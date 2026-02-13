CREATE DATABASE IF NOT EXISTS default;

CREATE TABLE IF NOT EXISTS default.logs_raw
(
  raw String,
  hostname String,
  address String
)
ENGINE = MergeTree
ORDER BY tuple();
