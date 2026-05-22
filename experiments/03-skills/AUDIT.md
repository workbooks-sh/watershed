# Audit — Skills authoring

## The three approaches

| Approach | File | Lines |
|---|---|---|
| A: Markdown (current) | `a-markdown.md` | 35 |
| B: Org-mode, static | `b-org-static.org` | 32 |
| C: Org-mode + executable Lua | `c-org-executable.org` | 44 |

## Scoring criteria

### Verbosity

- **A:** Markdown is the lightest. Frontmatter is yaml; body is prose.
- **B:** Org-mode equivalent is similar weight. Headers use `*` instead
  of `#`; properties via `#+KEY:` instead of yaml.
- **C:** Adds source blocks. Each example adds ~5 lines, but the
  examples become *runnable*, not just illustrative prose.

**Winner: A and B basically tie on verbosity; C adds bytes but gains
runnable examples.**

### LLM authoring fluency

- **A:** Strong. Markdown is the most-trained doc format on the planet.
- **B:** Acceptable. Org-mode is less common in training data, but the
  structure is intuitive enough that LLMs handle it correctly with
  light guidance.
- **C:** Acceptable. Same as B for the prose; LLMs already write Lua
  source blocks for tools.

**Winner: A wins narrowly; B and C are close.**

### Loadability into existing infrastructure

- **A:** Already works. Current skill system parses markdown frontmatter
  via Vite glob. No changes needed.
- **B:** Requires teaching the skill loader to parse `#+KEY:` directives
  instead of (or in addition to) yaml frontmatter. Small change, but
  a change.
- **C:** Same as B, plus the WORG executor (which parses source blocks)
  has to be wired into the skill-execution path for the runnable
  examples.

**Winner: A. B and C cost migration work.**

### Reviewability

- **A:** Excellent. Markdown renders cleanly in any viewer.
- **B:** Good. Org-mode is readable raw and renders well in Emacs /
  some Markdown-compatible viewers. Slightly less ubiquitous.
- **C:** Same as B for the prose. Source blocks are a clear visual
  separator between "what we're explaining" and "here's how it works
  in code."

**Winner: A; B and C are close runners-up.**

### The thing C unlocks that A and B can't

Skills with executable example blocks let the agent **literally run
the example** to confirm behavior before applying the convention.

This is genuinely valuable:

- A skill teaches "good query syntax." The agent can run the example
  query and see real results, not just trust the prose.
- A skill teaches "citation format." The agent can run the validator
  on a candidate citation before saving.
- A skill teaches "transition the workbook to state X." The agent can
  see what state X looks like.

This is the same idea as Jupyter notebooks: prose + runnable code in
one document, where the code anchors the prose to reality. Pure
markdown can't do this without inventing a "literate execution"
convention.

**For skills that include 'how do you actually do X', C is strictly
better. For skills that are pure convention/style guides, A is fine.**

## Verdict

**No single winner — the right choice depends on the skill's content.**

- **Pure-convention skills** (style guides, anti-patterns, prose-only
  documentation): stay on markdown (A). It's working, it's universally
  understood, no migration cost.

- **Skills that include "here's how" with concrete code or commands:**
  use org-mode with executable Lua source blocks (C). The example IS
  the skill, not just prose about the skill.

- **Static org-mode (B) is the worst of both:** doesn't gain executable
  examples, does pay migration cost. Skip.

## Implication

Don't migrate existing skills. Add a *new* skill format —
`skills/<name>/SKILL.org` — for the cases where executable examples
add value. The skill loader recognizes both `.md` and `.org` and
handles each appropriately:

- `.md` → frontmatter parsing, body as prose only.
- `.org` → property-block parsing, source blocks registered with
  luerl so the agent can execute them.

Authors choose per-skill which format fits. Most existing skills stay
markdown. New skills with executable content use org-mode.

This is *additive*, not migratory.

## One concern worth flagging

If a skill's executable example block has side effects (writes to DB,
calls external APIs), running it as part of skill consumption is
dangerous. Convention should be:

- `#+begin_src lua :results value` — read-only, safe to auto-run.
- `#+begin_src lua :results none` — has side effects, never auto-run,
  shown to the agent as illustration only.

Or stronger: the skill loader rejects source blocks that aren't
explicitly tagged as read-only. The author has to opt into "this
example is safe to execute." Default to safe.
