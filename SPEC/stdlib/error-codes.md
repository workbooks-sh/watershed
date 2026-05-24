# Error code reference

> Part of the [Watershed stdlib](./README.md). The codes below are referenced
> by every per-namespace spec.

Stable error codes used across the stdlib. Lua callers branch on `err.code`.
Codes are namespaced by category for searchability.

### General

- `NOT_IMPLEMENTED` — host doesn't implement this function.
- `TIMEOUT` — generic timeout (function-specific codes preferred where applicable).
- `INTERNAL` — host-internal failure; trace_id included.

### `db.*`

- `TABLE_NOT_FOUND` — table not in workbook schema.
- `ROW_NOT_FOUND` — primary key match failed.
- `QUERY_INVALID` — query shape rejected.
- `LIMIT_EXCEEDED` — limit > 10,000.
- `IDS_TOO_MANY` — read_many with > 1,000 IDs.
- `CONSTRAINT_VIOLATION` — unique/foreign-key/check.
- `VALIDATION_FAILED` — Ash validation rejected.
- `TENANT_MISMATCH` — record's tenant_id != ctx.tenant.
- `FOREIGN_KEY_RESTRICT` — delete blocked by FK.
- `SQL_INVALID` — raw query parse error.
- `SQL_EXECUTION_FAILED` — raw query runtime error.

### `broker.*`

- `BROKER_ENDPOINT_NOT_FOUND`.
- `BROKER_AUTHZ_DENIED`.
- `BROKER_TIMEOUT`.
- `CONNECTION_NOT_FOUND`.
- `CONNECTION_UNAUTHORIZED`.
- `INTEGRATION_RATE_LIMITED`.
- `INTEGRATION_ERROR`.

### `agent.*`

- `AGENT_NOT_FOUND`.
- `AGENT_BUDGET_EXCEEDED`.
- `AGENT_FAILED`.
- `AGENT_RUN_NOT_FOUND`.

### `oban.*`

- `WORKER_NOT_FOUND`.
- `QUEUE_NOT_FOUND`.
- `ARGS_TOO_LARGE`.
- `CRON_INVALID`.

### `pubsub.*`

- `PUBSUB_CONTEXT_INVALID`.

### `http.*`

- `HTTP_TIMEOUT`.
- `HTTP_DNS_FAILED`.
- `HTTP_TLS_FAILED`.
- `HTTP_BODY_TOO_LARGE`.
- `HTTP_HOST_BLOCKED`.
- `HTTP_RATE_LIMITED`.

### `crypto.*`

- `CRYPTO_ALGO_UNSUPPORTED`.

### `json.*`

- `JSON_PARSE_FAILED`.
- `JSON_ENCODE_FAILED`.

### `worg.*`

- `WORG_PARSE_FAILED`.
- `WORG_HEADLINE_NOT_FOUND`.
- `WORG_STATE_INVALID`.

### `fs.*`

- `FS_PATH_INVALID`.
- `FS_NOT_FOUND`.
- `FS_QUOTA_EXCEEDED`.
- `FS_BACKEND_ERROR`.

### Resource limits (per-call)

- `LUA_DEADLINE_EXCEEDED` — script exceeded wall-clock cap.
- `LUA_MEMORY_EXCEEDED` — script exceeded heap cap.
- `LUA_REDUCTIONS_EXCEEDED` — script exceeded BEAM reduction count.
