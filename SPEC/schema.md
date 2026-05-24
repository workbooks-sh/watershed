# Watershed Schema Declaration Specification

> Defines the `workbook.schema.lua` file format — the declarative way a
> workbook author describes its data shapes. Watershed compiles this into
> Ash resource modules at publish time.
>
> Status: v0 draft. Refine as the vertical slice exercises codegen.
>
> Cross-references: [PLAN.md §5](../PLAN.md) (schema declaration overview),
> [DECISIONS.md §2.7](../DECISIONS.md) (Ash + Postgres choice),
> [DECISIONS.md §2.8](../DECISIONS.md) (multitenancy model),
> [stdlib/db.md](./stdlib/db.md) (how `db.*` calls resolve against these resources),
> [LIBRARIES.md](../LIBRARIES.md) (Ash 3.x docs).

---

## 1. What `workbook.schema.lua` is

Every workbook that uses Watershed's data layer ships a single file at its
root: `workbook.schema.lua`. The file returns a Lua table describing every
persisted data shape the workbook owns. Watershed's CLI consumes this file
at publish time and produces:

1. Ash resource modules registered with the host's Phoenix app.
2. Generated Postgres migrations (via `mix ash_postgres.generate_migrations`).
3. A `_generated/api.ts` file the workbook's Svelte client uses for
   type-safe `subscribe()` / `call()` against `db.read*` / `db.write*` /
   etc.

Authors edit `workbook.schema.lua` directly. They never touch generated
files; they never write Elixir or Ecto migrations by hand.

## 2. File shape

A schema file is a Lua module returning a single table:

```lua
-- workbook.schema.lua
return {
  -- Each top-level key is a table name. Values are table definitions.
  tasks = {
    fields = { ... },
    tenant = "current_user",
    indexes = { ... },
  },

  findings = {
    fields = { ... },
    tenant = "workspace",
    -- ...
  },

  -- ...
}
```

Table names use `snake_case`. Pluralization is convention but not enforced;
the codegen uses the table name verbatim for the Postgres table and the
Ash resource module name (singularized via Inflex — `tasks` → `Tasks`
resource, `findings` → `Findings`).

A schema file may declare:

| Key | Required | Purpose |
|---|---|---|
| Table names (top-level keys) | At least one | The tables this workbook owns. |
| `_meta` | No | Workbook-wide metadata (schema version, etc.). See §11. |
| `_extends` | No | Schema composition — pull in shared schemas. See §12. |

Any unknown top-level key raises a `SCHEMA_INVALID` error at publish time.

## 3. Table definition shape

Each table's value is a table with these keys:

```lua
tasks = {
  -- Required
  fields = { ... },           -- §4

  -- Tenancy (required; one of the values in §5)
  tenant = "current_user",

  -- Optional
  indexes = { ... },          -- §6
  unique = { ... },           -- §6
  relations = { ... },        -- §7
  policies = { ... },         -- §8
  computed = { ... },         -- §9

  -- Optional metadata
  description = "...",        -- For the admin UI + codegen comments
  reactive = true,            -- Default true — table can back reactive shapes
}
```

Required keys: `fields`, `tenant`. Everything else is optional.

## 4. Field types

`fields` is a Lua table mapping column names to type declarations.

```lua
fields = {
  id = "uuid",
  text = "string",
  status = "string",
  done = "boolean",
  priority = "number",
  created_at = "timestamp",
  metadata = "json",
  description = "text",
  assignee_id = "uuid?",        -- nullable
  tags = "string[]",            -- array
  owner_email = "email",        -- string subtype with validation
}
```

### 4.1 Primitive types

| Type | Postgres | Lua representation | Notes |
|---|---|---|---|
| `"uuid"` | `uuid` | string | Default for primary keys. |
| `"string"` | `varchar(255)` | string | Use `"text"` for unbounded. |
| `"text"` | `text` | string | No length cap. |
| `"number"` | `numeric` or `bigint` | number | Subtype inferred from usage; explicit `"integer"` / `"float"` / `"decimal"` overrides. |
| `"integer"` | `bigint` | number | Whole numbers. |
| `"float"` | `double precision` | number | IEEE 754. |
| `"decimal"` | `numeric(precision, scale)` | string | Returned as string to preserve precision. Default `numeric(19, 4)`. |
| `"boolean"` | `boolean` | boolean | |
| `"timestamp"` | `timestamptz` | ISO 8601 string | Always UTC. |
| `"date"` | `date` | string `"YYYY-MM-DD"` | |
| `"json"` | `jsonb` | table | Deeply converted to/from Lua tables. |
| `"bytes"` | `bytea` | string (binary-safe) | Not UTF-8 decoded. |

### 4.2 Nullable

Append `?` to make a field nullable:

```lua
fields = {
  id = "uuid",
  assignee_id = "uuid?",       -- nullable foreign key
  description = "text?",
}
```

Required fields default to NOT NULL. Missing required fields on `db.write`
raise `VALIDATION_FAILED`.

### 4.3 Arrays

Append `[]` to make a field an array:

```lua
fields = {
  tags = "string[]",            -- Postgres text[]
  scores = "number[]",
  attachment_ids = "uuid[]",
}
```

Empty arrays serialize as `[]`, not `nil`. Nullable arrays use `"string[]?"`.

### 4.4 Identity / system types

| Type | Purpose |
|---|---|
| `"user_id"` | Foreign key to `Identity.User` (the platform user table). Resolves to `uuid`. |
| `"workspace_id"` | Foreign key to `Orgs.Group` (workspace tenant). Resolves to `uuid`. |
| `"workbook_id"` | Foreign key to `Workbooks.Workbook`. Resolves to `uuid` (base64url-encoded). |
| `"email"` | String with email validation. |
| `"url"` | String with URL validation. |

These compile to the underlying Postgres type with the foreign-key relationship
inferred. The codegen wires up the `belongs_to` to the platform-side resource.

### 4.5 Foreign keys to workbook tables

To reference another table in the same workbook, use the bare `uuid` type and
declare the relationship explicitly in `relations` (§7). Don't embed the
relationship in the type:

```lua
-- DO
fields = {
  id = "uuid",
  task_id = "uuid",
},
relations = {
  task = { belongs_to = "tasks", via = "task_id" },
},

-- DON'T  (no implicit FK inference)
fields = {
  task_id = "ref(tasks)",
},
```

This explicit form is verbose but unambiguous, and it keeps `fields` as a
pure declaration of columns rather than a hybrid columns+relations table.

### 4.6 Defaults

Field defaults use the long form table syntax:

```lua
fields = {
  status = { type = "string", default = "open" },
  done = { type = "boolean", default = false },
  created_at = { type = "timestamp", default = "now()" },
  retries = { type = "integer", default = 0 },
}
```

The string `"now()"` is a special marker resolved to `NOW()` at the
Postgres level — not interpolated client-side. Other defaults are Lua
literals (string, number, boolean, table for JSON).

Mixing short and long forms in the same `fields` table is allowed:

```lua
fields = {
  id = "uuid",                                  -- short
  status = { type = "string", default = "open" },  -- long
  text = "string",                              -- short
}
```

### 4.7 Auto-managed fields

Every table implicitly gets these unless explicitly overridden:

| Auto field | Type | Behavior |
|---|---|---|
| `id` | `uuid` (v7) | Primary key. Auto-generated on insert. Time-ordered for index locality. |
| `tenant_id` | `uuid` | Tenant scope. Injected from `ctx.tenant`; Lua cannot set or read it as a regular column. |
| `created_at` | `timestamp` | Auto-set on insert. |
| `updated_at` | `timestamp` | Auto-set on insert and update. |

Authors can override any of these by declaring them in `fields`:

```lua
-- Override id type to use natural keys instead of uuid
fields = {
  id = "string",   -- e.g., for slug-keyed tables
  -- ...
}
```

`tenant_id` is special — it can be omitted but not redefined to a different
type. The host always writes it as a uuid.

## 5. Tenancy

Every table declares its tenant scope via the `tenant` field. Required.

| Value | Meaning |
|---|---|
| `"current_user"` | One scope per user. The classic personal-data case. `tenant_id = ctx.user.id`. |
| `"workspace"` | One scope per `Orgs.Group`. Multi-user shared data. `tenant_id = ctx.workspace_id`. |
| `"workbook"` | One scope per workbook instance. Each installation of a workbook gets its own row set. `tenant_id = workbook.id`. |
| `"shared"` | No tenant scope — global to the host. Reserved for system tables; rarely used in author schemas. Requires explicit `--@shared-data` annotation on the schema. |

Tenant scope is enforced at the Ash policy layer (DECISIONS §2.8). Lua's
`db.*` calls implicitly filter on `tenant_id`; cross-tenant queries are
impossible from inside Lua. The host sets `tenant_id`; authors cannot.

### 5.1 Tenant context

`ctx.tenant` resolves to the row in the relevant tenant table:

- `tenant = "current_user"` → `ctx.user.id`
- `tenant = "workspace"` → the active workspace ID for the current user
- `tenant = "workbook"` → the workbook instance ID
- `tenant = "shared"` → unset; queries bypass tenant filter

Inside Lua, you can read `ctx.tenant` as a string but never modify it.

### 5.2 Cross-tenant references

A workbook table can reference platform tables (`Identity.User`,
`Orgs.Group`) without tenant restriction — these are global. But a table
in workbook A cannot reference rows in workbook B's tables; the tenant
boundary holds.

## 6. Indexes

```lua
indexes = {
  "status",                                 -- single column
  "created_at",
  { "status", "priority" },                 -- composite
  { fields = "email", unique = true },      -- unique single-column
  { fields = { "workspace_id", "slug" }, unique = true },  -- unique composite
  { fields = "tags", method = "gin" },      -- gin index for array
}
```

Two shorthand forms:
- String: single-column non-unique index on the named field.
- Array: composite non-unique index on the listed fields.

For unique or method-overridden indexes, use the long table form.

`unique = { "field_name" }` is also accepted as sugar for `unique`:

```lua
unique = { "slug" },                 -- shorthand
-- equivalent to:
indexes = { { fields = "slug", unique = true } },
```

`tenant_id` is implicitly included in every index unless `tenant = "shared"`.
The codegen prepends `tenant_id` to composite indexes for query efficiency.

## 7. Relationships

```lua
findings = {
  fields = {
    id = "uuid",
    topic = "string",
    task_id = "uuid",
    reviewer_id = "user_id",
  },
  tenant = "workspace",
  relations = {
    -- Single-row references (foreign keys)
    task = { belongs_to = "tasks", via = "task_id" },
    reviewer = { belongs_to = "platform.users", via = "reviewer_id" },

    -- Reverse references
    -- (Declared on the OTHER table, but mentioned here for symmetry)
  },
}

tasks = {
  fields = { id = "uuid", text = "string" },
  tenant = "workspace",
  relations = {
    findings = { has_many = "findings", via = "task_id" },
    primary_assignee = { has_one = "task_assignments", via = "task_id" },
  },
}
```

| Kind | Cardinality | Notes |
|---|---|---|
| `belongs_to` | This row references one row on the other side. Stores the FK on this table. | Most common. |
| `has_many` | One row on this side references many on the other side. FK is on the other table. | |
| `has_one` | Like `has_many` but enforces "at most one." | |
| `many_to_many` | Through a join table. | Declare with `through` and `via` keys; see §7.1. |

### 7.1 Many-to-many

```lua
tasks = {
  -- ...
  relations = {
    tags = {
      many_to_many = "tags",
      through = "task_tags",
      via = "task_id",
      paired = "tag_id",
    },
  },
}

task_tags = {
  fields = {
    id = "uuid",
    task_id = "uuid",
    tag_id = "uuid",
  },
  tenant = "workspace",
  unique = { { "task_id", "tag_id" } },
}
```

The join table is a normal workbook table. The `many_to_many` declaration
on one side is enough — the codegen wires the reverse direction.

### 7.2 References to platform tables

Use the `platform.` prefix for FKs to platform-side Ash domains:

| Platform reference | Maps to |
|---|---|
| `platform.users` | `Identity.User` |
| `platform.workspaces` | `Orgs.Group` |
| `platform.workbooks` | `Workbooks.Workbook` |
| `platform.agents` | `Agents.Agent` |

These are read-only from workbook code — you can reference users but you
can't create or modify them through workbook `db.*` calls.

## 8. Policies

Tenancy is enforced automatically. For finer-grained access control,
declare policies:

```lua
tasks = {
  -- ...
  policies = {
    -- Anyone in the workspace can read tasks
    read = "workspace_member",

    -- Only the creator can update
    update = { creator_only = true },

    -- Only workspace admins can delete
    delete = "workspace_admin",
  },
}
```

Policy values are either strings (named policy from a small set) or tables
(structured rules).

### 8.1 Built-in policy names

| Policy | Meaning |
|---|---|
| `"public"` | Anyone, including unauthenticated. Rare for workbook data. |
| `"authenticated"` | Any signed-in user. |
| `"current_user"` | Only the user whose `tenant_id` matches the row's `tenant_id`. Default for `tenant = "current_user"` tables. |
| `"workspace_member"` | Any member of the row's workspace. Default for `tenant = "workspace"` tables. |
| `"workspace_admin"` | Workspace members with admin role. |
| `"creator_only"` | Only the user whose `id == row.created_by`. Requires the table to have a `created_by user_id` field. |

### 8.2 Custom policy expressions

For one-off rules, use a table:

```lua
policies = {
  update = {
    or = {
      "workspace_admin",
      { creator_only = true },
      { has_role = "editor" },
    },
  },
}
```

Custom expressions compile to Ash policy clauses. The set of supported
combinators (`or`, `and`, `not`, `has_role`, `field_equals`) is
documented in the codegen module. v0 starts conservative; new combinators
are minor-version bumps.

## 9. Computed fields

Fields derived from other columns or relations.

```lua
tasks = {
  fields = {
    id = "uuid",
    text = "string",
    done = "boolean",
    completed_at = "timestamp?",
  },
  computed = {
    is_overdue = {
      type = "boolean",
      from = "done = false AND created_at < (NOW() - INTERVAL '7 days')",
    },
    finding_count = {
      type = "integer",
      from_aggregate = { count = "findings" },
    },
  },
}
```

Two forms:

- `from`: a SQL expression. Compiled to a Postgres generated column or
  view, depending on volatility.
- `from_aggregate`: a relationship aggregate. Compiled to an Ash
  aggregate calculation.

Computed fields are read-only — they appear in `db.read*` results but
can't be set via `db.write` or `db.update`.

## 10. Reactive shape compatibility

`db.read*` calls on the table become Phoenix.Sync shapes when the
enclosing server function is `:reactive` (see PLAN §4, stdlib/db.md).
Per LIBRARIES.md, Phoenix.Sync v0.6 supports only `WHERE`-only shape
queries. Schema design implications:

- A reactive `db.read("tasks", { where = { status = "open" } })` works.
- A reactive query with joins, order_by, limit, or preloads is REJECTED
  by the classifier at publish time (until Phoenix.Sync gains support).
- For complex queries, the author can either denormalize the schema (cheaper
  reads, more storage) or accept that the function is `:effectful` rather
  than `:reactive` (no live subscription, but full query power).

To make a table explicitly non-reactive (e.g., for archival data that
should never back a live subscription), set `reactive = false`:

```lua
audit_log = {
  fields = { ... },
  tenant = "workspace",
  reactive = false,            -- db.read on this table is :effectful, never :reactive
}
```

This is a hint to the classifier; queries against the table opt out of
reactivity, no exceptions.

## 11. Metadata

Top-level `_meta` table for workbook-wide schema metadata:

```lua
return {
  _meta = {
    schema_version = 3,           -- For migration tracking
    description = "Task tracker schema for the productivity workbook",
  },

  tasks = { ... },
  -- ...
}
```

`schema_version` is opaque to Watershed — it's for the author's own
versioning. Watershed tracks its own migration state separately via
`mix ash_postgres.generate_migrations`.

## 12. Schema composition

A workbook can pull in shared schemas via `_extends`:

```lua
return {
  _extends = { "watershed.common.timestamps", "watershed.common.audit" },

  tasks = {
    -- The extensions are applied to every table in this schema
    fields = { ... },
  },
}
```

Watershed ships a small library of standard extensions:

| Extension | Adds to every table |
|---|---|
| `watershed.common.timestamps` | `created_at`, `updated_at` (default; rarely opted out of) |
| `watershed.common.audit` | `created_by user_id`, `updated_by user_id` |
| `watershed.common.soft_delete` | `deleted_at timestamp?`; queries auto-filter unless `include_deleted = true` |

Custom extensions can be defined by other workbooks and pulled in via
`workbook_id.extension_name` syntax. Out of scope for v0; documented as a
future expansion.

## 13. Migration behavior

When a schema changes, Watershed's CLI generates a migration via `mix
ash_postgres.generate_migrations`. The flow:

1. Author edits `workbook.schema.lua`.
2. Author runs `mix watershed.tables.migrate --dry-run` to see the diff.
3. If the diff looks safe (additive, non-destructive), `mix
   watershed.tables.migrate` applies it. If it's destructive (drops
   a column, renames a column without hint, changes a column type
   incompatibly), the CLI refuses with `MIGRATION_UNSAFE` and surfaces
   what would be lost.
4. To force a destructive migration, the author confirms explicitly via
   `--allow-data-loss`.

Renames need a hint to avoid drop+add:

```lua
fields = {
  -- Renamed `text` to `title`. Hint disambiguates.
  title = { type = "string", was = "text" },
}
```

Without `was`, the codegen sees a deleted `text` column and a new `title`
column — interpreted as drop+add, which loses data.

## 14. Full example

Realistic schema for a research workbook:

```lua
-- workbook.schema.lua

return {
  _meta = {
    schema_version = 1,
    description = "Research workbook — tasks, findings, evaluations",
  },

  tasks = {
    description = "Top-level research tasks the user wants to investigate.",
    tenant = "workspace",
    fields = {
      id = "uuid",
      title = "string",
      description = "text?",
      status = { type = "string", default = "open" },
      priority = { type = "integer", default = 1 },
      assigned_to = "user_id?",
      due_at = "timestamp?",
    },
    indexes = { "status", "priority", "assigned_to" },
    relations = {
      findings = { has_many = "findings", via = "task_id" },
      assignee = { belongs_to = "platform.users", via = "assigned_to" },
    },
    policies = {
      read = "workspace_member",
      update = { or = { "workspace_admin", { creator_only = true } } },
      delete = "workspace_admin",
    },
  },

  findings = {
    description = "Sources / papers / notes attached to a task.",
    tenant = "workspace",
    fields = {
      id = "uuid",
      task_id = "uuid",
      topic = "string",
      content = "text",
      source = "string",
      tags = "string[]",
      score = "number?",
    },
    indexes = { "task_id", "topic", { fields = "tags", method = "gin" } },
    relations = {
      task = { belongs_to = "tasks", via = "task_id" },
      evaluations = { has_many = "evaluations", via = "finding_id" },
    },
  },

  evaluations = {
    description = "Quality grades on findings, one per reviewer.",
    tenant = "workspace",
    fields = {
      id = "uuid",
      finding_id = "uuid",
      reviewer_id = "user_id",
      score = "integer",
      rationale = "text",
    },
    unique = { { "finding_id", "reviewer_id" } },
    relations = {
      finding = { belongs_to = "findings", via = "finding_id" },
      reviewer = { belongs_to = "platform.users", via = "reviewer_id" },
    },
  },
}
```

This produces:
- Three Postgres tables with auto-managed `id`, `tenant_id`, `created_at`,
  `updated_at` plus the declared fields.
- Ash resource modules: `WorkbookN.Tasks`, `WorkbookN.Findings`,
  `WorkbookN.Evaluations`.
- Ash domain module: `WorkbookN.Domain`.
- Migrations under `priv/repo/migrations/`.
- Generated `_generated/api.ts` with type-safe references.

## 15. Open questions

For the vertical slice to resolve:

1. **`tenant = "workbook"` semantics**. Each workbook instance is one
   tenant, but how does this interact with multiple users sharing a
   workbook? Resolve by mapping `tenant = "workbook"` to a per-instance
   group, treating it as a shorthand for "workspace scoped to this
   workbook." Verify in slice.
2. **Computed field volatility classification**. SQL-generated columns
   are deterministic; aggregates are reactive-eligible. Should this be
   explicit per computed field?
3. **Many-to-many through table — auto-generate or require explicit?**
   v0 requires explicit; consider auto-generation if the pattern is
   verbose at scale.
4. **`was` hints for column renames** — keep as hint syntax, or move
   to a separate migrations file? Keep inline for now; revisit if
   schema files become unwieldy.
5. **Schema validation at edit time** — should `workbook dev` lint the
   schema continuously, or only at `workbook publish`? Probably lint
   continuously via the existing classifier infrastructure.

## 16. Conformance

Schema-level conformance tests (separate from stdlib conformance, but
following the same format) live in `SPEC/conformance/schema.md` (TBD).
They cover:

- Valid schemas compile without error.
- Invalid schemas produce specific error codes (`SCHEMA_INVALID`,
  `TENANT_MISSING`, `FIELD_TYPE_UNKNOWN`, `RELATION_TARGET_NOT_FOUND`,
  `POLICY_UNDEFINED`, etc.).
- Migration diff is correctly classified as safe / unsafe.
- Round-trip: schema → Ash module → Postgres → query via `db.*` returns
  expected shape.

## 17. Versioning

Schema spec versions with stdlib. Breaking changes (e.g., changing the
default tenant model, changing the policy expression grammar) require
a coordinated bump across the Watershed runtime and all workbooks that
have published against the prior version.

`_meta.schema_version` is the author-side version; not coupled to this
spec's version.
