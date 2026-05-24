# Setup fixtures

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

These schemas + seed data are reused across many tests. Tests reference them
by name in their `#+SCHEMA:` and `#+SEED:` headers.

### fixture: `tasks_minimal`

A single `tasks` table — the simplest schema for db.* tests.

```lua
-- @fixture:tasks_minimal
return {
  tasks = {
    fields = {
      id = "uuid",
      text = "string",
      status = "string",
      done = "boolean",
      created_at = "timestamp",
    },
    tenant = "current_user",
    indexes = { "status", "created_at" },
  },
}
```

### fixture: `tasks_with_assignee`

`tasks` + `users` with a foreign key. For relational tests.

```lua
-- @fixture:tasks_with_assignee
return {
  users = {
    fields = { id = "uuid", email = "string", display_name = "string" },
    tenant = "current_user",
  },
  tasks = {
    fields = {
      id = "uuid",
      text = "string",
      status = "string",
      assigned_to = "uuid?",   -- nullable FK to users.id
    },
    tenant = "current_user",
    indexes = { "assigned_to" },
  },
}
```

### seed: `three_open_tasks`

Three tasks in `:open` state. Run after applying `tasks_minimal`.

```lua
-- @seed:three_open_tasks
db.write("tasks", { text = "alpha",   status = "open",   done = false })
db.write("tasks", { text = "beta",    status = "open",   done = false })
db.write("tasks", { text = "gamma",   status = "open",   done = false })
```

### seed: `mixed_status_tasks`

Three open, two done. For filter tests.

```lua
-- @seed:mixed_status_tasks
db.write("tasks", { text = "alpha",   status = "open", done = false })
db.write("tasks", { text = "beta",    status = "open", done = false })
db.write("tasks", { text = "gamma",   status = "open", done = false })
db.write("tasks", { text = "delta",   status = "done", done = true  })
db.write("tasks", { text = "epsilon", status = "done", done = true  })
```
