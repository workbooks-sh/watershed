# Whack — Decisions & Context

> Companion to `PLAN.md`. This document captures the reasoning behind the architectural
> decisions: what we chose, what we rejected, when to revisit. Read this when something
> in the plan doesn't make sense — the why probably lives here.
>
> Conversation context: derived from a multi-turn architecture discussion (May 2026)
> covering the question "how do we get Convex-like reactivity and multi-tenancy on top
> of Postgres + Phoenix without losing the workbook artifact's portability?"

---

## 1. The architectural pivot

**Where we started:** Workbooks ships as portable `.html` artifacts. Recipients open them
anywhere. Studio's Phoenix Postgres handles auth/identity/admin, but workbook *runtime data*
goes to BYO databases (Supabase / Turso / Convex) via `wb.db(slot)`. The runtime SDK has
no server-defined queries, no reactive subscriptions, no transactional boundaries — authors
hand-wire their own backends.

**The reframing:** If Studio is the managed backend that handles everything for users, and
the wedge is "internal tool that can graduate to public app" (the Slack story, adjusted for
AI-skill distribution), then BYO is the *escape hatch*, not the default. Workbook authors
should declare their data needs and have Studio provide the backend — reactive queries,
multi-tenancy, persistence — without making the workbook stop being portable.

**The architectural decision:** Build a Lua-based authoring layer (Whack) that sits between
the workbook artifact and Studio's Phoenix/Postgres/Ash backend. Lua scripts express
queries, mutations, actions, and agent definitions. The Whack runtime classifies and
executes them. Workbooks can graduate to customer infrastructure because the Lua scripts
are portable across host implementations.

---

## 2. Decisions

### 2.1 Authors write Svelte + Lua. Nothing else.

**Decision:** Workbook UI is authored in Svelte 5. Workbook server logic (queries,
mutations, actions, agent definitions, schema declarations) is authored in Lua. No other
language is part of the author surface. Elixir, Rust, and JS exist underneath as platform
code that authors never touch.

**Why:**
- Two languages is a manageable cognitive load for AI agents (which are the primary
  authors in our model).
- Each language is in its strongest territory: Svelte for reactive UI, Lua for embedded
  scripting.
- LLM-quality on both is sufficient (Svelte is a JS dialect, Lua is small enough for
  agents to handle with good context).

**Alternatives rejected:**
- *Elixir as the server-script language* — locks scripts to BEAM, breaks the portability
  story.
- *JS sandboxed via QuickJS* — viable but adds a runtime we don't otherwise need; Lua is
  more deliberately designed for embedding.
- *Declarative-only HTML DSL* — hits a ceiling fast; authors will demand imperative escape
  hatches and we'll end up reinventing JavaScript poorly.

**When to revisit:** If the second language (Lua) materially slows authoring or causes
persistent agent-quality issues we can't fix with better SKILL.md docs, reconsider whether
JS-via-QuickJS would have been the better second language.

---

### 2.2 Lua is the bridge language across runtimes.

**Decision:** Lua is positioned as a portability contract, not just an authoring choice.
Workbook Lua scripts must run identically against any host that implements the Whack
stdlib — Phoenix/luerl today, Rust/mlua hosts later, browser/Fengari hosts if we ever add
client-side execution.

**Why:**
- Lua is the most production-tested embeddable scripting language. Real precedents:
  Redis, Nginx (OpenResty), Neovim, Roblox, Defold, WoW, Lightroom, Wireshark.
- Embeddability ≠ portability of scripts. Each Lua embedding historically defines its own
  host API. We make portability real by specifying the stdlib and conformance-testing it.
- This is the property Convex cannot offer — Convex scripts only run on Convex's infra.

**Alternatives rejected:**
- *Elixir scripts that happen to be portable* — BEAM-only, not portable.
- *WASM as the universal interchange format* — more complex authoring (Rust or AssemblyScript),
  doesn't gain us much for the orchestration use case.

**Critical caveat:** Lua-as-portability-contract only works if **the stdlib is a real
spec with semver and conformance tests.** Without that, you've added a language without
gaining the property that justified adding it. The stdlib is the load-bearing artifact.

**When to revisit:** If after building the stdlib and one Rust-host implementation,
conformance turns out to be impractical (semantic gaps too wide), the portability claim
needs to be retracted or scoped down.

---

### 2.3 Luerl in BEAM is the primary execution model.

**Decision:** All Whack server-side execution happens through luerl (pure-Erlang Lua
interpreter) hosted in Phoenix. Lua scripts execute as Erlang processes, sandboxed by
construction, supervised by OTP.

**Why:**
- Luerl gives sandboxing *for free* — Lua scripts can do *nothing* by default; capabilities
  are explicitly added by the host. This matches the third-party-publishing roadmap.
- BEAM supervision = crash isolation. One workbook's bad script can't crash Studio.
- Performance overhead (10–100× slower than native Lua) is irrelevant for thin orchestration,
  which is the only thing Whack scripts should do. If a script does heavy compute, that's a
  signal to add a new Elixir/Rust primitive, not to optimize the Lua.

**Alternatives rejected:**
- *mlua via NIF* — fast, but NIFs run in BEAM's address space with full OS access and can
  crash the entire VM. NIFs are *not a sandbox*. Using them for untrusted scripts
  contradicts the security model we picked Lua to get.
- *mlua in a separate OS process (Erlang port)* — viable as a future option for very hot
  paths, but adds operational complexity (another service) we don't need yet.
- *mlua in WASM hosted in BEAM* — the right long-term escape valve if luerl perf ever
  becomes the bottleneck. Sandboxed by WASM design, near-native speed. The repo already has
  WASM infrastructure (`worg-wasm`) that could be extended. Document as planned but don't
  build yet.

**When to revisit:** If profiling shows Lua interpretation (not the primitives it calls)
is the actual bottleneck under realistic load. Until that's measured, luerl stays.

---

### 2.4 Server scripts execute server-side by default. Three modes documented.

**Decision:** A workbook's Lua scripts run server-side on the host (Studio's Phoenix, or
a customer's Phoenix on graduation). The `.html` artifact carries the Lua bundle as
embedded data (a gzipped `<script id="wb-server-bundle">` block) but doesn't execute it
client-side. The host extracts the bundle on receipt and registers it with the workbook ID.

Three execution modes are documented as part of the architecture but only mode 1 ships in v1:

| Mode | Where Lua runs | Use case | Cost |
|---|---|---|---|
| 1: Server | Host Phoenix (luerl) | Multi-user, agents, persistence | Default |
| 2: Client | Browser (Fengari / Lua-WASM) | Single-user, offline, sealed | ~200–400KB artifact growth |
| 3: Hybrid | Both, with sync via Electric | Local-first multi-user | ~3MB with PGlite |

**Why:**
- Mode 1 matches the stated primary use case (internal tools, agents, multi-user).
- Mode 2/3 are real future capabilities but the .html-self-contained property already
  holds in mode 1 (the bundle is in the .html, even if it doesn't execute there).
- Building modes 2 and 3 prematurely doubles or triples the stdlib implementation surface
  (every primitive needs a browser-side equivalent) before we know which workbooks need it.

**Alternatives rejected:**
- *Ship mode 2 first as a "look how portable" demo* — Optimizes the wrong axis; nobody
  asked for offline mode, lots of authors will ask for multi-user reactivity.
- *Force mode 3 (hybrid local-first) on every workbook* — Convex-on-Phoenix at 3× the
  artifact size and 2× the engineering. Premature.

**When to revisit:** When ≥3 real workbooks would meaningfully benefit from mode 2 or 3,
build mode 2 first (simpler than mode 3) as a per-workbook opt-in.

---

### 2.5 The stdlib API is the priority artifact.

**Decision:** Before any code is written, the Whack stdlib spec is drafted as a complete
document: every function's signature, semantics, error model, reactivity classification,
transactional behavior, tenant model, failure modes, and cross-host portability constraints.

**Why:**
- The stdlib is the *contract* that gives Lua portability across runtimes. Without a
  written, conformance-tested spec, "Lua scripts are portable" is marketing, not architecture.
- Treating it as a real spec (semver, breaking-change discipline, deprecations) protects
  authors from drift as the implementation evolves.
- Every other piece of the architecture — Postgres semantics, agent model, WORG integration,
  client codegen — has to commit to specific stdlib functions. Writing the spec forces
  every hand-wave in the architecture to resolve.

**Alternatives rejected:**
- *"30 tools" as a hand-wave* — Already corrected. WORG was claimed to have 30 deterministic
  Lua tools; verification showed it has none implemented. Don't repeat the mistake.
- *Build the implementation, document later* — Documenting after the fact bakes in whatever
  the implementation happened to do, including accidents. The doc has to lead.

**When to revisit:** Spec is a living doc with semver. Revisit per release. No reason to
ever delete this decision.

---

### 2.6 No Convex `query` / `mutation` / `action` trinity at the authoring level.

**Decision:** Authors write plain Lua functions. The runtime classifies each function by
static analysis of which stdlib namespaces it calls. The Convex trinity is preserved
*conceptually* (reactive reads, transactional writes, effectful actions are all distinct
behaviors) but not exposed as wrapper functions in author code.

**Why:**
- Lua is supposed to feel like Lua, not like a Convex DSL wearing Lua syntax.
- Static classification by stdlib usage is unambiguous when authors avoid dynamic dispatch
  (which the linter enforces).
- The Convex naming becomes irrelevant once you don't have to copy their type system or
  their hosted-runtime constraints.

**How classification works:**
- Function only calls `db.read*` → pure read → reactive-eligible.
- Function calls `db.write*` or `db.update*` → mutation → wrapped in a transaction.
- Function calls `broker.*`, `oban.*`, `http.*` → effectful → opted out of reactivity and
  transactional guarantees.
- Linter rejects ambiguous patterns at publish time (dynamic dispatch, conditional effects
  without explicit `--@effect` annotation).

**Alternatives rejected:**
- *Convex naming for parity* — Inherits a constraint we don't need to inherit.
- *Annotation-only classification* (require authors to mark every function) — More
  ceremony than static analysis with no safety gain.

**When to revisit:** If real-world Lua code routinely needs `--@effect` annotations for
conditional patterns the linter can't classify, consider whether explicit annotation
should become the default rather than the fallback.

---

### 2.7 Postgres + Ash + Phoenix.Sync (Electric) + Oban as the Studio implementation.

**Decision:** Whack's reference implementation (Whack-on-Studio) uses:
- **Postgres** on Fly as the system of record. Single primary, Supavisor connection
  pooling, vertical scaling first, read replica second.
- **Ash** + **AshPostgres** for resource definitions, multitenancy, policies, calculations.
  Stdlib `db.*` calls route through Ash.
- **Phoenix.Sync** (built on Electric) for reactive shapes. Reactive Lua functions get
  translated into Electric shape subscriptions.
- **Oban** for background jobs. Stdlib `oban.*` enqueues jobs; workers can be Lua or Elixir.

**Why:**
- Each tool is mature, BEAM-native, and solves a known problem cheaply.
- This stack handles tens of thousands of multi-tenant orgs on a single Postgres before
  scaling becomes a real conversation. Studio's growth ceiling is far above current scope.
- Phoenix.Sync's HTTP shape API works from any client origin, including `file://`, matching
  what the workbook artifact needs.

**Scaling ladder (not "sharding"):**
1. Supavisor (connection pooling — Postgres falls over from connection count before query
   load, so fix this first).
2. Vertical: bigger Fly Postgres machine.
3. Read replica.
4. Vertical partitioning (hot tables to their own Postgres).
5. Tenant sharding — only at very large scale, deferred indefinitely. Graduation to
   customer infrastructure is the pressure-release valve.

**Alternatives rejected:**
- *Switch from Postgres to a document database* — Postgres + jsonb handles document
  workloads cleanly; switching DBs trades a worse transactional story for negligible benefit.
- *Convex-on-Phoenix (build the reactive runtime from scratch)* — Months of work for what
  Phoenix.Sync provides for free.

**When to revisit:** If Phoenix.Sync's shape semantics turn out not to map cleanly onto
the reactive classifications we infer from Lua scripts, we may need a custom reactivity
layer. Monitor this during the vertical-slice build.

---

### 2.8 Multi-tenancy is row-level + Ash policies, not schema-per-tenant.

**Decision:** Tenant identity is a column on every resource (denormalized from the
hierarchy: `org → workspace → workbook_instance → recipient`). Ash policies enforce that
queries are automatically scoped to the active tenant.

**Why:**
- Schema-per-tenant scales operationally to hundreds, not thousands. Workbooks needs to
  scale to tens of thousands of tenants on a single Postgres.
- Row-level + Ash policies is the industry pattern for B2B SaaS at this scale (Linear,
  Notion, Figma all started here).
- Hard tenant isolation (schema-per-tenant) is reserved for graduated enterprise customers
  who get their own Phoenix+Postgres deploy.

**Critical implementation point:** The Whack runtime is the only thing that constructs
`ctx`. Lua scripts can read `ctx.tenant` but never set it. Host discipline, not Lua
discipline.

---

### 2.9 Agents are authored in org-mode, not in Lua. Lua is the source-block language.

**Decision:** Agent definitions live in `.org` files. Tool implementations are Lua
source blocks inside those org files. The Whack stdlib provides the vocabulary for
those source blocks. There is no `agent.define` function in Lua — no agent DSL on the
Lua side at all.

**Why:**

- WORG already provides DAG + state machine + `:LOGBOOK:` + `:RESULTS:` + properties +
  scheduler. A Lua agent DSL would duplicate every one of these.
- The WORG infrastructure (parser, query, mutation, Elixir NIF, executor stub) is
  already built. The outstanding piece (`wb-4vhr.15` — luerl execution) is the same
  piece Whack needs anyway. The two roadmaps merge into one.
- Org-mode is plain-text reviewable, version-control friendly, and supports
  hierarchical composition that Lua tables don't naturally express.
- The cost — agents that would have been 15-line Lua tables are 25-line org files —
  is small. The win — single mental model, single runtime, single infrastructure
  stack — is large.

**Concrete evidence:** four experiments at `packages/whack/experiments/`:

- 01-simple-agent — org+lua source blocks beats pure-Lua DSL on every axis.
- 02-multi-agent — org pipeline file referencing per-agent org files beats Lua
  orchestrator on composition and runtime semantics.
- 03-skills — markdown stays for prose-only skills, org-mode for skills with
  executable examples. Both legitimate.
- 04-data-schema — Lua wins because schemas are pure declarative data, not structure
  + execution.

The synthesis: **org-mode for things with structure + execution + state. Lua for
pure code or pure declarative data. Svelte for UI.**

**Alternatives rejected:**

- *`agent.define` Lua DSL with handlers* — Builds a parallel framework on top of WORG
  without using it. Lots of work, no gain.
- *Lua orchestrator with `agent.invoke` chains* — Imperative shape doesn't carry
  cross-cutting properties (cost caps, retries, approvals); reinvents WORG primitives.

**Implications:**

- `/skills/whack/agents.md` is the dedicated agent architecture doc. PLAN.md §8 points to it. (Previously this lived at `packages/whack/AGENTS.md`; relocated per the no-AGENTS.md operating rule.)
- `wb-4vhr.15` becomes part of Whack v1, not a separate workstream.
- The stdlib's `agent.*` namespace shrinks to just `agent.invoke(path, args)` for
  sub-agent calls from inside source blocks. No `agent.define`, no agent loop API
  exposed to Lua.

**When to revisit:** If real-world authoring shows that the verbosity tax of org-mode
for simple agents is causing genuine friction (LLMs producing malformed org-mode,
authors preferring a Lua shortcut), consider adding `agent.define` as a *Lua-to-org
compiler* — a shortcut that compiles to org-mode at publish time. Don't add it as a
second runtime path.

---

### 2.10 Cloud sandbox VMs are wrapped in Lua, not exposed as raw Rust/Python entry points.

**Decision:** When Whack needs to execute work outside BEAM (heavy compute, untrusted code
beyond what luerl can sandbox, third-party language runtimes), it spins up a Fly.io
ephemeral sandbox VM. The sandbox itself hosts a Lua interpreter (mlua + Rust). Lua inside
the sandbox shells out to Rust/Python/C++/whatever.

**Why:**
- Preserves the bridge-language thesis — same Lua surface across BEAM, browser, sandbox VM.
- Calling Whack code doesn't change based on where execution happens. Authors write
  `sandbox.run({...})`, the platform routes.
- Extensibility property: a fork could swap the sandbox image to run Python or any other
  language. The wrapping Lua keeps the contract stable.

**Cost:** Stdlib has to be implemented (or stubbed appropriately) in each Lua host.
Conformance tests carry this discipline.

**When to revisit:** Sandbox VMs are deferred from v1. Decision recorded so it doesn't
get re-litigated when the first heavy-compute workbook needs it.

---

## 3. Things I (the assistant) got wrong along the way

These corrections are part of the record so the design isn't built on the bad version:

**3.1 "WORG has 30 deterministic Lua tools."**
False. WORG has zero implemented Lua execution today. The executor stub at
`packages/worg/elixir/worg/lib/worg/exec.ex:39` raises `"not yet implemented — wb-4vhr.15"`.
The "30 tools" framing was a verbal hand-wave that turned out not to match the code.
**Correction:** WORG-Lua execution is planned, not built. The Whack stdlib is net-new
engineering; we are not "reusing what's there."

**3.2 "mlua via NIF is the perf escape valve."**
Wrong. NIFs are not a sandbox. They have full OS access and crashes take down the BEAM
VM. Using them for untrusted scripts contradicts the entire reason we picked Lua.
**Correction:** The real perf escape valve is mlua compiled to WASM, hosted by a WASM
runtime in BEAM. Sandboxed by WASM design, near-native speed. Documented in 2.3.

**3.3 "Just keep workbooks BYO-database; don't make Phoenix Postgres the runtime data layer."**
Wrong premise — fights the product vision. Studio *is* the managed backend; BYO is the
escape hatch.
**Correction:** Whack treats Studio's Phoenix Postgres as the default data backend.
Workbooks talk to it through the stdlib. BYO and graduation paths exist as alternative
backends behind the same stdlib contract.

**3.4 "Internal tools rarely need reactive queries."**
Insufficiently considered. The agent-coordination case (humans observing what agents are
doing) requires reactivity by the basic math of bursty mutations vs polling.
**Correction:** Reactive queries are day-one in the v1 plan, not deferred. The agent loop
is the killer demo, not a feature.

**3.5 "Most internal tools never graduate — build for internal-only first."**
Partially wrong, especially in an AI-skill-distribution world where the artifact *is* the
distribution unit. Graduation rates are higher than the Slack-survivor framing implies.
**Correction:** Graduation is a first-class design constraint, not a deferred concern.
The `.html` carries the Lua bundle so a customer host can extract and register it.

---

## 4. Open questions (intentionally unresolved until the vertical slice)

These are flagged so the build phase forces a decision rather than papering over them:

1. **`db.read` → Ash actions vs. raw Ecto?** Default plan: Ash for safety, with `db.raw`
   as an escape hatch for cases Ash can't express. Confirm during slice.

2. **Reactive Lua → Electric shapes — wire-up mechanism.** Two candidates: (a) translate
   reactive function bodies into shape definitions at publish time; (b) subscribe to
   underlying tables and re-execute the Lua on change. Both have tradeoffs; the slice
   should attempt (a) and fall back to (b) if static translation proves brittle.

3. **Schema migration on author edits.** Convex spent years on this; we will not match
   them. v1 strategy: CLI refuses to publish if pending migrations would lose data, prompts
   the author. Production migrations are explicit, not auto-applied.

4. **Oban worker language.** Lua workers via `oban.enqueue("send_email", ...)` need a
   dispatch mechanism that routes to the named Lua function. Open question: do we
   pre-register every worker at publish, or look them up dynamically by name? Slice
   should pick one.

5. **Transaction granularity in mutations.** Default plan: a Lua mutation function = one
   Postgres transaction. Multi-mutation chains require explicit `db.transaction(function()
   ... end)` opt-in. Confirm during slice.

6. **Conformance test format for the stdlib.** What does "this host conforms to Whack
   stdlib v0.3" mean operationally? A test suite of Lua scripts + expected outputs?
   Property-based? Open question; resolve when the second host (mlua) ships.

7. **WORG integration surface.** WORG-Lua execution is planned but unimplemented. How
   tightly does Whack's stdlib bind to WORG's APIs vs. treat WORG as one of many backends?
   Likely answer: WORG functions live in a `worg.*` namespace in the stdlib; Whack hosts
   that implement WORG support expose them, others raise a "not implemented" error.

---

## 5. Things explicitly out of scope for v1

- Client-side Lua execution (mode 2).
- Hybrid / local-first / PGlite (mode 3).
- Cloud sandbox VMs for heavy compute.
- mlua-via-NIF or mlua-via-WASM in BEAM.
- Tenant sharding.
- Schema-per-tenant for non-graduated customers.
- BYO-database escape hatch (deferred — `wb.db(slot)` stays as a v0 surface but isn't
  the focus).
- A non-Lua second implementation host (e.g., Rust-host running Whack workbooks).
- Custom Luau-style typed dialect.

These are documented as future work, not vetoed. The point is to not get distracted
implementing them before the v1 vertical slice exists.
