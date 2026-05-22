# Audit — Simple Agent (researcher with 2 tools)

## The three approaches

| Approach | File | Lines |
|---|---|---|
| A: Pure Lua DSL | `a-lua-dsl.lua` | 40 |
| B: Pure org-mode (declarative) | `b-org-declarative.org` | 27 |
| C: Org-mode + Lua source blocks | `c-org-with-lua.org` | 33 |

## Scoring criteria

### Verbosity

- **A (Lua):** ~40 lines. Each tool needs ~15 lines (name, description,
  args table, handler function). Agent definition is ~10 more.
- **B (Org declarative):** ~27 lines. Shortest, but only because it's
  hiding the implementation behind a `:CALL:` property that a runtime
  has to interpret. Doesn't scale to non-trivial tool bodies.
- **C (Org + Lua blocks):** ~33 lines. Slightly more than B because
  source blocks have boilerplate, slightly less than A because the
  metadata is properties instead of nested tables.

**Winner: C (when measuring real-world tools), B (only for tools that
fit the declarative shape, which is < 20% in practice).**

### LLM authoring fluency

- **A:** Strong. LLMs handle Lua tables fluently; this is essentially
  the same shape as Convex/Mastra/LangChain agent definitions they've
  seen in training.
- **B:** Weak. The `:CALL:`, `:PARAM_MAP:`, `:ARGS:` properties are a
  custom DSL the LLM doesn't know. It'll write them inconsistently and
  the runtime has to compensate.
- **C:** Strong. Org-mode + Lua source blocks is a recognizable pattern
  (Emacs, Jupyter-adjacent, literate programming). LLMs write both
  parts well in isolation; the boundary is natural.

**Winner: A and C tie; B loses.**

### Human review

- **A:** Acceptable but dense. Reading the file requires understanding
  Lua table-with-functions syntax. The structure (system, tools list,
  agent definition) is not visually distinct from the implementation.
- **B:** Excellent for structure (clear headlines, properties), but
  the `:CALL:` discipline obscures what the tool actually *does*.
- **C:** Best of both. Headlines and properties give you scannable
  structure; source blocks give you "see exactly what this does." A
  reviewer can skim headlines, drill into one tool's source block.

**Winner: C decisively.**

### Composition / extension

- **A:** Tools are first-class Lua values, easy to require/share across
  agents. But agent extension (adding dependencies, validators, cost
  tracking) requires adding new top-level keys to the table and
  growing the DSL.
- **B:** Excellent. Org-mode's existing conventions (`:DEPENDS_ON:`,
  `:KIND:`, `:LOGBOOK:`, tags, drawers) provide a deep extension
  surface without inventing anything. But still can't actually
  *execute* anything novel.
- **C:** Excellent. Same extension surface as B (it IS B with bodies).
  Tools can be moved between files by cut-and-paste. Properties can
  carry arbitrary metadata (cost caps, tenant scopes, validators).

**Winner: C; B is conceptually equivalent but can't execute.**

### Runtime semantics

- **A:** Runtime has to interpret a Lua table as an agent definition.
  Custom semantics — reactivity classification, transaction wrapping,
  agent loop — all live in the `agent.define` host. Familiar pattern
  but a real Whack-specific runtime.
- **B:** Runtime has to interpret org-mode properties as executable
  semantics. Either a property-to-code transpiler (fragile) or a deep
  property registry (verbose). Either way, the org file no longer
  describes its own behavior — the host's interpretation does.
- **C:** Runtime is straightforward. The org file describes the agent.
  Source blocks are executed by luerl when the WORG executor walks
  the DAG. No additional layer.

**Winner: C decisively. The WORG executor already exists.**

## Verdict

**Approach C wins clearly.** Org-mode for structure + Lua source blocks
for implementation. The only approach where:

- The existing infrastructure (WORG parser, query, mutation, executor)
  does the heavy lifting.
- Both layers (structure and execution) are in their native idiom.
- LLM authoring is fluent in both halves.
- Reviewers can scan or drill at their preferred level.

**Approach B fails** because the declarative-only ceiling is too low —
real tools need real code.

**Approach A is viable but redundant.** It builds an agent framework in
Lua that duplicates what WORG already provides for structure, and it
inherits no benefit from WORG's DAG / state machine / drawers / tags.

## Implication

The Whack stdlib supplies the *vocabulary* that Lua source blocks call
into (`http.*`, `db.*`, etc.). The agent shape, multi-stage flow,
dependencies, and validation are pure org-mode — no Whack DSL needed
for that layer.
