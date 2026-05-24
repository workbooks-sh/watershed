# `broker.*` — Authenticated host endpoints

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

HTTP into Watershed's own operations API. Used when a Lua function needs to
trigger something the host exposes as a route (e.g., issuing a lease, fetching
audit chain verification).

### `broker.fetch(endpoint, opts?)`

**Classification:** `:effectful`. **Portability:** required.

Call a Watershed `/ops/*` endpoint with the current user's credentials.

**Args:**
- `endpoint` (string, required) — Endpoint path, e.g., `"/ops/audit/01HQ.../verify"`.
- `opts` (table, optional):
  - `method` (string) — `"GET"` (default), `"POST"`, `"PATCH"`, `"DELETE"`.
  - `body` (table) — Request body, JSON-encoded by the host.
  - `headers` (table) — Extra headers.

**Returns:** Response envelope `{ ok = true, data = ..., warnings = [...] }` on success;
raises on `ok = false`.

**Errors:**
- `BROKER_ENDPOINT_NOT_FOUND` — endpoint doesn't exist.
- `BROKER_AUTHZ_DENIED` — current user lacks operator permission for the endpoint.
- `BROKER_TIMEOUT` — 30s default; configurable per call via `opts.timeout`.

### `broker.execute(connection, action, args?)`

**Classification:** `:effectful`. **Portability:** required.

Run an integration action through a configured connection (OAuth provider, external
API). Wraps the connection's auth + rate-limit + audit log.

**Args:**
- `connection` (string, required) — Connection slug from `Orgs.Connection`.
- `action` (string, required) — Action name defined by the connection's adapter.
- `args` (table, optional) — Action arguments.

**Returns:** Adapter-defined response.

**Errors:**
- `CONNECTION_NOT_FOUND`.
- `CONNECTION_UNAUTHORIZED` — token expired/revoked.
- `INTEGRATION_RATE_LIMITED`.
- `INTEGRATION_ERROR` — upstream returned a non-2xx; includes `details.status` and `details.body`.
