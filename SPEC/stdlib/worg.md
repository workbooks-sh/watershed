# `worg.*` — Org-mode document operations (host-optional)

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

WORG parser/mutator bindings. A host that doesn't implement WORG surfaces
`NOT_IMPLEMENTED` for these.

### `worg.parse(text)`

**Classification:** `:pure`. **Portability:** host-optional.

**Args:**
- `text` (string, required) — Org-mode document text.

**Returns:** Parsed AST (host-defined shape; mirrors WORG's Rust/Elixir
representation).

**Errors:**
- `WORG_PARSE_FAILED` — includes `details.line`.
- `NOT_IMPLEMENTED` (host without WORG support).

### `worg.query(text, predicate)`

**Classification:** `:reactive` (read-only on the document). **Portability:** host-optional.

**Args:**
- `text` (string, required) — Org document.
- `predicate` (table, required) — WORG query predicate. See `packages/worg/`
  for the predicate vocabulary.

**Returns:** Array of matching headlines.

**Errors:**
- `WORG_PARSE_FAILED`.
- `NOT_IMPLEMENTED`.

### `worg.update_todo(text, id, new_state)`

**Classification:** `:mutation` (on the document text). **Portability:** host-optional.

**Args:**
- `text` (string, required).
- `id` (string, required) — Headline `:ID:` property.
- `new_state` (string, required) — TODO keyword.

**Returns:** Updated org document text.

**Errors:**
- `WORG_HEADLINE_NOT_FOUND`.
- `WORG_STATE_INVALID`.
- `NOT_IMPLEMENTED`.

### `worg.append_logbook(text, id, entry)`

**Classification:** `:mutation`. **Portability:** host-optional.

**Args:**
- `text` (string, required).
- `id` (string, required).
- `entry` (string or table, required) — Logbook entry.

**Returns:** Updated org document text.

**Errors:**
- `WORG_HEADLINE_NOT_FOUND`.
- `NOT_IMPLEMENTED`.
