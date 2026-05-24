# `time.*` — Clock access

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

### `time.now()`

**Classification:** `:effectful` (non-deterministic). **Portability:** required.

**Args:** none.

**Returns:** ISO 8601 timestamp string in UTC, e.g., `"2026-05-22T19:45:00Z"`.

### `time.monotonic()`

**Classification:** `:effectful`. **Portability:** required.

**Args:** none.

**Returns:** Monotonic timestamp in milliseconds (host-internal reference point).
Use for measuring durations within a single execution; not comparable across
processes or restarts.
