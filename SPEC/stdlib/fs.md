# `fs.*` — Workbook-scoped blob storage

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

S3-backed (R2 default). All operations are auto-scoped to the current workbook;
Lua can't reach blobs in other workbooks.

### `fs.put(path, bytes, opts?)`

**Classification:** `:mutation`. **Portability:** required.

**Args:**
- `path` (string, required) — Workbook-relative path. Must not start with `/`
  or contain `..`.
- `bytes` (string, required) — Blob contents.
- `opts` (table, optional):
  - `content_type` (string) — MIME type. Default `application/octet-stream`.
  - `cache_control` (string).

**Returns:** `{ path = "...", size = N, etag = "..." }`.

**Errors:**
- `FS_PATH_INVALID`.
- `FS_QUOTA_EXCEEDED` — workbook hit its storage budget.
- `FS_BACKEND_ERROR` — S3-level failure; includes `details.code`.

### `fs.get(path)`

**Classification:** `:reactive` (read-only). **Portability:** required.

**Args:**
- `path` (string, required).

**Returns:** `{ bytes = "...", content_type = "...", size = N, etag = "..." }`.

**Errors:**
- `FS_PATH_INVALID`.
- `FS_NOT_FOUND`.
- `FS_BACKEND_ERROR`.

### `fs.list(prefix?)`

**Classification:** `:reactive`. **Portability:** required.

**Args:**
- `prefix` (string, optional) — Path prefix. Default `""` (list all).

**Returns:** Array of `{ path = "...", size = N, last_modified = "...", etag = "..." }`.

**Errors:**
- `FS_BACKEND_ERROR`.

### `fs.delete(path)`

**Classification:** `:mutation`. **Portability:** required.

**Args:**
- `path` (string, required).

**Returns:** `nil`.

**Errors:**
- `FS_PATH_INVALID`.
- `FS_NOT_FOUND`.
- `FS_BACKEND_ERROR`.
