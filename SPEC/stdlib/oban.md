# `oban.*` — Background jobs

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

Enqueue work to run outside the current request lifecycle.

### `oban.enqueue(worker, args, opts?)`

**Classification:** `:effectful`. **Portability:** required.

Enqueue a job. Workers are registered by name (Elixir worker modules) or by Lua
function reference (host wraps in a generic Elixir worker).

**Args:**
- `worker` (string, required) — Worker name, e.g., `"send_email"`, `"index_document"`.
- `args` (table, required) — Job payload, JSON-serializable.
- `opts` (table, optional):
  - `queue` (string) — Queue name. Default `"default"`.
  - `priority` (number) — 0–3. Default 1.
  - `schedule_in` (number) — Seconds to defer. Default 0.
  - `unique` (table) — Uniqueness rules; see Oban docs.
  - `max_attempts` (number) — Default 5.

**Returns:** `{ id = "...", state = "available", queue = "...", inserted_at = "..." }`.

**Errors:**
- `WORKER_NOT_FOUND`.
- `QUEUE_NOT_FOUND`.
- `ARGS_TOO_LARGE` — args serialize to > 1MB.

### `oban.schedule(worker, cron, args?)`

**Classification:** `:effectful`. **Portability:** required.

Register a cron-scheduled job.

**Args:**
- `worker` (string, required).
- `cron` (string, required) — Crontab syntax, e.g., `"0 9 * * 1-5"`.
- `args` (table, optional).

**Returns:** `{ id = "...", schedule = "..." }`.

**Errors:**
- `WORKER_NOT_FOUND`.
- `CRON_INVALID`.
