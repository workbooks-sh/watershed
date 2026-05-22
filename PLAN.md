# Whack — Build Plan

> What we're building. Read `DECISIONS.md` for the why behind each choice — this
> document focuses on the what and the build sequence.
>
> Status: planning, no implementation yet. Vertical slice (Section 11) is the next
> concrete move.

---

## 1. What Whack is

Whack is the workbooks backend standard. It defines:

- A **Lua scripting model** for workbook server logic — queries, mutations, actions,
  agent definitions, schema declarations.
- A **standard library API** (~30–50 functions across `db.*`, `broker.*`, `agent.*`,
  `oban.*`, `pubsub.*`, `http.*`, `worg.*`, etc.) that any Whack-conformant host must
  implement.
- A **reference implementation** built on Phoenix + luerl + Ash + Phoenix.Sync (Electric) +
  Oban + Postgres. This is what Workbooks Studio runs.
- A **portability contract** that allows the same Lua scripts to run against alternative
  hosts (Rust + mlua, customer self-hosted Phoenix, future browser-side Lua).
- A **distribution model** — Whack is its own package, importable into workbooks but
  separable for users who want to experiment with the backend independently.

What Whack is *not*:
- Not a database. (Whack uses Postgres.)
- Not a UI framework. (UI stays Svelte 5 inside the .html artifact.)
- Not a hosting platform. (Studio is the hosting product; Whack is the abstraction
  layer under it.)
- Not a Convex clone. (We borrow ideas — reactive queries, schema-as-API — without
  inheriting the closed-runtime constraint.)

---

## 2. Package structure

Whack ships as a top-level monorepo package, parallel to WORG and Wavelet:

```
packages/whack/
├── DECISIONS.md           # why (this file's companion)
├── PLAN.md                # what (this file)
├── README.md              # introduction (TBD)
├── SPEC/                  # the standard
│   ├── stdlib.md          # function-by-function reference — PRIORITY ARTIFACT
│   ├── classification.md  # how the runtime classifies functions
│   ├── schema.md          # workbook.schema.lua format
│   ├── conformance.md     # what conformance testing looks like
│   └── versioning.md      # semver discipline
├── elixir/                # reference implementation (Studio backend)
│   └── whack/
│       ├── lib/whack/     # luerl host, stdlib bindings, classifier, codegen
│       └── test/
├── lua/                   # Lua-side helpers (shipped to workbooks as `server/lib`)
├── runtime-bindings/      # client-side `@work.books/runtime` extensions
└── tests/
    └── conformance/       # canonical Lua scripts that any host must pass
```

Whack is integrated into workbooks via:
- The `workbook-cli` learns to compile `server/*.lua` into a bundle and embed it in the
  `.html` artifact as `<script id="wb-server-bundle">`.
- The `@work.books/runtime` SDK gains `subscribe()` and `call()` primitives that route
  through the broker to the host's Whack runtime.
- The Studio Phoenix app embeds the `whack` Elixir application as a dependency.

---

## 3. The standard library — priority artifact

The stdlib spec is the first thing to write and the load-bearing artifact for everything
else. Initial scope: ~30–50 functions across these namespaces.

### 3.1 Namespaces

| Namespace | Purpose | Reactive eligible? |
|---|---|---|
| `db.*` | Data access (reads, writes, transactions, subscriptions) | `db.read*` is the only reactive surface |
| `broker.*` | Authenticated HTTP to broker endpoints, integration actions | No (effectful) |
| `agent.*` | Invoke other agents, observe agent state, define agent tools | No (effectful) |
| `oban.*` | Enqueue background jobs, schedule recurring work | No (effectful) |
| `pubsub.*` | Broadcast / subscribe to workbook-scoped topics | No (broadcast itself is effectful) |
| `http.*` | Outbound HTTP (rate-limited, audited) | No (effectful) |
| `crypto.*` | Hashing, signing — no random key generation | Pure |
| `time.*` | Wall clock, monotonic clock | Effectful (non-deterministic) |
| `uuid.*` | UUID generation | Effectful (non-deterministic) |
| `json.*` | Parse, encode | Pure |
| `worg.*` | WORG document parse/mutate (host-optional) | Read-only methods are pure |
| `fs.*` | Workbook-scoped blob storage (R2 / Tigris) | Read-only methods are pure |
| `sandbox.*` | Spin up ephemeral sandbox VM (deferred from v1) | No |
| `subscribe.*` | Internal — not author-facing; used by codegen | n/a |

### 3.2 Per-function spec requirements

For each function the spec must declare:

- **Signature** — argument shapes, return shape.
- **Semantics** — what it does, observable side effects, ordering guarantees.
- **Reactivity classification** — does calling this function make the enclosing function
  reactive-eligible, mutation, or effectful?
- **Transactional behavior** — participates in enclosing transaction or escapes it?
- **Tenant scope** — uses `ctx.tenant` implicitly, takes explicit scope, or bypasses
  tenancy.
- **Failure modes** — what raises, what returns errors, what retries.
- **Cross-host portability** — must all hosts implement, may skip with a clear error,
  or is host-specific.
- **Examples** — at least one trivial and one realistic use case.

### 3.3 Initial function list (draft — refine during SPEC/stdlib.md authoring)

```
db.read(table, query)            -- reactive, pure
db.read_one(table, id)           -- reactive, pure
db.read_many(table, ids)         -- reactive, pure
db.write(table, record)          -- mutation, transactional
db.update(table, id, patch)      -- mutation, transactional
db.delete(table, id)             -- mutation, transactional
db.transaction(fn)               -- explicit transaction boundary
db.raw(query, params)            -- escape hatch, mutation classification

broker.fetch(endpoint, opts)     -- effectful
broker.execute(connection, action, args) -- effectful

agent.invoke(slug, prompt, opts) -- effectful
agent.state(run_id)              -- effectful (reads live state)
agent.define(spec)               -- declarative (not called at runtime)

oban.enqueue(worker, args, opts) -- effectful
oban.schedule(worker, cron, args) -- effectful

pubsub.broadcast(topic, payload) -- effectful
pubsub.subscribe(topic, fn)      -- effectful, only valid in handlers

http.get(url, opts)              -- effectful
http.post(url, body, opts)       -- effectful

crypto.hash(algo, data)          -- pure
crypto.hmac(algo, key, data)     -- pure

time.now()                       -- effectful
time.monotonic()                 -- effectful

uuid.v4()                        -- effectful
uuid.v7()                        -- effectful

json.parse(s)                    -- pure
json.encode(v)                   -- pure

worg.parse(text)                 -- pure (host-optional)
worg.update_todo(id, state)      -- mutation (host-optional)
worg.append_logbook(id, entry)   -- mutation (host-optional)
worg.query(filter)               -- reactive, pure (host-optional)

fs.put(path, bytes, opts)        -- mutation
fs.get(path)                     -- reactive, pure
fs.list(prefix)                  -- reactive, pure
fs.delete(path)                  -- mutation
```

Refine during SPEC authoring. Target final v1 list: 35–50 functions.

---

## 4. Function classification — how the runtime decides

When a server Lua file is registered with the host, the classifier walks each top-level
function's AST and assigns a classification:

| Classification | Trigger | Runtime behavior |
|---|---|---|
| `:reactive` | Calls only reactive-eligible stdlib functions | Wired into Phoenix.Sync as an Electric shape |
| `:mutation` | Calls any `db.write*` / `db.update*` / `db.delete` / `db.transaction` and no effectful functions | Wrapped in a single Postgres transaction |
| `:effectful` | Calls anything in `broker.*` / `http.*` / `oban.*` / `pubsub.*` / `time.*` / `uuid.*` | No transaction wrapper, no reactivity, audit log entry |
| `:undefined` | Dynamic dispatch (`db[name](...)`), conditional effects without annotation | Linter rejects at publish |

Authors can override classification with comment annotations:

```lua
--@effect
function maybe_notify(ctx, args)
  if args.notify then
    broker.send_email(...)
  end
end
```

Rejection messages tell authors exactly why and how to fix. The linter is part of the
publish pipeline (`workbook build` runs it).

---

## 5. Schema declaration — `workbook.schema.lua`

A workbook declares its data shapes in a single file. The CLI generates Ash resource
modules from this declaration and ships them to the Studio host (or an alternative host)
on publish.

```lua
-- workbook.schema.lua
return {
  tasks = {
    fields = {
      id = "uuid",
      text = "string",
      status = "string",
      done = "boolean",
      created_at = "timestamp",
      assigned_to = "user_id?",
    },
    tenant = "current_user",
    indexes = { "status", "created_at" },
  },

  findings = {
    fields = {
      id = "uuid",
      topic = "string",
      content = "text",
      source = "string",
    },
    tenant = "workspace",
    indexes = { "topic" },
  },
}
```

CLI behavior on `workbook build`:
1. Parse schema.
2. Compare against last-published schema (cached in `.workbook/`).
3. Generate Ash resource modules + migrations.
4. Refuse publish if migrations would lose data; prompt author.
5. On confirmed publish, register schema with the host.

Schema-side decisions deferred to vertical slice:
- Exact field type vocabulary (full list).
- Relationship syntax (`belongs_to`, `has_many`).
- Computed field syntax.
- Policy syntax beyond the simple `tenant` field.

---

## 6. Runtime architecture (Studio reference implementation)

```
Workbook (.html)
   │
   ├── Svelte client UI
   ├── @work.books/runtime SDK
   │      ↓ subscribe() / call()
   │
   ↓ HTTPS / WebSocket
   │
Broker (Cloudflare Worker)
   │ — auth, rate limiting, audit
   ↓ HTTPS
   │
Studio Phoenix
   ├── Whack runtime (Elixir app)
   │     ├── luerl host (sandbox)
   │     ├── stdlib bindings → Ash / Phoenix.Sync / Oban
   │     ├── classifier (publish-time)
   │     └── codegen (publish-time)
   │
   ├── Ash (data layer, multitenancy, policies)
   ├── Phoenix.Sync (Electric shape server)
   ├── Oban (background jobs)
   └── Postgres (Fly managed, Supavisor pooled)
```

Per-request flow:

- **Reactive query** — Client `subscribe(api.tasks.list)` opens a Phoenix.Sync shape
  stream via broker. Initial snapshot + incremental updates flow over WebSocket. Lua
  function is invoked once at shape registration to define the shape; thereafter Electric
  watches the WAL.

- **Mutation** — Client `call(api.tasks.create, args)` POSTs through broker. Phoenix
  starts a transaction, invokes the Lua function via luerl with injected `ctx`, commits.
  Reactive subscribers see the change via Electric.

- **Action** — Client `call(api.tasks.notify, args)` POSTs through broker. Phoenix
  invokes the Lua function via luerl, no transaction. Effects (Oban enqueues, HTTP calls)
  are audited.

---

## 7. Authoring model

### 7.1 Project layout

```
my-workbook/
├── workbook.config.mjs        # build config (JS — small, stable)
├── workbook.schema.lua        # data shape declarations
├── src/                       # Svelte client
│   ├── App.svelte
│   ├── lib/                   # shared components
│   └── _generated/
│       └── api.ts             # codegen — typed client references
├── server/                    # Lua server (libs + helpers, no agents)
│   ├── tasks.lua              # plain server functions per resource
│   ├── notifications.lua
│   └── lib/                   # shared Lua utilities used by source blocks
├── agents/                    # agent definitions — org-mode (see /skills/whack/agents.md)
│   ├── researcher.org
│   └── triager.org
├── plans/                     # multi-agent pipelines + planning DAGs
│   └── research-pipeline.org
├── skills/                    # markdown or org-mode skill bundles
│   ├── academic-research/SKILL.md
│   └── arxiv-conventions/SKILL.org
└── .workbook/                 # local cache (gitignored)
```

### 7.2 Server function example

```lua
-- server/tasks.lua
return {
  list = function(ctx, args)
    return db.read("tasks", {
      where = { status = args.status or "open" },
      order_by = "created_at",
    })
  end,

  create = function(ctx, args)
    return db.write("tasks", {
      text = args.text,
      status = "open",
      created_by = ctx.user.id,
    })
  end,

  complete = function(ctx, args)
    db.update("tasks", args.id, { status = "done", done = true })
  end,

  notify_assignee = function(ctx, args)
    --@effect
    local task = db.read_one("tasks", args.task_id)
    if task.assigned_to then
      oban.enqueue("send_email", {
        to = task.assigned_to,
        template = "task_assigned",
        task_id = task.id,
      })
    end
  end,
}
```

### 7.3 Client example

```svelte
<!-- src/App.svelte -->
<script>
  import { subscribe, call } from "@work.books/runtime";
  import { api } from "./_generated/api";

  const tasks = subscribe(api.tasks.list, { status: "open" });
  const createTask = call(api.tasks.create);
  const completeTask = call(api.tasks.complete);

  let newText = $state("");
</script>

<input bind:value={newText} />
<button onclick={() => createTask({ text: newText }).then(() => newText = "")}>
  Add
</button>

{#each tasks as task}
  <div class:done={task.done}>
    {task.text}
    <button onclick={() => completeTask({ id: task.id })}>✓</button>
  </div>
{/each}
```

### 7.4 Inline server option (small workbooks only)

For single-component workbooks, server functions can live in a `<server>` block inside
the Svelte file:

```svelte
<server lang="lua">
return {
  list = function(ctx, args)
    return db.read("tasks", { status = args.status or "open" })
  end,
}
</server>

<script>
  import { subscribe } from "@work.books/runtime";
  const tasks = subscribe("list", { status: "open" });
</script>
```

The CLI's Svelte preprocessor extracts `<server>` blocks at build time. Same runtime
behavior; just lighter ceremony for tiny workbooks.

---

## 8. Agent authoring

**Agents are not authored in Lua.** They are authored in org-mode (`.org` files).
See [`/skills/whack/agents.md`](../../skills/whack/agents.md) for the complete agent architecture: file shape, tool
definitions, multi-stage pipelines, multi-agent orchestration, skills integration,
validators, cost/retry/approval semantics, runtime model.

The rationale for this choice (org-mode over a Lua DSL) is documented in
`DECISIONS.md` §2.10 and grounded in the experiments at `experiments/01-simple-agent/`
and `experiments/02-multi-agent/`.

Short version: WORG already provides the DAG, state machine, drawers, logbook,
properties, and DAG-aware scheduler that an agent framework needs. Building a parallel
agent DSL in Lua would duplicate all of it without gaining anything. Org-mode is the
authoring surface; Lua source blocks inside org files are the execution surface.

The Whack stdlib (this document, §3) supplies the vocabulary that those source blocks
call into. Authors write **`.org` for agents/pipelines + `.lua` for tools/libs/schemas
+ `.svelte` for UI**. The Elixir/Phoenix/luerl runtime stays platform infrastructure.

---

## 9. WORG integration

Whack and WORG are deeply linked but cleanly separated:

- **WORG owns:** the document model (org-mode parsing, mutation, query), the DAG
  scheduler (`Predicate::Ready`), the state machine (`TODO → DOING → DONE/...`), and
  the existing Elixir + Rust + NIF + WASM infrastructure.
- **Whack owns:** the luerl runtime that executes source blocks inside WORG documents,
  the stdlib those source blocks call, and the data layer (Ash + Phoenix.Sync + Oban
  + Postgres) the stdlib binds to.

The previously-planned WORG-Lua executor (`wb-4vhr.15`) **merges into the Whack v1
build.** It's the same luerl host serving both roles — there is no separate
"WORG-Lua executor" and "Whack agent runtime."

The `worg.*` namespace in the Whack stdlib exposes WORG's existing APIs (parse, query,
transition_todo, append_logbook, etc.) so Lua source blocks can interact with org
documents programmatically. Note that *agent execution itself* doesn't go through
`worg.*` — the WORG executor calls into luerl directly. `worg.*` is for cases where a
source block wants to read or mutate a *different* org document (e.g., a planning
agent updating a project plan).

For the full agent + WORG architecture (file layout, examples, runtime topology), see
[`/skills/whack/agents.md`](../../skills/whack/agents.md).

---

## 10. Distribution

Whack ships in three layers:

### 10.1 The spec

`packages/whack/SPEC/` is the open standard. Versioned (semver), language-agnostic,
implementation-independent. Anyone can implement a Whack host by conforming to the spec.
This is the part that's "not just Workbooks Studio."

### 10.2 The Elixir reference implementation

`packages/whack/elixir/whack/` is the BEAM implementation. Used by Studio. Available
as a standalone Hex package eventually — someone running their own Phoenix could
depend on `whack` and host workbook server logic.

### 10.3 The workbook integration

The pieces of Whack that ship inside the workbook artifact:

- The `@work.books/runtime` extensions (`subscribe`, `call`, `api.*` typing).
- The Lua bundle (server scripts gzipped into `<script id="wb-server-bundle">`).
- The schema bundle (workbook.schema.lua compiled to a manifest).

These are integrated into `workbook-cli` and `@work.books/runtime` rather than living in
a separate npm package — they're tightly coupled to the workbook build pipeline.

### 10.4 Subtree mirror

Like WORG / Wavelet / Colorwave, Whack will mirror to its own public repo
(`github.com/workbooks-sh/whack`) via `git subtree push --prefix=packages/whack
whack main` when ready for public release.

---

## 11. Vertical slice — the next concrete move

Before writing more spec or architecture docs, build the smallest end-to-end thing that
exercises every unresolved decision. Scope:

**One workbook, one resource, three operations:**
- Schema: a single `tasks` table.
- Server: `list`, `create`, `complete` Lua functions.
- Client: Svelte component subscribing to `list`, calling `create` and `complete`.
- Multi-user: two browsers see each other's changes in real time.
- Multi-tenant: two organizations see only their own tasks.

**Stack to wire:**
- Phoenix app embedding `whack` Elixir application.
- luerl runtime hosting Lua scripts.
- Ash resource generated from `workbook.schema.lua`.
- Phoenix.Sync shape for `list`.
- `workbook-cli` extended to compile + embed `server/*.lua`.
- `@work.books/runtime` extended with `subscribe()` / `call()`.

**Decisions the slice forces (and therefore resolves):**
- How `db.read` translates to an Ash read action.
- How reactive Lua becomes a Phoenix.Sync shape.
- How the linter classifies a function.
- How the codegen produces `_generated/api.ts`.
- How the broker routes `subscribe()` and `call()` to the right host.
- How `ctx.tenant` gets injected.
- Whether mutations are auto-atomic or require explicit `db.transaction(...)`.

**Out of scope for the slice:**
- Agents (added in next iteration).
- WORG integration.
- Migrations beyond initial schema (manual SQL is fine for the slice).
- Conformance test suite (deferred until a second host exists).
- Performance optimization.

**Estimated effort:** 2–3 focused weeks of build, end-to-end. If it takes longer, that's
a signal the architecture is more brittle than the design suggests, and the slice should
inform a revision to this document.

---

## 12. Build sequence after the slice

Once the vertical slice works:

1. **Write SPEC/stdlib.md** — full spec for the ~35 functions, with semantics learned
   from the slice. This becomes the canonical reference.
2. **Extend the slice into a second workbook** — one with agents, one with a different
   reactive pattern (e.g., joined reads, large lists). Surface gaps in the stdlib.
3. **Write SPEC/conformance.md** — define what conformance means, draft the first test
   suite.
4. **Build agent runtime** — `agent.define`, agent loop in Elixir, live state
   subscription. Ship the "live agent coordination" demo as the differentiator.
5. **WORG integration** — implement `worg.*` namespace, port the existing WORG-Lua
   execution plan (`wb-4vhr.15`) into Whack rather than as a separate runtime.
6. **CLI tooling** — schema diff/migration prompts, linter polish, IDE LSP support for
   the stdlib.
7. **Second host implementation** — Rust + mlua, conformance-tested against Studio's
   Elixir host. This is what proves the portability claim.

Each step is gated on the previous one working. No parallel speculation.

---

## 13. What's intentionally not in this plan

These are deferred so they don't dilute v1:

- Mode 2 (client-side Lua) — added when ≥3 workbooks would benefit.
- Mode 3 (hybrid / PGlite local-first) — added when offline-capable workbooks become a
  product priority.
- Cloud sandbox VMs — added when a workbook needs computation beyond what luerl can
  sandbox.
- mlua-via-WASM in BEAM — added when luerl interpretation is the measured bottleneck.
- Schema-per-tenant — added only for graduated enterprise customers.
- BYO-database escape hatch — `wb.db(slot)` stays as a v0 surface but isn't promoted.
- Luau-style gradual types — investigate after the stdlib is stable.
- Public-facing Whack standard release — after the second-host conformance test exists.

Each of these is a future epic, not a "we forgot to plan for it" gap.

---

## 14. How this lands in the monorepo

When the vertical slice is approved and built:

- `packages/whack/` — this package.
- `apps/workbooks-runtime/lib/workbooks_runtime/whack/` — Studio's Phoenix mounts the
  Whack runtime here (until/unless the Elixir app is extracted as a standalone Hex
  package).
- `packages/workbooks/packages/workbook-cli/` — CLI gains `server/*.lua` compilation step.
- `packages/workbooks/packages/runtime/` — runtime SDK gains `subscribe()` / `call()` /
  `api` codegen integration.
- A new beads epic captures the vertical slice and downstream steps.

---

## 15. Open invitation

This plan is intentionally written so the vertical slice (Section 11) can start *next*.
Treat sections 3–10 as the design space that the slice will harden. If the slice surfaces
that any decision in `DECISIONS.md` was wrong, update that doc first and this plan
second — `DECISIONS.md` is the source of truth for *why*, this plan is the source of
truth for *what*.
