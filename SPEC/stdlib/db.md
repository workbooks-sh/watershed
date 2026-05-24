# `db.*` — Data layer

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

Read and write the host's Postgres-backed data. Routed through Ash actions; tenant
auto-scoped.

### `db.read(table, query?)`

**Classification:** `:reactive`. **Portability:** required.

Read multiple rows from `table` matching `query`.

**Args:**
- `table` (string, required) — Table name declared in `workbook.schema.lua`.
- `query` (table, optional) — Filter and pagination. Default: all rows (tenant-scoped).
  - `where` (table) — Equality filters: `{ status = "open", priority = 1 }`. **`WHERE`-only**
    at v1 (Phoenix.Sync constraint). Joins, ranges, IN-clauses arrive when Phoenix.Sync
    supports them.
  - `order_by` (string or table) — Column or `{ column = "asc"|"desc" }`. Falls back to
    primary key ascending.
  - `limit` (number) — Max rows. Default 100. Hard cap 10,000.

**Returns:** Array of row tables. Empty array `{}` on no match; never `nil`.

**Errors:**
- `TABLE_NOT_FOUND` — table not in workbook schema.
- `QUERY_INVALID` — query shape rejected (e.g., unsupported filter operator).
- `LIMIT_EXCEEDED` — limit > 10,000.

**Reactivity:** Becomes a Phoenix.Sync shape when the enclosing server function is
classified `:reactive`. The shape's `WHERE` clause always includes `tenant_id =
ctx.tenant` injected by the host — Lua cannot omit it.

**Example:**

```lua
local tasks = db.read("tasks", {
  where = { status = args.status or "open" },
  order_by = "created_at",
  limit = 50,
})
```

### `db.read_one(table, id)`

**Classification:** `:reactive`. **Portability:** required.

Read exactly one row by primary key.

**Args:**
- `table` (string, required).
- `id` (string, required) — Primary key. UUID format expected.

**Returns:** Row table or `nil` if not found. Use `nil` check — does not error.

**Errors:**
- `TABLE_NOT_FOUND`.

**Example:**

```lua
local task = db.read_one("tasks", args.task_id)
if not task then
  error({ code = "TASK_NOT_FOUND", message = "no task with id " .. args.task_id })
end
```

### `db.read_many(table, ids)`

**Classification:** `:reactive`. **Portability:** required.

Read multiple rows by primary key.

**Args:**
- `table` (string, required).
- `ids` (array of string, required) — UUIDs.

**Returns:** Array of row tables, in the same order as `ids`. Missing rows are
omitted from the result (callers should compare lengths if they need to detect
gaps).

**Errors:**
- `TABLE_NOT_FOUND`.
- `IDS_TOO_MANY` — more than 1,000 IDs in one call.

### `db.write(table, record)`

**Classification:** `:mutation`. **Portability:** required.

Insert a new row.

**Args:**
- `table` (string, required).
- `record` (table, required) — Column values. Primary key auto-generated if not
  provided. `tenant_id` injected by host; if present in `record`, must match
  `ctx.tenant` or `TENANT_MISMATCH` is raised.

**Returns:** The inserted row table including auto-generated fields (id, timestamps).

**Errors:**
- `TABLE_NOT_FOUND`.
- `CONSTRAINT_VIOLATION` — unique/foreign-key/check constraint failed. Includes
  `details.constraint` with the constraint name.
- `TENANT_MISMATCH` — record's `tenant_id` doesn't match `ctx.tenant`.
- `VALIDATION_FAILED` — Ash validation rejected the record.

**Transactionality:** Wrapped in the enclosing server function's transaction.
A `:mutation` server function that calls multiple `db.write` is atomic by default.

**Example:**

```lua
return db.write("tasks", {
  text = args.text,
  status = "open",
  created_by = ctx.user.id,
})
```

### `db.update(table, id, patch)`

**Classification:** `:mutation`. **Portability:** required.

Update specific fields on a row.

**Args:**
- `table` (string, required).
- `id` (string, required) — Primary key.
- `patch` (table, required) — Columns to update. Missing keys are unchanged.

**Returns:** The updated row table.

**Errors:**
- `TABLE_NOT_FOUND`.
- `ROW_NOT_FOUND`.
- `CONSTRAINT_VIOLATION`.
- `VALIDATION_FAILED`.

### `db.delete(table, id)`

**Classification:** `:mutation`. **Portability:** required.

Delete a row by primary key.

**Args:**
- `table` (string, required).
- `id` (string, required).

**Returns:** The deleted row table (last view before deletion).

**Errors:**
- `TABLE_NOT_FOUND`.
- `ROW_NOT_FOUND`.
- `FOREIGN_KEY_RESTRICT` — row is referenced by another table with `ON DELETE RESTRICT`.

### `db.transaction(fn)`

**Classification:** `:mutation`. **Portability:** required.

Run `fn` as an explicit transaction. Multiple `db.write`/`update`/`delete` calls
inside `fn` are atomic. Calls to effectful functions inside `fn` are forbidden
(classifier rejects).

**Args:**
- `fn` (function, required) — Lua function taking no args. Return value is
  the transaction result.

**Returns:** Whatever `fn` returns.

**Errors:**
- Any error raised inside `fn` rolls back and re-raises.

**Example:**

```lua
return db.transaction(function()
  local task = db.write("tasks", { text = args.text })
  db.write("audit_entries", { action = "task_created", task_id = task.id })
  return task
end)
```

### `db.raw(query, params?)`

**Classification:** `:mutation` (conservative — even read-only raw SQL is treated
as mutation to opt out of reactivity). **Portability:** required.

Escape hatch for SQL that Ash can't express. Raw parameterized query.

**Args:**
- `query` (string, required) — SQL with `$1`, `$2` placeholders. **Never** interpolate
  user values into the string — use parameters.
- `params` (array, optional) — Parameter values. Default empty array.

**Returns:** `{ rows = [...], columns = [...], num_rows = N }` for SELECTs;
`{ num_rows = N }` for INSERT/UPDATE/DELETE/DDL.

**Errors:**
- `SQL_INVALID` — parse error.
- `SQL_EXECUTION_FAILED` — runtime error; includes `details.pg_code`.

**Tenancy:** **Not auto-scoped.** Caller must include `WHERE tenant_id = $N`
explicitly. Watershed lints raw queries for missing tenant filters at publish
time and warns; the lint cannot reject because some legitimate raw queries
target tenant-agnostic system tables.

**Example:**

```lua
local result = db.raw([[
  SELECT date_trunc('day', created_at) as day, COUNT(*) as n
  FROM tasks
  WHERE tenant_id = $1 AND created_at >= $2
  GROUP BY day
  ORDER BY day
]], { ctx.tenant, args.since })
```
