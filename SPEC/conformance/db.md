# `db.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: db.read returns empty array on empty table

`db.read` on an empty table must return `[]`, never `nil`.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.read("tasks")
```

#+EXPECT: exact
```json
[]
```

#+CLASSIFY: :reactive

---

### test: db.read returns all rows when no query

Reading without a query returns every row in the tenant scope.

#+SCHEMA: tasks_minimal
#+SEED: three_open_tasks

#+SCRIPT:
```lua
local rows = db.read("tasks", { order_by = "text" })
local texts = {}
for i, row in ipairs(rows) do texts[i] = row.text end
return texts
```

#+EXPECT: exact
```json
["alpha", "beta", "gamma"]
```

---

### test: db.read filters by where clause

Equality `where` filter excludes non-matching rows.

#+SCHEMA: tasks_minimal
#+SEED: mixed_status_tasks

#+SCRIPT:
```lua
local rows = db.read("tasks", { where = { status = "open" } })
return #rows
```

#+EXPECT: exact
```json
3
```

---

### test: db.read respects limit

`limit` caps the result set.

#+SCHEMA: tasks_minimal
#+SEED: three_open_tasks

#+SCRIPT:
```lua
local rows = db.read("tasks", { limit = 2 })
return #rows
```

#+EXPECT: exact
```json
2
```

---

### test: db.read rejects unknown table

`TABLE_NOT_FOUND` for tables not in the workbook schema.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.read("nonexistent")
```

#+EXPECT: error
TABLE_NOT_FOUND

---

### test: db.read rejects limit over cap

Limit > 10,000 raises `LIMIT_EXCEEDED`.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.read("tasks", { limit = 100000 })
```

#+EXPECT: error
LIMIT_EXCEEDED

---

### test: db.read_one returns row by id

`db.read_one` returns the matching row's shape.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
local created = db.write("tasks", { text = "find me", status = "open", done = false })
return db.read_one("tasks", created.id)
```

#+EXPECT: shape
```json
{
  "id": "@uuid",
  "text": "find me",
  "status": "open",
  "done": false,
  "created_at": "@timestamp"
}
```

---

### test: db.read_one returns nil on miss

Missing primary key returns `nil`, does not error.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.read_one("tasks", "00000000-0000-0000-0000-000000000000")
```

#+EXPECT: exact
```json
null
```

---

### test: db.read_many preserves order

Results returned in the same order as input IDs.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
local a = db.write("tasks", { text = "a", status = "open", done = false })
local b = db.write("tasks", { text = "b", status = "open", done = false })
local c = db.write("tasks", { text = "c", status = "open", done = false })
local rows = db.read_many("tasks", { c.id, a.id, b.id })
return { rows[1].text, rows[2].text, rows[3].text }
```

#+EXPECT: exact
```json
["c", "a", "b"]
```

---

### test: db.read_many silently skips missing ids

Missing IDs are omitted from the result (no error).

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
local a = db.write("tasks", { text = "a", status = "open", done = false })
local rows = db.read_many("tasks", {
  "00000000-0000-0000-0000-000000000000",
  a.id,
  "11111111-1111-1111-1111-111111111111",
})
return #rows
```

#+EXPECT: exact
```json
1
```

---

### test: db.write returns inserted row with generated fields

`db.write` returns the full row with id + timestamps populated.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.write("tasks", { text = "new", status = "open", done = false })
```

#+EXPECT: shape
```json
{
  "id": "@uuid",
  "text": "new",
  "status": "open",
  "done": false,
  "created_at": "@timestamp"
}
```

#+CLASSIFY: :mutation

---

### test: db.write rejects mismatched tenant_id

Explicit `tenant_id` in record must match `ctx.tenant` or `TENANT_MISMATCH`.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.write("tasks", {
  text = "spoof",
  status = "open",
  done = false,
  tenant_id = "00000000-0000-0000-0000-000000000000",
})
```

#+EXPECT: error
TENANT_MISMATCH

---

### test: db.update patches specific fields

`db.update` modifies only the named fields.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
local created = db.write("tasks", { text = "before", status = "open", done = false })
local updated = db.update("tasks", created.id, { status = "done", done = true })
return { text = updated.text, status = updated.status, done = updated.done }
```

#+EXPECT: exact
```json
{ "text": "before", "status": "done", "done": true }
```

---

### test: db.update rejects unknown id

Missing row raises `ROW_NOT_FOUND`.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
return db.update("tasks", "00000000-0000-0000-0000-000000000000", { status = "done" })
```

#+EXPECT: error
ROW_NOT_FOUND

---

### test: db.delete returns the deleted row

Delete returns the row's last view before removal.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
local created = db.write("tasks", { text = "doomed", status = "open", done = false })
local deleted = db.delete("tasks", created.id)
local check = db.read_one("tasks", created.id)
return { deleted_text = deleted.text, gone = check == nil }
```

#+EXPECT: exact
```json
{ "deleted_text": "doomed", "gone": true }
```

---

### test: db.transaction commits on success

Multiple writes inside a transaction all land.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
db.transaction(function()
  db.write("tasks", { text = "first", status = "open", done = false })
  db.write("tasks", { text = "second", status = "open", done = false })
end)
return #db.read("tasks")
```

#+EXPECT: exact
```json
2
```

---

### test: db.transaction rolls back on error

An error inside `db.transaction` rolls back all writes.

#+SCHEMA: tasks_minimal

#+SCRIPT:
```lua
local ok, err = pcall(function()
  db.transaction(function()
    db.write("tasks", { text = "first", status = "open", done = false })
    error("synthetic failure")
  end)
end)
return { committed = ok, row_count = #db.read("tasks") }
```

#+EXPECT: exact
```json
{ "committed": false, "row_count": 0 }
```

---

### test: db.raw runs a SELECT with parameters

Raw SQL with parameter binding returns rows and columns.

#+SCHEMA: tasks_minimal
#+SEED: three_open_tasks

#+SCRIPT:
```lua
local result = db.raw(
  "SELECT count(*) AS n FROM tasks WHERE tenant_id = $1 AND status = $2",
  { ctx.tenant, "open" }
)
return result.rows[1].n
```

#+EXPECT: exact
```json
3
```

#+CLASSIFY: :mutation
