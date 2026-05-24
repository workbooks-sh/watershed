# `json.*` — JSON parse/encode

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

### `json.parse(s)`

**Classification:** `:pure`. **Portability:** required.

**Args:**
- `s` (string, required) — JSON-encoded string.

**Returns:** Lua value (table for objects/arrays, string/number/boolean for scalars,
`nil` for JSON null).

**Errors:**
- `JSON_PARSE_FAILED` — includes `details.position` (byte offset of the syntax error).

### `json.encode(v)`

**Classification:** `:pure`. **Portability:** required.

**Args:**
- `v` (any, required) — Lua value.

**Returns:** JSON string. Tables encoded as arrays if they're a sequence (keys
1..N), objects otherwise. Functions and userdata cause encoding failure.

**Errors:**
- `JSON_ENCODE_FAILED` — non-serializable value encountered; includes `details.path`.
