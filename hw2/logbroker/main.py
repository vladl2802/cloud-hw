# app.py
# Persistent on-disk buffering + flush to ClickHouse at most once per second.
#
# Guarantees:
# - write_log returns 200 only after the log batch is fsync'ed to disk
# - flush loop inserts to ClickHouse no more often than FLUSH_INTERVAL_SEC
# - survives restarts on same disk using (buffer.log + offset.meta)
# - at-least-once delivery (duplicates possible on retries), as allowed

import sys
import asyncio
import json
import os
import time
import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple, List

import httpx
from fastapi import FastAPI, Response, status
from pydantic import BaseModel


# -----------------------
# Config
# -----------------------

BUFFER_DIR = Path(os.getenv("BUFFER_DIR", "/var/lib/logbroker"))
BUFFER_DIR.mkdir(parents=True, exist_ok=True)

BUFFER_FILE = BUFFER_DIR / "buffer.log"     # jsonl: one event per line
OFFSET_FILE = BUFFER_DIR / "offset.meta"    # committed byte offset into buffer.log
FLUSH_INTERVAL_SEC = float(os.getenv("FLUSH_INTERVAL_SEC", "1.0"))

CLICKHOUSE_URL = os.getenv("CLICKHOUSE_URL", "http://192.168.10.10:8123")
CLICKHOUSE_TABLE = os.getenv("CLICKHOUSE_TABLE", "default.logs_raw")

# Limit one flush batch so we don't build huge requests
MAX_BATCH_LINES = int(os.getenv("MAX_BATCH_LINES", "10000"))
MAX_BATCH_BYTES = int(os.getenv("MAX_BATCH_BYTES", str(4 * 1024 * 1024)))  # 4 MiB

# Optional compaction to prevent unbounded file growth
COMPACT_AFTER_BYTES = int(os.getenv("COMPACT_AFTER_BYTES", str(256 * 1024 * 1024)))  # 256 MiB


# -----------------------
# API models (adjust to your HW stub if needed)
# -----------------------

class WriteLogRequest(BaseModel):
    logs: List[dict]


# -----------------------
# Disk spool (WAL)
# -----------------------

def _atomic_write_text(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def _read_offset(path: Path) -> int:
    try:
        return int(path.read_text(encoding="utf-8").strip() or "0")
    except FileNotFoundError:
        return 0
    except ValueError:
        return 0


@dataclass
class DiskSpool:
    buffer_path: Path
    offset_path: Path

    def __post_init__(self):
        self._write_lock = asyncio.Lock()
        self._fd = os.open(self.buffer_path, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o644)

    async def append_jsonl_lines(self, lines: List[bytes]) -> None:
        async with self._write_lock:
            for ln in lines:
                os.write(self._fd, ln)
            os.fsync(self._fd)

    def read_from_offset(self, offset: int, max_lines: int, max_bytes: int) -> Tuple[bytes, int]:
        if not self.buffer_path.exists():
            return b"", offset

        size = self.buffer_path.stat().st_size
        if offset >= size:
            return b"", offset

        with open(self.buffer_path, "rb") as f:
            f.seek(offset)
            data = f.read(max_bytes)

        if not data:
            return b"", offset

        last_nl = data.rfind(b"\n")
        if last_nl == -1:
            return b"", offset

        chunk = data[: last_nl + 1]
        if max_lines > 0:
            lines = chunk.splitlines(keepends=True)
            if len(lines) > max_lines:
                lines = lines[:max_lines]
                chunk = b"".join(lines)

        return chunk, offset + len(chunk)

    def commit_offset(self, new_offset: int) -> None:
        _atomic_write_text(self.offset_path, str(new_offset))

    def maybe_compact(self) -> None:
        committed = _read_offset(self.offset_path)
        if committed < COMPACT_AFTER_BYTES:
            return
        if not self.buffer_path.exists():
            return

        size = self.buffer_path.stat().st_size
        if committed >= size:
            with open(self.buffer_path, "wb") as f:
                f.truncate(0)
                f.flush()
                os.fsync(f.fileno())
            self.commit_offset(0)
            return

        tmp = self.buffer_path.with_suffix(".compact.tmp")
        with open(self.buffer_path, "rb") as src, open(tmp, "wb") as dst:
            src.seek(committed)
            while True:
                buf = src.read(8 * 1024 * 1024)
                if not buf:
                    break
                dst.write(buf)
            dst.flush()
            os.fsync(dst.fileno())
        os.replace(tmp, self.buffer_path)
        self.commit_offset(0)

    async def close(self):
        async with self._write_lock:
            try:
                os.fsync(self._fd)
            finally:
                os.close(self._fd)


class ClickHouseWriter:
    def __init__(self, base_url: str, table: str):
        self.base_url = base_url.rstrip("/")
        self.table = table
        self._client = httpx.AsyncClient(timeout=10.0)

    async def insert_raw_json_lines(self, jsonl: bytes) -> None:
        print("insert_raw_json_lines", file=sys.stderr)

        rows = []
        for ln in jsonl.splitlines():
            if not ln:
                continue
            rows.append(json.dumps({"raw": ln.decode("utf-8")}, ensure_ascii=False).encode("utf-8") + b"\n")

        print(rows, file=sys.stderr)

        if len(rows) == 0:
            return

        body = b"".join(rows)
        query = f"INSERT INTO {self.table} FORMAT JSONEachRow"
        r = await self._client.post(f"{self.base_url}/", params={"query": query}, content=body)
        print(r, file=sys.stderr)
        r.raise_for_status()

    async def close(self):
        await self._client.aclose()


class BufferedFlusher:
    def __init__(self, spool: DiskSpool, ch: ClickHouseWriter):
        self.spool = spool
        self.ch = ch
        self._stop = asyncio.Event()
        self._task: Optional[asyncio.Task] = None

    async def start(self):
        self._task = asyncio.create_task(self._run())

    async def stop_and_flush(self, hard_deadline_sec: float = 10.0):
        self._stop.set()
        if self._task:
            try:
                await asyncio.wait_for(self._task, timeout=hard_deadline_sec)
            except asyncio.TimeoutError:
                pass
        t0 = time.time()
        while time.time() - t0 < hard_deadline_sec:
            did = await self.flush_once()
            if not did:
                break

    async def _run(self):
        print("_run", file=sys.stderr)
        while not self._stop.is_set():
            await self.flush_once()
            try:
                await asyncio.wait_for(self._stop.wait(), timeout=FLUSH_INTERVAL_SEC)
            except asyncio.TimeoutError:
                pass

        await self.flush_once()

    async def flush_once(self) -> bool:
        committed = _read_offset(self.spool.offset_path)
        batch, new_offset = self.spool.read_from_offset(
            committed, max_lines=MAX_BATCH_LINES, max_bytes=MAX_BATCH_BYTES
        )
        if not batch:
            self.spool.maybe_compact()
            return False

        try:
            await self.ch.insert_raw_json_lines(batch)
        except Exception:
            return True

        self.spool.commit_offset(new_offset)
        self.spool.maybe_compact()
        return True


spool = DiskSpool(BUFFER_FILE, OFFSET_FILE)
ch = ClickHouseWriter(CLICKHOUSE_URL, CLICKHOUSE_TABLE)
flusher = BufferedFlusher(spool, ch)

@asynccontextmanager
async def lifespan(app: FastAPI):
    await flusher.start()
    yield
    # On shutdown: flush what we can and close resources
    await flusher.stop_and_flush()
    await ch.close()
    await spool.close()

app = FastAPI(lifespan=lifespan)

@app.get("/health")
async def health():
    return {"ok": True}

@app.post("/write_log")
async def write_log(req: WriteLogRequest):
    lines = []
    for event in req.logs:
        line = json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
        lines.append(line)

    if not lines:
        return Response(status_code=status.HTTP_200_OK)

    await spool.append_jsonl_lines(lines)
    return Response(status_code=status.HTTP_200_OK)
