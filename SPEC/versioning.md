# Watershed Spec Versioning

> Semver discipline across the Watershed specs (`stdlib/`, `conformance/`,
> `schema.md`, `classification.md`) and how the runtime implementations
> track versions.
>
> Status: v0 draft.
>
> Cross-references: every other spec file references this one for the
> "Versioning" section convention. This file is the source of truth.

---

## 1. What versions

Five things have versions:

1. **`stdlib/*.md`** — the function contract.
2. **`conformance/*.md`** — the executable spec.
3. **`schema.md`** — the workbook.schema.lua format.
4. **`classification.md`** — the publish-time classifier rules.
5. **Runtime implementations** — Watershed-Elixir, future Watershed-Rust, etc.

The four spec families version together as one `watershed-spec` version.
Implementations version independently and declare which spec version they
target.

## 2. Spec versioning rules (semver)

| Change kind | Bump |
|---|---|
| New required stdlib function | minor |
| New host-optional stdlib function | minor |
| New optional argument to an existing function | minor |
| New error code | minor |
| New annotation in `classification.md` | minor |
| New field type in `schema.md` | minor |
| New conformance test | minor |
| Clarification (doc text only, no behavior change) | patch |
| Example added / improved | patch |
| Cross-reference fix | patch |
| Removed stdlib function | **major** |
| Renamed stdlib function | **major** |
| Changed argument shape (positional → table, type change) | **major** |
| Changed return shape (added required field, removed field) | **major** |
| Changed default behavior (e.g., transactional semantics) | **major** |
| Changed classification of an existing function | **major** |
| Removed or renamed an error code | **major** |
| Tightened a previously-rejected classifier pattern | **major** |
| Removed an annotation | **major** |
| Changed default tenant model in `schema.md` | **major** |

### 2.1 Patch examples (not exhaustive)

- Reword a function description in `stdlib/db.md` without changing semantics.
- Add a code example to an existing function.
- Fix a typo or broken link.
- Move text between sections without rewriting it.

### 2.2 Minor examples

- Add `db.read_paginated` as a new function. Hosts that don't support it
  raise `NOT_IMPLEMENTED`; conformant hosts on the new minor version
  implement it.
- Add an `--@cache(ttl)` annotation. Old hosts ignore it (no caching);
  new hosts honor it.
- Add error code `CONNECTION_TIMEOUT` to `broker.fetch`. Callers using
  the old version see `BROKER_TIMEOUT` only; new callers can branch on
  the more specific code.

### 2.3 Major examples

- Rename `db.read_many` to `db.batch_read`. Existing Lua code breaks.
- Change `agent.invoke` to require a third argument. Existing callers
  break until updated.
- Reclassify `time.now()` from `:effectful` to `:reactive` (hypothetical
  — would break reactivity model).
- Remove `db.raw` (forcing all SQL through Ash). Existing escape-hatch
  callers break.

## 3. Pre-1.0 (where we are now)

Until v1.0.0 stable, the rules are looser:

- Minor bumps may include breaking changes if documented in the
  changelog. (This is standard pre-1.0 behavior.)
- v0.x → v0.(x+1) bumps may rename functions or restructure namespaces
  if the cost-benefit is clearly positive.
- Conformance test failures during pre-1.0 are expected as the spec
  settles.

v1.0.0 ships when:
- The Elixir reference implementation passes 100% of required
  conformance tests.
- A second host (Rust + mlua, or another) passes the same tests.
- The spec has been frozen for at least 30 days without breaking changes.

After v1.0.0, the table in §2 applies strictly.

## 4. Runtime implementation versioning

Implementations (e.g., the Watershed Elixir app, a future Rust host)
version independently of the spec:

- The implementation has its own version (e.g., Watershed-Elixir v0.5.2).
- The implementation declares which `watershed-spec` versions it claims
  to support, e.g., `~> 0.4` for "any 0.4.x".
- An implementation passing conformance for `watershed-spec v0.4.7` may
  also pass `v0.4.8` if no new required tests were added — it just
  hasn't been re-verified. Re-verify on the next minor bump of the spec.

## 5. Workbook compatibility

A workbook's `workbook.config.mjs` declares the spec version it was
authored against:

```js
export default {
  slug: "my-workbook",
  type: "spa",
  watershed_spec: "~> 0.4",
}
```

Watershed hosts refuse to deploy workbooks whose declared spec version
isn't in the host's supported range. The CLI surfaces this as
`SPEC_VERSION_INCOMPATIBLE` with the offending workbook + host versions.

Hosts may advertise multiple supported spec versions for migration windows
(e.g., a host that supports both `v0.4.x` and `v0.5.x` during the
transition between major versions).

## 6. Conformance and version skew

When the spec moves from `v0.N` to `v0.(N+1)`:

1. The conformance suite gains new tests for new functions / errors.
2. Existing hosts re-run conformance; tests they pass remain passing.
3. New required tests must be implemented for the host to claim
   `v0.(N+1)` support.

When the spec moves from `v0.N` to `v1.0.0`:

1. The full conformance suite is frozen for 30 days.
2. Every implementation re-runs the full suite from scratch.
3. Workbooks that declared `~> 0.N` need their `watershed_spec` updated
   to `~> 1.0` (and possibly other Lua changes if v1.0 changed surfaces).

After v1.0, breaking changes require a coordinated cross-host bump
plus a deprecation window for authored workbooks.

## 7. Deprecation policy

Functions or annotations marked for removal:

1. Get a `@deprecated` annotation in the spec doc with a "removed in"
   target version.
2. Continue to work for at least one minor version before removal.
3. Removed only in major versions, with a clear "removed in v2.0.0"
   note.

The classifier emits a warning at publish for workbooks using deprecated
functions. The warning is not an error until the targeted removal
version.

## 8. Changelog discipline

Every spec change ships with a changelog entry. The changelog lives in
`docs/watershed/CHANGELOG.md` (TBD — to be created when the spec
ships a first non-draft version). Format:

```markdown
## v0.5.0 — 2026-N-N

### Added
- `db.read_paginated(table, query, page_token)` — pagination support
  for large result sets.
- New error code `STREAM_TIMEOUT` for long-running reactive queries.

### Changed
- (none)

### Deprecated
- `oban.enqueue_at` — use `oban.enqueue(_, _, { schedule_at = ... })`
  instead. Removed in v1.0.

### Fixed
- (none)
```

## 9. Spec doc headers

Every spec file (`stdlib/<ns>.md`, `conformance/<ns>.md`, `schema.md`,
`classification.md`) opens with a status block:

```markdown
> Status: v0 draft. <free-form note about stability>
>
> Cross-references: ...
```

When v1.0 ships, replace `v0 draft` with `v1.0.0` (or whatever current
version applies). Patch bumps don't require updating every spec file's
header — only the top-level changelog.

## 10. Tagging in git

Spec versions correspond to git tags on `workbooks-sh/workbooks-mono`:

- `watershed-spec-v0.5.0` — tag of the commit that ships spec v0.5.0.
- `watershed-spec-v1.0.0` — the v1.0 freeze.

Implementation versions tag their own subtree:

- `watershed-elixir-v0.3.4` (on the subtree push to `workbooks-sh/watershed`).

The mono repo uses `watershed-spec-vX.Y.Z` tags as the canonical version
reference. Implementations and workbooks reference these tags when
declaring compatibility.

## 11. Versioning of this file

This file (`versioning.md`) ships at v0 alongside the rest of the spec
set. Future changes to the rules above are themselves subject to the
rules: breaking changes to versioning policy are major bumps of the
spec; clarifications are patch bumps.

## 12. Open questions

For v1.0 to lock in:

1. **What's the exact test for "30 days frozen"?** Probably: no commits
   touching `SPEC/` for 30 days before the v1.0 tag.
2. **How does the implementation declare its claimed spec range?**
   Probably a `mix watershed.version` command that prints both the
   implementation version and the spec version it targets.
3. **Workbook upgrade tooling.** When a spec major bump breaks workbooks,
   is there a `mix watershed.upgrade-workbook --to=v1.0` that mechanically
   updates `workbook.schema.lua` and Lua source? Likely yes for common
   patterns; manual for complex cases.
4. **Multi-version host support windows.** If we ship v1.0 and v0.x
   workbooks are still in the wild, how long does a host promise to
   support v0.x? Probably 12 months from v1.0 GA.
5. **Versioning of stdlib namespaces.** Right now the spec versions
   as a whole. Could individual namespaces version independently? E.g.,
   `db.*` is v0.5 but `worg.*` is v0.3. Probably overcomplicated; defer
   unless a concrete need emerges.
