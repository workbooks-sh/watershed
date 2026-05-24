# Watershed — Build Plan

> What we're building. Read `DECISIONS.md` for the why behind each choice — this
> document focuses on the what and the build sequence.
>
> Status: planning, no implementation yet. Vertical slice (Section 12) is the next
> concrete move.

---

## 1. What Watershed is

**Watershed is the Workbooks platform backend.** Everything between the workbook
artifact (the `.html` file) and Postgres that isn't UI. It defines:

- **Platform features** — auth, identity, workbook lifecycle (register, publish,
  revoke, lease, audit), agent registry, multi-tenancy (orgs, groups, members,
  roles), blob storage (R2 default, S3-compatible swappable), integration actions,
  hash-chained audit logs, key release for per-view decryption. These are *first-class
  Watershed scope*, not pieces bolted on by integration.
- **Operations surface** — three access paths to the same Ash + Oban + Telemetry data:
  - **API first** — a stable HTTP/JSON contract for everything an operator (or agent)
    might want: list tables, query state, inspect jobs, read recent telemetry, trigger
    actions. This is the source of truth; the other two paths are clients.
  - **CLI** — `mix watershed.<verb>` commands for the same operations, plus
    `fly ssh console` + `bin/<app> remote` for IEx. Agents drive Watershed primarily
    through the CLI; the CLI calls the API.
  - **Custom dashboard** (optional, lightweight) — Phoenix LiveView UI that reads
    the API for visualizations a human might want (status overview, table browser,
    job queue, telemetry charts). Built simply, not by directly reusing `ash_admin`'s
    or `oban_web`'s default UIs — those libraries are used for their data surfaces
    (resource introspection, job state) and we paint our own thin LiveView on top.
    The dashboard is for occasional human use; agents shouldn't need it.
- **Lua scripting model** for workbook server logic and tool dispatch — queries,
  mutations, actions, agent tools, schema declarations.
- **Standard library API** (~30–50 functions across `db.*`, `broker.*`, `agent.*`,
  `oban.*`, `pubsub.*`, `http.*`, `worg.*`, etc.) — the surface Lua source blocks
  call into. Same surface for workbook server scripts and per-workbook tool handlers.
- **Reference implementation** built on Phoenix + Ash + AshAuthentication + Luerl +
  Phoenix.Sync (Electric) + Oban + Postgres on Fly. This is what Workbooks Studio
  runs and what the broker becomes after migration.
- **Cloudflare independence** — Watershed runs on stock Phoenix + Postgres + Fly with
  no Cloudflare-specific dependencies. R2 is the default blob backend but explicitly
  swappable for any S3-compatible store. DNS/CDN is optional convenience, not required.
- **Portability contract** — the same Lua scripts and the same Ash data model run
  against alternative hosts (customer self-hosted Phoenix on their own Fly, future
  Rust + mlua host, future browser-side Lua).
- **Distribution model** — Watershed is its own package (`docs/watershed`),
  importable into Workbooks but separable for users who want to host the backend
  independently or fork it.

What Watershed is *not*:
- Not a database. (Watershed uses Postgres.)
- Not a UI framework. (UI stays Svelte 5 inside the .html artifact.)
- Not Cloudflare-dependent. (R2 default is the only CF product, and it's optional.)
- Not a hosting product. (Studio is the hosted-SaaS product; Watershed is the
  backend it deploys. Anyone can self-host Watershed on their own Fly.)
- Not a Convex clone. (We borrow ideas — reactive queries, schema-as-API — without
  inheriting the closed-runtime constraint.)

### Design priority: agent-first developer experience

Every Watershed surface — CLI, API, skills, error messages, response shapes — is
designed for an AI coding agent to use without human help. **In a working
deployment, a human never has to look at the admin UI.** The CLI and API are the
primary developer surface; the dashboard is a convenience for occasional human
review.

Concretely, this means:
- Every operation an operator can do via the dashboard must also be available via
  the CLI and the API, with the same identifiers and the same response shapes.
- API responses are structured (JSON), versioned, and include machine-readable
  error envelopes (`{ "error": { "code": "...", "message": "...", "hint": "..." } }`).
- The CLI's output is parseable. `--json` flag on every command for agent
  consumption; default text output is for humans.
- Skills (in `/skills/watershed/`) document patterns, not just APIs. An agent can
  read a skill and know not just *what* commands exist but *when* to use which.
- Schema definitions, agent definitions, and server functions are all authored in
  files (org-mode + Lua + Svelte) that fit the existing agent workflow. The agent
  never has to fill out a form in the dashboard to create a resource.

The reframe: Watershed isn't "a platform with an admin UI." It's an **agent-operable
backend** that happens to ship a small LiveView dashboard for humans who want one.
This priority shapes Sections 11 (broker transition library picks) and the new
Section 16 (Agent developer experience) below.

---

## 2. Package structure

Watershed ships as a top-level monorepo package, parallel to WORG and Wavelet:

```
docs/watershed/
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
│   └── watershed/
│       ├── lib/watershed/     # luerl host, stdlib bindings, classifier, codegen
│       └── test/
├── lua/                   # Lua-side helpers (shipped to workbooks as `server/lib`)
├── runtime-bindings/      # client-side `@work.books/runtime` extensions
└── tests/
    └── conformance/       # canonical Lua scripts that any host must pass
```

Watershed is integrated into workbooks via:
- The `workbook-cli` learns to compile `server/*.lua` into a bundle and embed it in the
  `.html` artifact as `<script id="wb-server-bundle">`.
- The `@work.books/runtime` SDK gains `subscribe()` and `call()` primitives that route
  through the broker to the host's Watershed runtime.
- The Studio Phoenix app embeds the `watershed` Elixir application as a dependency.

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

### 3.3 Initial function list (draft — refine during SPEC/stdlib/ authoring)

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

agent.invoke(path, args)         -- effectful — invoke an org-mode agent by file path
agent.state(run_id)              -- effectful (reads live state)
-- (no agent.define — agents are org-mode files, not Lua DSL; see DECISIONS §2.9)

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
Watershed (Phoenix on Fly — single application)
   ├── HTTP API
   │     — auth (ash_authentication: magic-link + WorkOS OIDC)
   │     — workbook lifecycle (register / publish / revoke / lease)
   │     — agent registry
   │     — audit log + signing-key verification
   │     — integration actions (broker.execute, OAuth providers)
   │     — rate limiting + per-org policies
   │
   ├── Watershed runtime
   │     ├── Luerl host (sandbox, per-call isolation)
   │     ├── Stdlib bindings → Ash / Phoenix.Sync / Oban
   │     ├── Classifier + codegen (publish-time)
   │     └── Tool dispatch (per-workbook Lua handlers)
   │
   ├── Ash domains
   │     — Identity (User, AuthorKey, Session)
   │     — Workbooks (Workbook, Lease, AuditEntry, ToolHandler)
   │     — Agents (Agent, Session)
   │     — Orgs (Group, GroupMember, Connection)
   │     — plus per-workbook resource tables (from workbook.schema.lua)
   │
   ├── Phoenix.Sync (Electric shape server)
   ├── Oban (background jobs)
   ├── Operations API (HTTP/JSON, /ops/*)
   │     — list resources, query state, inspect jobs, read telemetry,
   │       trigger actions
   │     — source of truth; CLI and dashboard are clients
   │     — uses ash, ash_admin's resource introspection, oban's job query API,
   │       phoenix_live_dashboard's telemetry data — all surfaced as JSON
   │     — auth-gated to operators only
   ├── Custom dashboard (Phoenix LiveView, /admin/*) — optional
   │     — thin LiveView UI reading from /ops/* API
   │     — for occasional human use; agents drive via API + CLI
   │     — NOT a wrapper around ash_admin/oban_web default UIs; uses their
   │       data surfaces but paints our own design
   └── Postgres (Fly managed, Supavisor pooled)

Watershed CLI (`mix watershed.<verb>` + binary releases):
   ↑ calls /ops/* API
   — agents drive Watershed primarily through this
   — `--json` flag on every command for parseable output

Blob storage (configurable):
   ↑ R2 by default, any S3-compatible backend supported
   accessed via Watershed's blob client (ex_aws_s3 or req_s3)

Optional edge layer (not required):
   DNS, edge cache, WAF — Cloudflare today, swappable for any CDN
   No application code at the edge.
```

There is **one Phoenix application**. What was historically split between "Broker
on Cloudflare" and "Studio Phoenix" collapses to a single Watershed deployment on
Fly. The migration that produces this state is §11 below.

Per-request flow:

- **Reactive query** — Client `subscribe(api.tasks.list)` opens a Phoenix.Sync shape
  stream directly to Watershed. Initial snapshot + incremental updates flow over
  WebSocket. Lua function is invoked once at shape registration to define the shape;
  thereafter Electric watches the WAL.

- **Mutation** — Client `call(api.tasks.create, args)` POSTs to Watershed. Phoenix
  starts a transaction, invokes the Lua function via luerl with injected `ctx`, commits.
  Reactive subscribers see the change via Electric.

- **Action** — Client `call(api.tasks.notify, args)` POSTs to Watershed. Phoenix
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
├── agents/                    # agent definitions — org-mode (see /skills/watershed/agents.md)
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
See [`/skills/watershed/agents.md`](../../skills/watershed/agents.md) for the complete agent architecture: file shape, tool
definitions, multi-stage pipelines, multi-agent orchestration, skills integration,
validators, cost/retry/approval semantics, runtime model.

The rationale for this choice (org-mode over a Lua DSL) is documented in
`DECISIONS.md` §2.10 and grounded in the experiments at `experiments/01-simple-agent/`
and `experiments/02-multi-agent/`.

Short version: WORG already provides the DAG, state machine, drawers, logbook,
properties, and DAG-aware scheduler that an agent framework needs. Building a parallel
agent DSL in Lua would duplicate all of it without gaining anything. Org-mode is the
authoring surface; Lua source blocks inside org files are the execution surface.

The Watershed stdlib (this document, §3) supplies the vocabulary that those source blocks
call into. Authors write **`.org` for agents/pipelines + `.lua` for tools/libs/schemas
+ `.svelte` for UI**. The Elixir/Phoenix/luerl runtime stays platform infrastructure.

---

## 9. WORG integration

Watershed and WORG are deeply linked but cleanly separated:

- **WORG owns:** the document model (org-mode parsing, mutation, query), the DAG
  scheduler (`Predicate::Ready`), the state machine (`TODO → DOING → DONE/...`), and
  the existing Elixir + Rust + NIF + WASM infrastructure.
- **Watershed owns:** the luerl runtime that executes source blocks inside WORG documents,
  the stdlib those source blocks call, and the data layer (Ash + Phoenix.Sync + Oban
  + Postgres) the stdlib binds to.

The previously-planned WORG-Lua executor (`wb-4vhr.15`) **merges into the Watershed v1
build.** It's the same luerl host serving both roles — there is no separate
"WORG-Lua executor" and "Watershed agent runtime."

The `worg.*` namespace in the Watershed stdlib exposes WORG's existing APIs (parse, query,
transition_todo, append_logbook, etc.) so Lua source blocks can interact with org
documents programmatically. Note that *agent execution itself* doesn't go through
`worg.*` — the WORG executor calls into luerl directly. `worg.*` is for cases where a
source block wants to read or mutate a *different* org document (e.g., a planning
agent updating a project plan).

For the full agent + WORG architecture (file layout, examples, runtime topology), see
[`/skills/watershed/agents.md`](../../skills/watershed/agents.md).

---

## 10. Distribution

Watershed ships in three layers:

### 10.1 The spec

`docs/watershed/SPEC/` is the open standard. Versioned (semver), language-agnostic,
implementation-independent. Anyone can implement a Watershed host by conforming to the spec.
This is the part that's "not just Workbooks Studio."

### 10.2 The Elixir reference implementation

`docs/watershed/elixir/watershed/` is the BEAM implementation. Used by Studio. Available
as a standalone Hex package eventually — someone running their own Phoenix could
depend on `watershed` and host workbook server logic.

### 10.3 The workbook integration

The pieces of Watershed that ship inside the workbook artifact:

- The `@work.books/runtime` extensions (`subscribe`, `call`, `api.*` typing).
- The Lua bundle (server scripts gzipped into `<script id="wb-server-bundle">`).
- The schema bundle (workbook.schema.lua compiled to a manifest).

These are integrated into `workbook-cli` and `@work.books/runtime` rather than living in
a separate npm package — they're tightly coupled to the workbook build pipeline.

### 10.4 Subtree mirror

Like WORG and Wavelet, Watershed will mirror to its own public repo
(`github.com/workbooks-sh/watershed`) via `git subtree push --prefix=docs/watershed
watershed main` when ready for public release.

---

## 11. Cloudflare independence and the broker transition

### The portability charter

**Watershed must run on stock Phoenix + Postgres + Fly with zero Cloudflare
dependencies.** Anyone — Studio, a customer self-hosting, an OSS user forking
the stack — can deploy Watershed on any Fly account, any Postgres cluster, any
S3-compatible blob store, without needing a Cloudflare account.

The only Cloudflare product Watershed defaults to is **R2** (blob storage for
workbook artifacts). R2 is the default because its free-egress pricing is too
good to walk away from at our scale, but the storage interface is generic —
swap in `ex_aws_s3` or `req_s3` pointing at any S3-compatible backend (AWS S3,
Backblaze B2, Tigris, Wasabi, MinIO) via env var, no code change.

The current Cloudflare Worker (`packages/broker/worker`) is a **legacy
implementation** of platform features that Watershed now owns. It exists for
historical reasons; the broker migration transfers its features into Watershed
and retires it.

### What Watershed absorbs from the broker

The broker today implements features that Watershed claims as first-class scope
(§1 above). The migration is the operational path for transferring each:

| Watershed feature | Broker's legacy implementation | Replaced by |
|---|---|---|
| **Auth (magic-link + OIDC)** | Bespoke TS routes, WorkOS OAuth, magic-link tokens in D1 | `ash_authentication` with magic-link + WorkOS OIDC strategies |
| **Identity** | D1 tables for users, sessions, author keys | Ash `Identity` domain (User, AuthorKey, Session) |
| **Workbook lifecycle** | TS route handlers in `workbooks.ts` (~2400 lines) | Ash `Workbooks` domain + Phoenix controllers (URL contract preserved) |
| **Audit log** | Append-only D1 table, hash-chained per workbook | Ash `Workbooks.AuditEntry` with append-only policy |
| **Agent registry** | Bespoke TS handlers, D1 tables | Ash `Agents` domain |
| **Multi-tenancy** | Group/member tables, ad-hoc auth checks | Ash `Orgs` domain + Ash policies (`access_when`, `forbid_unless`) |
| **Blob storage** | R2 binding from CF Workers | `ex_aws_s3` / `req_s3` Elixir client against R2 (env-swappable) |
| **Tool dispatch** | Workers-for-Platforms + bespoke `host` table | Watershed's Luerl runtime + the Watershed stdlib |
| **Integration actions** | Bespoke route + connection tables | Same Ash `Orgs.Connection` schema, Elixir HTTP client behind it |

After migration, the broker as a separate concept disappears. There's just
Watershed serving HTTP routes from Phoenix on Fly. The `packages/broker/worker`
directory either gets retired (if we deploy a new `apps/workbooks-watershed`
app) or its TS contents get replaced with the Elixir application (decision
deferred to migration kickoff).

### What stays on Cloudflare (configuration, not code)

- **R2** as the default blob store (swappable, see above).
- **DNS routing** for `*.workbooks.sh` (any DNS provider works).
- **Edge cache + WAF** for the public surface (any CDN works — Cloudflare is
  convenient but Caddy in front of Fly Machines does the same thing at
  smaller scale).

No application code lives at the edge. The Workers Worker, if it survives at
all, is a thin proxy to the Fly app — same role Caddy could play.

### Migration phases (operational detail in the broker doc)

The transition is documented in [`docs/broker-fly-migration.md`](../../docs/broker-fly-migration.md).
Five phases, in order:

1. **Phase 0 — Scaffolding.** Phoenix+Ash app on Fly, fresh Postgres, feature
   flag in workbook CLI (`WORKBOOKS_BROKER_ELIXIR=1`) routes to the new app
   for testing.
2. **Phase 1 — Identity.** Magic-link + WorkOS OIDC via `ash_authentication`.
   Author signing keys, sessions, user lookup. Shadow-write to D1 + Postgres
   for one week; cut over when no discrepancies for 48h.
3. **Phase 2 — Workbook + agent metadata.** Workbook lifecycle routes, agent
   registry, group management, folders, taxonomy, presence. Same D1→Postgres
   shadow-write pattern.
4. **Phase 3 — Artifact storage.** Port the R2 client to Elixir. R2 itself
   stays as the default backend; credentials migrate from CF binding to a
   regular S3 access key.
5. **Phase 4 — Tool dispatch via Luerl.** Replace Workers-for-Platforms
   dispatch with Watershed's Luerl runtime + stdlib. Same workbook publish
   flow, same Lua handler shape, sandboxed BEAM execution instead of WfP
   isolates. Per-call resource limits (max instructions, wall-clock, memory)
   configurable per org.
6. **Phase 5 — Decommission Cloudflare Worker.** What's left in the CF zone
   is config: DNS, cache, WAF. The Worker either disappears or shrinks to a
   thin pass-through. `WORKBOOKS_BROKER_ELIXIR=1` becomes the default.

### Honest framing of why this isn't two plans

The broker doc was written first, before the Watershed name existed. Reading
it against the current Watershed architecture: every load-bearing decision
already aligns.

| Broker doc choice | Watershed equivalent |
|---|---|
| "Lua via Luerl, sandboxed per call" | DECISIONS §2.3 (luerl in BEAM) |
| "No NIFs for dispatch" | DECISIONS §2.3 + §2.10's NIF rejection |
| "No Port-driven external process" | Same |
| "Ash for resource modeling" | DECISIONS §2.7 |
| "Per-call resource limits" | Cost-cap properties on agent stages (`skills/watershed/agents.md`) |
| "Outbound HTTP via host proxy" | `http.*` namespace in §3 |

Treat the broker doc as the **operational** transition plan (route lists,
shadow-write strategy, acceptance criteria) and Watershed as the **architectural**
target. They describe the same system from different angles. After migration,
the broker doc gets archived; this plan becomes the canonical reference for
the unified system.

### Use existing libraries — don't reinvent

Watershed leans on the existing Elixir / Hex ecosystem aggressively. The
broker migration in particular should pick proven libraries over custom code:

| Concern | Library to use |
|---|---|
| Auth (magic-link, OIDC, sessions) | `ash_authentication` + `ash_authentication_phoenix` |
| Email transport (for magic-link delivery) | `swoosh` — provider-agnostic SMTP/API send; required by `ash_authentication`'s magic-link strategy |
| WorkOS OIDC strategy | `ash_authentication`'s OAuth2 strategy with WorkOS endpoints |
| Resource modeling + policies | `ash` + `ash_postgres` |
| Admin UI (resources, actions) | `ash_admin` (replaces bespoke `/v1/admin/*`) |
| Telemetry / runtime dashboard | `phoenix_live_dashboard` (built-in metrics, processes, ETS, request log) |
| Oban job queue inspector | `oban_web` (browse jobs, retry, cancel) |
| Public API shape | `ash_json_api` (preserves broker URL contract via thin Phoenix wrappers where needed) |
| Reactive shapes | `phoenix_sync` (Electric integration) |
| Background jobs | `oban` |
| Lua runtime | `luerl` (Robert Virding's pure-Erlang implementation) |
| S3 client | `ex_aws_s3` or `req_s3` |
| HTTP client | `req` |
| Telemetry / tracing | `:telemetry` + `OpenTelemetryPhoenix` |

Custom code is reserved for things genuinely specific to Workbooks: the
stdlib bindings between Luerl and Ash, the per-workbook tool handler
loader, the schema-to-Ash codegen. Everything else should be a thin layer
over a well-maintained Hex package.

### What does NOT change vs. the previous plan

- The Watershed stdlib design and classification model (§3, §4).
- The schema declaration syntax (§5).
- The author surface — org-mode + Lua + Svelte (§7).
- Agent authoring via WORG (§8, `skills/watershed/agents.md`).
- Multitenancy via row-level + Ash policies (DECISIONS §2.8).
- The portability claim across hosts (DECISIONS §2.2).

### Open questions surfaced by the integration

1. **Where does the broker's Phoenix app live?** Two options: (a) keep
   `packages/broker/worker` as the directory but replace its TS contents with
   an Elixir app; (b) create `packages/broker/worker-elixir` (broker doc's
   suggested name) and retire the TS one once cutover is complete. Resolve
   when Phase 0 starts.

2. **Does the broker's `ToolHandler` (Lua per workbook) use the same publish
   path as Watershed's `server/*.lua` bundling?** Answer should be yes — single
   publish path, single registration model. If they diverge, the broker doc
   is the canonical operational reference and Watershed's CLI mirrors it.

3. **Vertical slice (§12) — does it need to wait for broker Phases 1–4?**
   Probably not. The slice can run against a minimal Phoenix app standalone
   (no identity, no real auth, single hardcoded tenant). The broker phases
   bring those concerns in production. They can develop in parallel.

---

## 12. Vertical slice — the next concrete move

Before writing more spec or architecture docs, build the smallest end-to-end thing that
exercises every unresolved decision. Scope:

**One workbook, one resource, three operations:**
- Schema: a single `tasks` table.
- Server: `list`, `create`, `complete` Lua functions.
- Client: Svelte component subscribing to `list`, calling `create` and `complete`.
- Multi-user: two browsers see each other's changes in real time.
- Multi-tenant: two organizations see only their own tasks.

**Stack to wire:**
- Phoenix app embedding `watershed` Elixir application.
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

## 13. Build sequence after the slice

Once the vertical slice works:

1. **Write SPEC/stdlib/** — full spec for the ~35 functions, with semantics learned
   from the slice. This becomes the canonical reference.
2. **Extend the slice into a second workbook** — one with agents, one with a different
   reactive pattern (e.g., joined reads, large lists). Surface gaps in the stdlib.
3. **Write SPEC/conformance/** — define what conformance means, draft the first test
   suite.
4. **Build agent runtime** — `agent.define`, agent loop in Elixir, live state
   subscription. Ship the "live agent coordination" demo as the differentiator.
5. **WORG integration** — implement `worg.*` namespace, port the existing WORG-Lua
   execution plan (`wb-4vhr.15`) into Watershed rather than as a separate runtime.
6. **CLI tooling** — schema diff/migration prompts, linter polish, IDE LSP support for
   the stdlib.
7. **Second host implementation** — Rust + mlua, conformance-tested against Studio's
   Elixir host. This is what proves the portability claim.

Each step is gated on the previous one working.

### The broker transition is the critical path, not a side track

The numbered sequence above is the build sequence after the slice. Threaded
through it is the broker-to-Watershed transition, which delivers platform
features (auth, identity, workbook lifecycle, etc.) as the vertical slice
expands into a production system. Concrete order:

| Step | What happens | Broker phase mapping |
|---|---|---|
| 1 | Vertical slice runs | (independent — proves the runtime) |
| 2 | Watershed Phoenix app stood up | Broker Phase 0 (overlaps with step 1) |
| 3 | Identity surface lands | Broker Phase 1 |
| 4 | Workbook + agent metadata lands | Broker Phase 2 |
| 5 | Artifact storage in Watershed | Broker Phase 3 |
| 6 | Stdlib spec drafted (SPEC/stdlib/) | (gates Phase 4) |
| 7 | Tool dispatch via Watershed | Broker Phase 4 — the moment runtime + platform meet |
| 8 | CF Worker decommission | Broker Phase 5 |

After step 8, Watershed is the live platform. Cloudflare-specific application
code is gone. Steps 9-13 above (agent demo, WORG integration, conformance,
CLI polish, second host) are maturation work after the platform lands.

---

## 14. What's intentionally not in this plan

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
- Public-facing Watershed standard release — after the second-host conformance test exists.

Each of these is a future epic, not a "we forgot to plan for it" gap.

---

## 15. How this lands in the monorepo

When the vertical slice is approved and built:

- `docs/watershed/` — this package.
- `apps/studio/workhorse/lib/workhorse/watershed/` — Studio's Phoenix mounts the
  Watershed runtime here (until/unless the Elixir app is extracted as a standalone Hex
  package).
- `packages/workbooks/packages/workbook-cli/` — CLI gains `server/*.lua` compilation step.
- `packages/workbooks/packages/runtime/` — runtime SDK gains `subscribe()` / `call()` /
  `api` codegen integration.
- A new beads epic captures the vertical slice and downstream steps.

---

## 16. Agent developer experience

Watershed's primary developer is an AI coding agent. Every surface should be
designed for an agent to use without human intervention. This section lists
what that means in concrete terms.

### What an agent must be able to do

An agent working on a Watershed-backed workbook needs to:

1. **Discover state** — list tables, list registered agents, list recent jobs,
   show open subscriptions, fetch recent telemetry, read schema for a resource.
2. **Define resources** — write `workbook.schema.lua`, run the schema diff,
   apply migrations. (Files are authored via the agent's normal Edit/Write tools;
   the CLI handles compilation and migration.)
3. **Define agents** — write `agents/<name>.org`, validate via the WORG linter,
   register with Watershed via `mix watershed.agents.publish`.
4. **Define server functions** — write `server/<resource>.lua`, run the
   classifier, validate against the stdlib spec.
5. **Trigger actions** — invoke a server function with explicit args, run a
   stage of an agent plan, enqueue an Oban job, broadcast a PubSub message.
6. **Observe results** — read the return value, check the audit log entry,
   inspect any side effects (jobs enqueued, rows written).
7. **Debug failures** — read the structured error envelope, fetch the stack
   trace if available, see recent telemetry around the failure window.

Each of these has three forms: CLI command, API endpoint, skill that documents
the pattern.

### The CLI shape

Every command:
- Lives under `mix watershed.<noun>.<verb>` (e.g., `mix watershed.tables.list`,
  `mix watershed.agents.publish`, `mix watershed.jobs.retry`).
- Accepts `--json` for machine-readable output. Default output is for humans
  but should still be grep-friendly.
- Exits with non-zero status on failure. Errors go to stderr in human mode,
  to stdout JSON envelope in `--json` mode.
- Has a `--help` that doubles as documentation. If the help text is too long
  for stdout, it points at the skill file that explains the pattern.

Initial command set (refined during build):

```
mix watershed.tables.list                    # all tables in current workbook
mix watershed.tables.show <name>             # schema + recent rows
mix watershed.tables.migrate                 # apply schema.lua changes

mix watershed.functions.list                 # all registered Lua functions
mix watershed.functions.classify <file>      # show reactive/mutation/effectful
mix watershed.functions.invoke <name> <args> # call a function directly

mix watershed.agents.list                    # registered agents
mix watershed.agents.publish <path>          # register an .org file as agent
mix watershed.agents.run <slug> <prompt>     # invoke an agent
mix watershed.agents.state <run-id>          # current agent run state

mix watershed.jobs.list [--queue Q] [--state S]
mix watershed.jobs.retry <id>
mix watershed.jobs.cancel <id>

mix watershed.audit.list <workbook-id>       # audit log
mix watershed.audit.verify <workbook-id>     # chain verification

mix watershed.telemetry.recent               # recent telemetry events
mix watershed.telemetry.errors               # error events only

mix watershed.ops.health                     # liveness + DB + queues
mix watershed.ops.console                    # IEx remote (auth-gated)
```

This is the surface skill `skills/watershed/cli.md` will document.

### The API shape

A stable HTTP/JSON contract under `/ops/*` mirrors the CLI:

```
GET    /ops/tables                          # list
GET    /ops/tables/:name                    # show
POST   /ops/tables/migrate                  # apply schema

GET    /ops/functions                       # list
POST   /ops/functions/:name/invoke          # invoke

GET    /ops/agents
POST   /ops/agents/publish
POST   /ops/agents/:slug/run
GET    /ops/agents/runs/:id

GET    /ops/jobs?queue=&state=
POST   /ops/jobs/:id/retry
DELETE /ops/jobs/:id

GET    /ops/audit/:workbook_id
GET    /ops/audit/:workbook_id/verify

GET    /ops/telemetry/recent
GET    /ops/telemetry/errors

GET    /ops/health
```

Auth via the same `ash_authentication` session as the dashboard (operator role
required). Token-based access for agents via long-lived ops tokens (issuable
via `mix watershed.tokens.create` and scopable to specific operations).

### Skills as the agent's documentation

The `/skills/watershed/` directory is the agent's primary teaching surface.
Planned skill files (each loaded on demand by name, per the operating-rules
skill model):

```
/skills/watershed/
├── SKILL.md           # overview + frontmatter (exists)
├── agents.md          # agent architecture in org-mode (exists)
├── cli.md             # every CLI command + usage patterns (TBD)
├── api.md             # every /ops/* endpoint + request/response shapes (TBD)
├── stdlib.md          # the Lua stdlib reference for source blocks (TBD)
├── data-modeling.md   # writing workbook.schema.lua, migrations (TBD)
├── debugging.md       # how to inspect state, read logs, find errors (TBD)
└── publishing.md      # how `workbook publish` works end-to-end (TBD)
```

The TBD skills land as the corresponding subsystems ship. Each skill follows
the existing convention: YAML frontmatter (name, description, triggers) +
body explaining patterns with examples.

### Response shape discipline (the boring but critical part)

Every API and CLI response that an agent might parse follows the same envelope:

```json
{
  "ok": true,
  "data": { ... },
  "warnings": []
}
```

Or on failure:

```json
{
  "ok": false,
  "error": {
    "code": "TABLE_NOT_FOUND",
    "message": "No table named 'taks' in current workbook. Did you mean 'tasks'?",
    "hint": "Run `mix watershed.tables.list` to see available tables.",
    "trace_id": "01HQ..."
  }
}
```

Error codes are stable strings (`TABLE_NOT_FOUND`, `CLASSIFIER_REJECTED`,
`AUTH_REQUIRED`, etc.) — never error message text — so agent code can branch
on them reliably. Hints are agent-actionable: "run this command to recover."

### Why this matters more than the dashboard

The dashboard is a convenience for humans who occasionally check on the
system. The CLI + API + skills are how Watershed is *operated*. An AI coding
agent shipping a workbook never opens the dashboard — it inspects state via
CLI, writes schema files via Edit, runs migrations via CLI, debugs failures
via structured error envelopes, and reads skills when patterns are unclear.

If we get this right, the agent's workflow on Watershed feels indistinguishable
from its workflow on the local filesystem. That's the bar.

### What this does NOT mean

- Not "build a complete agent SDK." Agents use existing tools (Read, Edit,
  Write, Bash). The CLI is bash-callable; that's the SDK.
- Not "anti-human." Humans should be able to operate Watershed too — via the
  same CLI, the same dashboard, with the same error messages. The DX bar is
  set for agents because they're stricter consumers; humans get the same
  surface and just see it differently (text instead of JSON, dashboard instead
  of curl).
- Not "agents only." The /ops/* API is callable by anything — scripts, CI/CD,
  monitoring tools, custom integrations. The agent-first framing is about
  *prioritization* of API quality, not exclusivity.

### Build implications

This section adds to the build sequence (§13) without changing its order. Each
operational step from §13 needs to ship with:
- CLI commands for the operations it introduces.
- API endpoints for those same operations.
- A skill file (if a new pattern is introduced) or an update to an existing skill.
- Stable error codes for the failure modes that step introduces.

These are not "follow-on polish." They're acceptance criteria for each step.

---

## 17. Open invitation

This plan is intentionally written so the vertical slice (Section 12) can start *next*.
Treat sections 3–10 as the design space that the slice will harden. If the slice surfaces
that any decision in `DECISIONS.md` was wrong, update that doc first and this plan
second — `DECISIONS.md` is the source of truth for *why*, this plan is the source of
truth for *what*.
