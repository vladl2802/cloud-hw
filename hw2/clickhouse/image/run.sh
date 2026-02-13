#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_HOST="127.0.0.1"
CLICKHOUSE_PORT="9000"

/usr/bin/clickhouse-server&
pid="$!"

for i in $(seq 1 60); do
  if clickhouse-client --host "${CLICKHOUSE_HOST}" --port "${CLICKHOUSE_PORT}" --query "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

clickhouse-client --host "${CLICKHOUSE_HOST}" --port "${CLICKHOUSE_PORT}" --multiquery < /docker-init/table.sql

wait "${pid}"
