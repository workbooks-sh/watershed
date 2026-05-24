# Watershed Stdlib Specification

> The contract every Watershed host implements. Lua source blocks (inside
> `.org` agent files, `server/*.lua` modules, and per-workbook tool handlers)
> call these functions; the host provides the implementation.
>
> Status: v0 draft. Refine as the vertical slice exercises each function.
> Version this file with semver once the conformance test suite (`SPEC/conformance/`)
> exists.
>
> Cross-references: [PLAN.md §3](../../PLAN.md) (namespace overview), [PLAN.md §4](../../PLAN.md)
> (classifier rules), [DECISIONS.md §2.6](../../DECISIONS.md) (no Convex trinity at the
> authoring level), [DECISIONS.md §2.13](../../DECISIONS.md) (agent-first DX). For library
> picks backing this surface see [LIBRARIES.md](../../LIBRARIES.md).

---

## Namespace index

Per-namespace specifications:

- [`db.*`](./db.md) — Data layer (Ash-backed Postgres reads + writes).
- [`broker.*`](./broker.md) — Authenticated host endpoints + integration actions.
- [`agent.*`](./agent.md) — Multi-agent invocation from inside source blocks.
- [`oban.*`](./oban.md) — Background jobs and cron-scheduled work.
- [`pubsub.*`](./pubsub.md) — Broadcast / subscribe across processes.
- [`http.*`](./http.md) — Rate-limited, audited outbound HTTP.
- [`crypto.*`](./crypto.md) — Hashing and HMAC primitives.
- [`time.*`](./time.md) — Clock access (wall + monotonic).
- [`uuid.*`](./uuid.md) — UUID generation (v4 + v7).
- [`json.*`](./json.md) — JSON parse + encode.
- [`worg.*`](./worg.md) — Org-mode document operations (host-optional).
- [`fs.*`](./fs.md) — Workbook-scoped blob storage.

Reference material:

- [`error-codes.md`](./error-codes.md) — Stable error codes referenced across every namespace.

---

## 1. Conventions

### 1.1 Function-call shape

All stdlib functions are Lua functions accessible via dot syntax under a namespace
(`db.read`, `broker.fetch`, etc.). They are called from inside Lua source blocks
that the Watershed host has registered as either:

- **Server functions** (`server/*.lua`) — invoked by clients via the `@work.books/runtime`
  SDK's `call()` and `subscribe()` primitives.
- **Tool handlers** (per-workbook Lua, dispatched via `/v1/workbooks/:id/invoke`).
- **Source blocks inside org-mode agent files** (per agent stage/tool, executed by
  the WORG executor through the same luerl host).

The calling Lua function receives two implicit values from the host:

- `ctx` — opaque host context. Carries tenant identity, current user, request ID,
  trace ID. Read via `ctx.tenant`, `ctx.user.id`, etc. **Never settable by Lua.**
- `args` — the table of arguments passed by the caller (client → SDK → API → host).

`ctx` is not passed explicitly to stdlib functions; it's resolved by the host at
the binding edge. From Lua's perspective, you just call `db.read("tasks", {...})`.

### 1.2 Argument shapes

Tables are the universal argument shape. Optional arguments live in option tables.
Positional arguments are reserved for the one or two most semantically dominant
parameters (table name, query, ID).

```lua
-- positional for the dominant arg, optional table for the rest
db.read("tasks", { where = { status = "open" }, limit = 50 })

-- never:
db.read({ table = "tasks", where = ..., limit = 50 })   -- avoid
db.read("tasks", "open", 50)                            -- avoid
```

### 1.3 Return shapes

Every stdlib function returns exactly one Lua value. Errors are raised as Lua
errors (`error(...)`) with a structured table:

```lua
error({
  code = "TABLE_NOT_FOUND",
  message = "no table named 'taks' in current workbook",
  hint    = "did you mean 'tasks'? run `mix watershed.tables.list` to see all",
  trace_id = "01HQ...",
})
```

The host catches these and converts them to the operations API error envelope
(per PLAN.md §16):

```json
{ "ok": false, "error": { "code": "...", "message": "...", "hint": "...", "trace_id": "..." } }
```

**Stable error codes only.** Lua callers branch on `err.code`, never on
`err.message`. Codes use `UPPER_SNAKE_CASE`. The full code list is in
[`error-codes.md`](./error-codes.md).

### 1.4 Classification

Every function below is annotated with a classification used by the publish-time
classifier (PLAN.md §4):

- **`:pure`** — deterministic, no side effects, no host state read or written.
- **`:reactive`** — reads host data, deterministic given that data. Reactive-eligible:
  a server function whose body calls only `:pure` and `:reactive` stdlib functions
  is wired as a reactive subscription via Phoenix.Sync.
- **`:mutation`** — writes to the host's data layer. The enclosing server function
  is wrapped in a single Postgres transaction.
- **`:effectful`** — non-deterministic, calls external services, has observable
  side effects beyond the data layer. The enclosing server function opts out of
  reactivity and transactions; the call is audited.

The classifier rejects functions that combine effectful and reactive calls without
explicit annotation (PLAN.md §4). `--@effect` comment marks an explicit effectful
function whose body the classifier would otherwise reject.

### 1.5 Tenancy

Every `db.*` function automatically scopes to `ctx.tenant`. Lua code can read
`ctx.tenant` but never set it. Cross-tenant reads or writes are impossible from
inside Lua — the host enforces this at the Ash policy layer (DECISIONS.md §2.8).

Functions that operate outside the tenant model (`crypto.*`, `time.*`, `uuid.*`,
`json.*`) explicitly don't take a tenant; they're noted below.

### 1.6 Cross-host portability

Every function has a **portability flag** indicating whether all Watershed-conformant
hosts must implement it (`required`) or may surface a `NOT_IMPLEMENTED` error
(`host-optional`). The conformance test suite verifies required functions; optional
ones are skipped on hosts that opt out.

Currently host-optional: `worg.*` (a host can opt out of WORG document operations
without breaking the rest of the stdlib).

### 1.7 Values and types

| Lua type | Notes |
|---|---|
| `string` | UTF-8. `nil` ≠ empty string. |
| `number` | Lua 5.3 has integer vs. float subtype; stdlib treats them as one `number` type unless explicit. |
| `boolean` | `true`/`false`. `nil` ≠ `false` in stdlib args. |
| `table` | Maps and arrays. Stdlib never returns mixed map+array tables. |
| `nil` | Means "absent." Optional args default to `nil` if omitted. |
| `function` | Used for `db.transaction(fn)` and a few callbacks. |

Postgres-specific types are surfaced as Lua values:

| Postgres type | Lua representation |
|---|---|
| `uuid` | `string` (hex-with-dashes form) |
| `timestamp` / `timestamptz` | `string` (ISO 8601 in UTC) |
| `jsonb` | `table` (deeply converted) |
| `numeric` | `string` (preserves precision; Lua can't safely round-trip arbitrary decimals) |
| `boolean` | `boolean` |
| `text` / `varchar` | `string` |
| `bytea` | `string` (binary-safe in Lua; not UTF-8 decoded) |
| `array` (e.g., `text[]`) | `table` (1-indexed sequence) |

---

## 15. Versioning

This spec is `v0` until the conformance test suite exists and a second host
implementation passes it. After that, semver:

- **Patch** — clarifications, examples, doc improvements.
- **Minor** — new functions, new optional args, new error codes.
- **Major** — removed functions, changed signatures, changed semantics.

Breaking changes between major versions require a coordinated bump of every
Watershed host (Elixir, future Rust, etc.) plus a deprecation cycle for
authored Lua code.

The `phoenix_sync` constraint (`WHERE`-only) is acknowledged at v0; when
Phoenix.Sync gains joins/order_by/limit, `db.read` may extend (minor bump,
not breaking — added shapes are accepted by hosts that support them, others
return `QUERY_INVALID`).

---

## 16. Open questions

These are intentionally left for the vertical slice to resolve:

1. **Should `db.read`'s `where` support OR / NOT semantics at v1?** Phoenix.Sync
   may support these via shape composition; need to test.
2. **`db.transaction` nested call semantics.** Calling `db.transaction` inside
   another `db.transaction` — flatten to the outer, or use savepoints? Default
   plan: flatten (savepoints add complexity).
3. **`pubsub.subscribe` lifecycle for agent stages.** Subscriptions in long-lived
   stages need a clear teardown story when the stage completes. Likely auto-unsubscribed
   when the stage process exits.
4. **`http.*` per-workbook rate limit values.** Default budget TBD; current broker
   has bespoke per-org limits that should map cleanly.
5. **`fs.put` content-type detection.** Default to caller's `opts.content_type`
   or sniff from bytes? Probably explicit-only at v1 (no sniffing); revisit if
   authors complain.
6. **Stream APIs.** Should there be a `db.read_stream` for large result sets?
   Same for `fs.get_stream` for large blobs? Deferred — explicit when needed.

---

## 17. Conformance

Per DECISIONS §2.2, the portability claim requires conformance testing across
hosts. [`SPEC/conformance/`](../conformance/README.md) defines:

- A canonical set of Lua scripts that exercise every required function.
- Expected outputs (or expected error codes).
- A test runner that any host can execute against a fresh tenant.

Every change to this spec requires a corresponding update to the conformance
suite. The suite gates host implementations: a host that fails any required
test cannot claim Watershed conformance.
