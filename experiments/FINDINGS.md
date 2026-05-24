# Findings — Where Org-Mode, Lua, and Svelte Live

> Synthesis across the four experiments. Each experiment compared 2–3
> ways of expressing the same thing; this document distills the
> boundaries that emerged.

## The four experiments — results at a glance

| Experiment | Winner | Why |
|---|---|---|
| 01 — Simple agent | Org-mode + Lua source blocks | Structure native to org, execution native to Lua |
| 02 — Multi-agent orchestration | Pipeline org file referencing per-agent org files | DAG, state machine, observability come from WORG for free |
| 03 — Skills | **Both** — markdown for prose, org-mode for executable examples | Different content, different format |
| 04 — Data schema | Lua table | Pure declarative data is what Lua tables are good at |

## The principle that emerged

**Org-mode owns structure + execution + state.** Anything with:

- Hierarchical sections + metadata (planning, agent specs, skills with steps)
- Explicit dependencies / DAG (multi-stage pipelines, blocking workflows)
- State machine (TODO → DOING → DONE → FAILED transitions)
- Logging / observability (`:LOGBOOK:`, `:RESULTS:`, `:ARTIFACT:`)
- Executable bodies (source blocks)

…belongs in org-mode. The infrastructure (WORG parser, query API,
mutation API, executor) already exists. Use it.

**Lua owns pure code.** Anything with:

- Pure declarative data (schemas, config)
- Library/utility functions
- Tool implementations (inside org source blocks)
- Glue between stdlib primitives

…belongs in Lua. Lua tables are the natural shape for structured data;
Lua functions are the natural shape for "do this thing."

**Svelte owns the UI.** Everything the user sees in the browser stays
in Svelte 5. No change from prior plans.

## The three-language author surface (final)

```
.org files       — agents, pipelines, skills (when executable), plans
.lua files       — schemas, libraries, tool helpers
.lua blocks      — inside .org files, as tool / stage / validator bodies
.svelte files    — UI components
```

Authors never write Elixir, Rust, or JS directly. The runtime
(Phoenix/luerl/Ash/Electric) is platform infrastructure they don't
touch.

## What this changes about the prior PLAN.md

The earlier plan put agent authoring in Lua (`agent.define`,
`agent.plan_follower`, etc.). That's wrong. Concrete changes:

1. **Remove agent authoring from the Lua surface entirely.** No
   `agent.define`, no agent DSL in Lua. Agents are .org files.

2. **The Watershed stdlib stays.** It's still the vocabulary that Lua
   source blocks (inside org files) call into. `db.*`, `broker.*`,
   `http.*`, `oban.*`, etc. all stand.

3. **Add `agent.invoke(path, args)` to the stdlib** for sub-agent
   composition from inside source blocks. Other `agent.*` functions
   become unnecessary because the pipeline pattern handles orchestration.

4. **The Watershed agent runtime is WORG's executor.** No separate Lua
   agent loop. The WORG-Lua execution stub (`wb-4vhr.15`) becomes the
   Watershed agent runtime — same luerl host serves both.

5. **Agent architecture moves to its own document:** `/skills/watershed/agents.md`.
   PLAN.md references it. Keeping it separate from PLAN.md lets the
   agent architecture evolve independently of the stdlib/data-layer plan.
   (Originally drafted as `docs/watershed/AGENTS.md`; relocated per the
   no-AGENTS.md operating rule — see CLAUDE.md.)

6. **Skills can be markdown or org-mode.** Existing markdown skills
   stay as-is. New skills with executable examples can use .org. The
   skill loader handles both formats.

## What this clarifies about Watershed's scope

Watershed is now sharply defined:

**Watershed IS:**

- The Lua stdlib spec (`db.*`, `broker.*`, `http.*`, `agent.invoke`, etc.)
- The luerl runtime hosted in Phoenix
- The data layer integration (Ash, Phoenix.Sync, Oban, Postgres)
- The CLI tooling (compile `server/*.lua` + `workbook.schema.lua`,
  bundle into the .html artifact)
- The runtime SDK extensions on the client (`subscribe`, `call`)

**Watershed IS NOT:**

- An agent framework (that's WORG)
- A planning DAG (that's WORG)
- A state machine for tasks (that's WORG)
- A markup format (that's org-mode)

This is a much smaller, sharper scope than the prior PLAN.md implied.
That's good — it means Watershed ships sooner and integrates cleanly with
the existing WORG infrastructure rather than competing with it.

## Open questions surfaced by the experiments

1. **Data flow between pipeline stages** (experiment 02 AUDIT) — small
   results inline in `:RESULTS:` drawers vs. large results to Postgres
   with references. Resolve during vertical slice.

2. **Skill execution safety** (experiment 03 AUDIT) — auto-running
   read-only source blocks vs. requiring explicit opt-in. Resolve when
   the first org-mode skill ships.

3. **Cross-cutting properties** (experiment 02 AUDIT) — `:COST_CAP_USD:`,
   `:RETRIES:`, `:REQUIRES_APPROVAL:` and similar. Define a standard
   property vocabulary or accept ad-hoc per-pipeline. Resolve as
   patterns emerge from real pipelines.

4. **Should the per-stage system prompt** (experiment 02-B) live on
   the stage headline as a property, or in the referenced agent's own
   SYSTEM block, or both with override semantics? Resolve during
   vertical slice.

## Next concrete actions

1. **Write `/skills/watershed/agents.md`** — the agent architecture as a
   standalone document, building from the experiments. Done.
2. **Strip agent content from `PLAN.md`** — replace Section 8 with a
   one-paragraph pointer to `/skills/watershed/agents.md`. Done.
3. **Update `DECISIONS.md`** — add the decision: "agents are org-mode,
   not Lua DSL" with rationale from these experiments.
4. **Build the vertical slice** (PLAN.md Section 12) — same scope, but
   with the corrected agent model.
