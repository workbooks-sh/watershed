# Watershed — Authoring Surface Experiments

These experiments explore where Org Mode, Lua, and Svelte should each
live in the workbooks authoring stack. Each experiment expresses the
same thing in 2–3 different ways, then audits them against concrete
criteria.

The goal isn't to pick a winner abstractly — it's to find the *boundary*
where each tool stops being natural and another starts.

## Experiments

1. **`01-simple-agent/`** — A single research agent with two tools.
   Compares: pure Lua DSL vs. org-mode (declarative-only) vs. org-mode
   with Lua source blocks.

2. **`02-multi-agent/`** — A pipeline of three agents (researcher →
   critic → summarizer). Compares: Lua orchestrator with sub-agent
   invocations vs. monolithic org file vs. cross-referenced org files.

3. **`03-skills/`** — A research-conventions skill. Compares: pure
   markdown (current) vs. static org-mode vs. org-mode with executable
   example blocks.

4. **`04-data-schema/`** — A `findings` table schema. Compares: Lua
   declarative table vs. org-mode property-based vs. hybrid.

Each experiment ends with an `AUDIT.md` scoring the approaches against:

- **Verbosity** (lines of code for the same intent)
- **LLM authoring fluency** (how well does Claude write this?)
- **Human review** (how scannable, how clear)
- **Composition** (how easy to extend, reference, reuse)
- **Runtime semantics** (how clean is the execution model)

Final synthesis is in `FINDINGS.md`.
