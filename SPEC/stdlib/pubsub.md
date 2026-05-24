# `pubsub.*` — Broadcast / subscribe

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

Cross-process notifications. Underlies LiveView updates and inter-job signaling.

### `pubsub.broadcast(topic, payload)`

**Classification:** `:effectful`. **Portability:** required.

Broadcast `payload` to all subscribers of `topic` within the current workbook
scope. Topics are auto-prefixed by the host with `workbook:<id>:` to prevent
cross-workbook leakage.

**Args:**
- `topic` (string, required) — Workbook-scoped topic name, e.g., `"tasks-updated"`.
- `payload` (table, required) — Payload, JSON-serializable.

**Returns:** `nil`.

**Errors:** None — broadcasts are fire-and-forget.

### `pubsub.subscribe(topic, fn)`

**Classification:** `:effectful`. **Portability:** required. **Restricted to long-lived handlers.**

Subscribe to broadcasts on `topic`. The classifier rejects this in regular server
functions (which are short-lived per-request); valid only in long-running handlers
like agent stages or background-job loops.

**Args:**
- `topic` (string, required).
- `fn` (function, required) — Callback invoked per message with `(payload)`.

**Returns:** A subscription handle. Unsubscribe via `pubsub.unsubscribe(handle)` (TBD).

**Errors:**
- `PUBSUB_CONTEXT_INVALID` — called from a context that doesn't support subscriptions.
