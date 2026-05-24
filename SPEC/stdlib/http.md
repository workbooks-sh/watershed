# `http.*` — Outbound HTTP

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

Rate-limited, audited outbound HTTP. Routed through the host's egress proxy so
that all external calls land in the audit log.

### `http.get(url, opts?)`

**Classification:** `:effectful`. **Portability:** required.

**Args:**
- `url` (string, required) — `http://` or `https://` URL.
- `opts` (table, optional):
  - `headers` (table) — Request headers.
  - `query` (table) — Query string params, encoded by the host.
  - `timeout` (number) — Milliseconds. Default 30000. Max 120000.

**Returns:** `{ status = N, headers = {...}, body = "..." }`. `body` is the raw
string; callers JSON-decode if needed.

**Errors:**
- `HTTP_TIMEOUT`.
- `HTTP_DNS_FAILED`.
- `HTTP_TLS_FAILED`.
- `HTTP_BODY_TOO_LARGE` — response > 50MB.
- `HTTP_HOST_BLOCKED` — destination matches an egress denylist (RFC1918, etc.).
- `HTTP_RATE_LIMITED` — workbook hit its outbound budget.

### `http.post(url, body, opts?)`

**Classification:** `:effectful`. **Portability:** required.

**Args:**
- `url` (string, required).
- `body` (string or table, required) — If table, JSON-encoded and `Content-Type:
  application/json` set unless overridden.
- `opts` (table, optional) — Same as `http.get` plus content-type override.

**Returns:** Same shape as `http.get`.

**Errors:** Same as `http.get`.
