# Watershed Stdlib Conformance Suite

> Runnable spec for [`stdlib/`](../stdlib/README.md). Every Watershed-conformant host
> must pass the tests below for the functions tagged `Portability: required`.
> Host-optional functions (currently `worg.*`) are skipped on hosts that opt out.
>
> Status: v0 draft. Initial coverage focuses on `db.*`, `crypto.*`, `json.*` and
> establishes the test format. Other namespaces have token tests demonstrating
> the pattern; expand as functions land.
>
> Cross-references: [stdlib/README.md](../stdlib/README.md) (the contract), [PLAN.md §4](../../PLAN.md)
> (classifier), [DECISIONS.md §2.2](../../DECISIONS.md) (portability claim).

---

## Namespace index

Per-namespace conformance tests:

- [`db.*`](./db.md) — Data layer reads, writes, transactions, raw SQL.
- [`crypto.*`](./crypto.md) — Hash and HMAC known-value tests.
- [`json.*`](./json.md) — Parse, encode, error modes.
- [`time.*`](./time.md) — `time.now` shape, monotonic ordering.
- [`uuid.*`](./uuid.md) — v4 and v7 shape, ordering, distinctness.
- [`oban.*`](./oban.md) — Argument validation tokens.
- [`http.*`](./http.md) — Egress-control failure modes.
- [`agent.*`](./agent.md) — Not-found paths.
- [`broker.*`](./broker.md) — Surface-level rejections.
- [`pubsub.*`](./pubsub.md) — Broadcast fire-and-forget, subscribe rejection.
- [`fs.*`](./fs.md) — Put/get roundtrip, path traversal, listing.
- [`worg.*`](./worg.md) — Host-optional, skipped on hosts that don't implement.
- [`classifier`](./classifier.md) — Classifier conformance tests.
- [`limits`](./limits.md) — Resource-limit conformance.

Reference material:

- [`fixtures.md`](./fixtures.md) — Schemas + seeds reused across tests.

---

## 1. How to run the suite

### 1.1 What a conforming host provides

A test runner needs the host to expose:

1. **A fresh tenant.** Each test starts with an empty tenant scope: no rows in
   any table, no jobs in any queue, no blobs in `fs`. The runner calls
   `setup_tenant(tenant_id)` at start.
2. **An eval entry point.** `eval(tenant_id, lua_source) -> result` runs
   `lua_source` inside a luerl state with `ctx.tenant = tenant_id`, returns
   the script's return value as a Lua-to-JSON-converted table, or surfaces
   the structured error on `error(...)`.
3. **A schema apply step.** `apply_schema(tenant_id, schema_lua)` registers
   the tables declared in `schema_lua` (a `workbook.schema.lua` string).
4. **A teardown.** `teardown_tenant(tenant_id)` removes all state. Runner
   calls between tests to keep isolation.

The runner walks this file, extracts each `### test:` block, runs the script
against a fresh tenant, and compares the result to the expected block.

### 1.2 Test block format

Each test is a markdown subsection beginning with `### test:`. Following it:

- An English description (one paragraph).
- A `#+SCHEMA:` block (optional) — if present, the runner calls
  `apply_schema(tenant, ...)` with the schema before running the script.
- A `#+SEED:` block (optional) — Lua script run BEFORE the test script to
  populate state. Failures here fail the test as "setup error."
- A `#+SCRIPT:` block — the Lua under test.
- A `#+EXPECT:` block — the expected outcome (see §1.3).
- An optional `#+CLASSIFY:` block — asserts that the classifier would label
  the script as `:pure`, `:reactive`, `:mutation`, or `:effectful`.

Test blocks are isolated. Setup/seed state does not bleed between tests.

### 1.3 Expectation modes

`#+EXPECT:` blocks declare what the runner asserts. One of three modes:

**Exact** — script's return value must equal the JSON exactly.

```
#+EXPECT: exact
{ "value": 42 }
```

**Shape** — script's return value must match the shape. Keys present, types
correct, values matching nested rules. Recognized type sentinels:
`"@string"`, `"@number"`, `"@uuid"`, `"@timestamp"`, `"@boolean"`, `"@any"`.

```
#+EXPECT: shape
{ "id": "@uuid", "text": "hello", "created_at": "@timestamp" }
```

**Error** — script must raise with `err.code` matching. Other error fields
(message, hint, trace_id, details) are not compared but must be present.

```
#+EXPECT: error
TABLE_NOT_FOUND
```

For shape mode, arrays match positionally; for sparse-array semantics, use
`shape` with `@any` placeholders.

### 1.4 Pass/fail criteria

A host passes the suite when:

- Every `Portability: required` test in this file passes.
- Every `Portability: required` test that the host doesn't pass is documented
  as a known deviation, with a public-facing note. (Used during the
  vertical-slice phase when not all functions are implemented yet.)

Host-optional sections (currently `worg.*`) are reported as skip rather than
fail when the host raises `NOT_IMPLEMENTED`.

---

## 17. What's NOT covered in v0

The following are intentionally out of scope for v0 conformance and
should be added as their associated functions ship:

- **Reactive shape semantics** — `db.read` produces a Phoenix.Sync shape
  when the enclosing function is `:reactive`. Testing this requires a
  subscription harness; deferred to broker Phase 2.
- **Cross-workbook agent invocation** — out of scope per `stdlib.md` §16.
- **`pubsub.subscribe` happy-path** — needs a long-lived test harness
  (agent stage or job loop); deferred to broker Phase 4 work.
- **Full HTTP roundtrip** — needs a controllable upstream; can be added
  with a `httpbin`-style fixture once the host supports test mode.
- **Multi-tenant isolation** — tests that span tenants prove `ctx.tenant`
  is enforced. Add when the second tenant fixture lands in the vertical
  slice.
- **Long-running migration** — `db.raw` with DDL that should be rejected;
  policy TBD (do we allow DDL via `db.raw` in v0? PLAN §5 leaves this
  open). Decide during vertical slice.

When a deferred area becomes coverable, add a `## N. <area> conformance`
section with the same block format. The runner picks up new tests by
default.

---

## 18. Open implementation questions

For the host implementing the runner:

1. **How does `setup_tenant` interact with Ash multitenancy?** Concretely:
   does the runner create a fresh `Orgs.Group` per test, or use a single
   long-lived tenant with truncation between tests? Truncation is faster
   but the tenant id changes — verify ctx.tenant references work either way.
2. **Are timestamps in `:timestamp` JSON sentinel matched as exact strings
   or parsed?** Suggest parsed (ISO 8601 valid, in UTC) so micro-time
   drift doesn't false-fail tests.
3. **`classifier.classify` host helper** — what's the exact API? It runs
   the classifier without executing the function. Document in the host's
   test-runner glue.
4. **How are `fs.*` tests isolated?** Each test should target a fresh
   per-tenant prefix in the storage backend; the runner is responsible
   for cleanup. Consider whether to use a separate test bucket per host
   or per-tenant prefixes.

---

## 19. Versioning

The conformance suite versions with stdlib.md. A breaking change to a
function's signature or error code is a breaking change to the suite;
hosts must re-verify. Additive changes (new functions, new tests for
existing functions) are minor and don't invalidate prior runs.

When v1 stable arrives:
- Tag this file at v1 alongside stdlib.md.
- Any host that previously passed v0 needs to re-run against v1.
- Subsequent minor versions add tests but never invalidate v1 passes
  for already-existing tests.
