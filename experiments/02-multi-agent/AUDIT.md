# Audit — Multi-agent orchestration (3-stage research pipeline)

## The three approaches

| Approach | File(s) | Lines | Files |
|---|---|---|---|
| A: Lua orchestrator | `a-lua-orchestrator.lua` | 45 | 1 (+3 agent files elsewhere) |
| B: Monolithic org | `b-monolithic-pipeline.org` | 65 | 1 |
| C: Pipeline with refs | `c-pipeline-with-refs.org` | 30 (+3 agent files) | 4 |

## Scoring criteria

### Verbosity

- **A:** Pipeline file is shortest (45 lines), but Lua's imperative
  shape forces explicit error handling at every stage. Stage count
  scales line count linearly.
- **B:** Monolithic — single file holds everything. Verbose because
  every agent's full definition is inline. Reading "what's the
  pipeline?" requires scrolling past all tool implementations.
- **C:** Pipeline file is *very* short (30 lines, mostly properties).
  Per-agent files exist separately. Total line count higher than A,
  but each file does one thing.

**Winner depends on scale.** For 3 stages, A is shortest. For 10+
stages or shared agents (one researcher used by three pipelines), C
wins because agents are reused, not duplicated.

### LLM authoring fluency

- **A:** Strong. Imperative Lua with sequential `agent.invoke` calls
  is a pattern LLMs handle easily.
- **B:** OK. Org-mode with multiple nested stages + tools per stage
  works, but the LLM has to keep track of which `** TOOL` belongs to
  which `* TODO Stage` headline. Long files increase confusion risk.
- **C:** Strong. Each file is single-purpose; the pipeline file is
  almost pure metadata. LLMs handle small focused files much better
  than monolithic ones.

**Winner: A and C tie; B is weakest for longer pipelines.**

### Human review

- **A:** Reviewer reads sequentially. Easy to understand the flow but
  hard to see "what are the dependencies?" — they're encoded in code
  order, not declared.
- **B:** Reviewer sees everything in one place. Good for self-contained
  audit, but the file gets long quickly. Cognitive load grows.
- **C:** Reviewer sees the pipeline shape at a glance. Drill into
  individual agents on demand. Clearest separation between "what
  orchestrates" and "what executes."

**Winner: C decisively.**

### Composition / extension

- **A:** Reusing an agent across pipelines means calling `agent.invoke`
  from another orchestrator file. Works, but every orchestrator is
  custom Lua. Hard to add cross-cutting features (cost caps, retry
  policies) without rewriting each orchestrator.
- **B:** Everything is in one file — composition means copy-paste
  between pipeline files. Worst extensibility story.
- **C:** Agents are referenced by file path, not embedded. Adding a
  new pipeline = new pipeline.org + references to existing agents.
  Cross-cutting features attach as properties on the stage headlines.

**Winner: C decisively.**

### Runtime semantics

- **A:** Lua function runs through luerl. Each `agent.invoke` is a
  synchronous call (or async + await). The orchestrator owns the state
  machine — if it crashes, the pipeline state is lost unless persisted
  manually.
- **B:** WORG executor walks the DAG. State is in the .org file
  (DOING/DONE/FAILED transitions, logbook entries). Crash recovery is
  free — restart and resume from the last unfinished stage.
- **C:** Same WORG executor walks the pipeline. Plus the executor
  recurses into each agent file (also a WORG document). Two levels of
  DAG: orchestration + per-agent.

**Winner: C decisively. Free crash recovery, free observability, free
state machine.**

### Cross-cutting concerns

What about cost caps, retry policies, budget tracking, audit logs,
human-in-the-loop pauses?

- **A:** Have to be implemented in the Lua orchestrator body. Every
  orchestrator re-implements them. No standard surface.
- **B/C:** Org-mode properties carry these natively. `:COST_CAP_USD:
  5.0` on a stage. `:RETRIES: 3` on a tool. `:REQUIRES_APPROVAL: true`
  on a stage that pauses for human input. The WORG executor already
  knows how to read these (or can be extended to).

**Winner: B and C tie; A loses badly because every cross-cut is
re-invented per orchestrator.**

## Verdict

**Approach C wins for any non-trivial orchestration.** The split
between "pipeline as composition" (one short org file) and "agents as
reusable units" (one file each) matches how real systems are built.

**Approach B is viable for small one-off pipelines** where you want
self-contained portability — a single file that fully describes one
specific multi-agent flow. Use case: research-pipeline-for-this-week
type things that won't be reused.

**Approach A loses** because it builds an imperative orchestration
layer in Lua that recreates everything WORG already does — DAG, state
machine, crash recovery, dependency resolution, observability — and
inherits no benefit from existing infrastructure.

## Implication for orchestration design

- Pipelines are org files that reference agent org files via `:AGENT:`
  properties.
- Inputs/outputs are named on each stage. Threading happens by name
  via `:INPUTS_FROM:` property pointing at upstream stage outputs.
- The Watershed stdlib needs an `agent.invoke(path, args)` function for
  Lua source blocks that want to programmatically run sub-agents
  outside the WORG pipeline pattern (e.g., a tool that internally
  delegates to another agent). But the *primary* orchestration model
  is org-mode pipeline files, not Lua composition.

## Open question

How does data flow between stages? Two candidates:

1. **Named outputs in the .org file's logbook drawer.** Each stage's
   `:RESULTS:` block captures its output; downstream stages reference
   by stage ID + output name.
2. **Postgres tables.** Each stage writes to a results table, downstream
   stages query it.

(1) is more org-native and survives without a DB. (2) integrates with
the reactive subscription model. Probably both — small results inline,
large results to Postgres with a reference. Resolve during vertical
slice, not now.
