# Audit — Data schema declaration

## The two approaches

| Approach | File | Lines |
|---|---|---|
| A: Lua table | `a-lua.lua` | 40 |
| B: Org-mode | `b-org.org` | 55 |

(No "hybrid" approach — putting Lua source blocks inside an org file
for schema declaration is strictly worse than pure Lua, since schema
is pure data with no executable component.)

## Scoring criteria

### Verbosity

- **A:** 40 lines for three tables with 18 total fields. Each field
  is one line in the `fields` table.
- **B:** 55 lines for the same content. Each field becomes a sub-
  headline with a properties block. ~3× more vertical space per field.

**Winner: A decisively. Schemas are pure structured data, and
Lua tables are the canonical syntax for structured data.**

### LLM authoring fluency

- **A:** Strong. Lua table-of-tables is universally familiar.
- **B:** Mediocre. Org-mode property syntax for tabular schema data
  is uncommon in training corpora. LLMs will produce inconsistent
  property formatting (`:TYPE: uuid` vs `:type: uuid` vs `:TYPE: UUID`).

**Winner: A decisively.**

### Reviewability

- **A:** Excellent. Schema fits on a screen, fields read as columns.
- **B:** Acceptable for one table; gets unwieldy at 3+ tables. The
  visual structure (heavy headline hierarchy, nested properties) is
  designed for prose/planning documents, not flat data lists.

**Winner: A.**

### Composition / extension

- **A:** Adding a computed field, a complex policy, or a custom
  validator means extending the Lua table shape. Stays in one place.
- **B:** Same operation requires more property keys, deeper headline
  nesting. Properties don't compose as cleanly as nested tables.

**Winner: A.**

### What about runtime integration?

- **A:** Lua table parsed by the Watershed CLI; generates Ash resource
  modules + migrations.
- **B:** Org-mode parsed by WORG; the schema tables generated from
  parsed headlines/properties. Adds an extra translation layer with
  no benefit.

**Winner: A. No reason to involve org-mode for this.**

## Verdict

**Approach A wins decisively. Keep `workbook.schema.lua` as a Lua
file.** Schemas are pure declarative data; Lua tables are the natural
syntax. Org-mode adds noise without unlocking any benefit (no DAG, no
state machine, no source blocks).

## Implication

The principle that emerges: **org-mode for things with structure +
execution + state (agents, pipelines, plans, runnable skills). Lua
for things that are pure declarative data (schemas, config) or pure
code (utilities, helpers, tool implementations inside org files).**

These two domains don't overlap. Don't try to make them.
