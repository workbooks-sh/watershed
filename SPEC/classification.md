# Watershed Function Classification Specification

> Defines how the publish-time classifier walks a Lua server function's AST
> and labels it `:pure`, `:reactive`, `:mutation`, or `:effectful`. The
> classification determines runtime behavior — whether the function backs
> a reactive subscription, runs in a transaction, or escapes both.
>
> Status: v0 draft.
>
> Cross-references: [PLAN.md §4](../PLAN.md) (classification overview),
> [stdlib/](./stdlib/) (per-function classification annotations),
> [conformance/classifier.md](./conformance/classifier.md) (test cases).

---

## 1. Why classify

Watershed needs to know, at publish time, what a server function will do
when called. This shapes three things:

1. **Reactivity wiring.** Functions classified `:reactive` get a
   Phoenix.Sync shape registration. Others don't.
2. **Transaction wrapping.** Functions classified `:mutation` run inside
   a single Postgres transaction. Others don't.
3. **Effect auditing.** Functions classified `:effectful` get every
   side-effect call (HTTP, Oban enqueue, etc.) logged to the audit
   trail. Pure / reactive / mutation functions don't.

The classification is the runtime's contract with the author: write a
function with these properties, and we'll wire it up these ways. The
classifier rejects ambiguous or unsafe patterns at publish so they can't
make it to production.

## 2. The four classifications

| Class | Meaning | Runtime behavior |
|---|---|---|
| `:pure` | No host state read or written. Deterministic given args. | Function runs without any transaction or reactivity wiring. Result is cached if `@cache` is set. |
| `:reactive` | Reads host data, no writes, no side effects. Deterministic given snapshot. | Wired as a Phoenix.Sync shape subscription. Client gets initial snapshot + WAL-driven updates. |
| `:mutation` | Writes to the host's data layer. No external side effects. | Wrapped in a Postgres transaction. Rollback on error. Reactive subscribers see the change via Electric. |
| `:effectful` | Calls external services or has observable non-data side effects. | No reactivity, no transaction. Each effectful stdlib call audited. |

A function is exactly one of these. The classifier never returns a
mixed or "either" classification — it picks one based on the rules
below or rejects with `CLASSIFIER_REJECTED`.

## 3. Classification rules — by stdlib usage

The classifier walks the function's AST and records which stdlib namespaces
each call site touches. The classification follows from the union.

| Calls observed | Classification |
|---|---|
| Only `crypto.hash`, `crypto.hmac`, `json.*` | `:pure` |
| `db.read*`, plus any pure | `:reactive` |
| Any of `db.write`, `db.update`, `db.delete`, `db.transaction`, `db.raw`, plus reads/pure | `:mutation` |
| Any of `broker.*`, `http.*`, `oban.*`, `pubsub.*`, `time.*`, `uuid.*`, `agent.*`, `fs.put`/`fs.delete` | `:effectful` |
| `worg.parse`, `worg.query` (read-only) on a host-optional host | follows the data-touching class |
| `worg.update_todo`, `worg.append_logbook` | `:mutation` (host-optional) |

`fs.get` and `fs.list` are `:reactive` (read-only). `fs.put` and `fs.delete`
are `:mutation` of the blob storage layer. The classifier treats them
analogously to db reads/writes.

### 3.1 Priority of classifications

When a function's calls span multiple categories, the highest one wins:

```
:effectful > :mutation > :reactive > :pure
```

So a function that calls `db.read` and `oban.enqueue` is `:effectful`
(not `:reactive`). The presence of any effectful call disqualifies
reactive shape wiring.

### 3.2 No mixing of mutation and effectful in transactions

A function classified `:mutation` may **not** call any `:effectful`
stdlib functions inside its body. The classifier rejects this pattern.

Rationale: effects inside transactions are ambiguous on rollback. If
the transaction rolls back but the effect (HTTP call, Oban enqueue,
external API mutation) has already happened, you have a phantom side
effect with no corresponding state change.

The pattern is:
- Mutations stay pure (data writes only).
- Effects happen after the transaction commits (use `oban.enqueue`
  with deferred execution if needed).

To deliberately enqueue an Oban job that runs after a transaction, the
mutation function returns and the caller enqueues:

```lua
-- server/tasks.lua
return {
  -- :mutation
  create = function(ctx, args)
    return db.write("tasks", { text = args.text, status = "open" })
  end,

  -- :effectful — caller does the side effects after the mutation
  create_and_notify = function(ctx, args)
    local task = call.server("create", args)
    oban.enqueue("notify_team", { task_id = task.id })
    return task
  end,
}
```

`call.server` is a stdlib reference to another server function (TBD;
mentioned in `stdlib/agent.md` open questions).

## 4. Annotations

Authors influence classification via Lua comment annotations on the
function. All annotations live in the lines immediately above the
function declaration, prefixed `--@`.

### 4.1 `--@effect`

Marks a function explicitly as `:effectful` even if static analysis
wouldn't reject it. Use when:

- The function conditionally calls an effectful stdlib (the conditional
  branch might never execute, but the function as a whole must be
  treated as effectful).
- The function calls another internal helper that the author knows
  is effectful, but the classifier can't infer that.

```lua
return {
  --@effect
  notify_if_owner = function(ctx, args)
    local task = db.read_one("tasks", args.task_id)
    if task.assigned_to == ctx.user.id then
      oban.enqueue("send_email", { to = task.assigned_to_email })
    end
  end,
}
```

Without `--@effect`, the classifier rejects the conditional `oban.enqueue`
with `CLASSIFIER_AMBIGUOUS` because static analysis can't prove the
condition always runs the effect.

### 4.2 `--@cache(ttl)`

Marks a `:pure` or `:reactive` function for result caching. The runtime
caches the result keyed on args (and, for `:reactive`, on the underlying
read snapshot).

```lua
return {
  --@cache(60)  -- cache for 60 seconds
  list_active_tags = function(ctx, args)
    return db.read("tags", { where = { active = true } })
  end,
}
```

Invalidations: cache entries are invalidated automatically when the
underlying tables change (for `:reactive`). For `:pure`, the cache is
keyed only on args and lives until TTL.

`--@cache` on `:mutation` or `:effectful` functions is rejected
(`CACHE_INVALID_TARGET`).

### 4.3 `--@shared-data`

Marks a function that operates on `tenant = "shared"` tables. Required
because shared-data access bypasses tenant filtering — the classifier
won't allow it without the explicit opt-in.

```lua
return {
  --@shared-data
  --@effect
  log_to_global_audit = function(ctx, args)
    db.write("global_audit_log", { event = args.event, source = ctx.workbook_id })
  end,
}
```

Without `--@shared-data`, calls to shared-tenant tables produce
`SHARED_DATA_NOT_AUTHORIZED`.

### 4.4 `--@raw-tenant-check`

Marks a function using `db.raw` that has been manually verified to
include `WHERE tenant_id = $...`. Without this annotation, `db.raw`
calls produce a publish-time **warning** (not error) about potential
cross-tenant access.

```lua
return {
  --@raw-tenant-check
  daily_aggregates = function(ctx, args)
    return db.raw([[
      SELECT date_trunc('day', created_at) as day, COUNT(*) as n
      FROM tasks
      WHERE tenant_id = $1 AND created_at >= $2
      GROUP BY day
    ]], { ctx.tenant, args.since })
  end,
}
```

The annotation is the author's assertion that they've reviewed the
query and that tenant scoping is correct.

## 5. Rejected patterns

The classifier raises `CLASSIFIER_REJECTED` at publish time for these
patterns. Errors include the source location so the author can find
and fix the issue.

### 5.1 Effect inside `db.transaction`

```lua
return {
  bad = function(ctx, args)
    db.transaction(function()
      db.write("tasks", { text = args.text })
      oban.enqueue("send_email", { to = args.email })  -- REJECTED
    end)
  end,
}
```

Reason: see §3.2.

### 5.2 Conditional effect without `--@effect`

```lua
return {
  bad = function(ctx, args)
    if args.notify then
      oban.enqueue("send_email", { to = args.email })  -- REJECTED
    end
  end,
}
```

Reason: can't tell from static analysis whether the function should be
reactive (if the branch is dead) or effectful. Add `--@effect` to commit.

### 5.3 Dynamic stdlib dispatch

```lua
return {
  bad = function(ctx, args)
    local fn = db[args.action]  -- REJECTED — dynamic dispatch
    return fn("tasks", {})
  end,
}
```

Reason: the classifier can't determine what stdlib function gets called
at runtime. Dynamic dispatch through stdlib namespaces is rejected
unconditionally.

### 5.4 Recursive server-function calls without annotation

```lua
return {
  recursive = function(ctx, args)
    if args.depth > 0 then
      call.server("recursive", { depth = args.depth - 1 })  -- REJECTED without --@recursive
    end
  end,
}
```

Reason: unbounded recursion is a runtime risk. Author must opt in with
`--@recursive max=N`.

### 5.5 Calling `pubsub.subscribe` in a server function

```lua
return {
  bad = function(ctx, args)
    pubsub.subscribe("topic", function(msg) ... end)  -- REJECTED
  end,
}
```

Reason: subscriptions live longer than a single request. They're only
valid in long-lived contexts (agent stages, job loops).

### 5.6 Cross-namespace effects in a marked `:pure` function

```lua
return {
  --@pure
  bad = function(ctx, args)
    return time.now()  -- REJECTED — time.* is effectful
  end,
}
```

Reason: `--@pure` is an assertion. Calls to non-pure stdlib break it.
(The `--@pure` annotation is rarely needed — the classifier infers
purity automatically. Author would use it to forbid future edits from
sneaking in effects.)

## 6. Per-call audit log

Every `:effectful` function call produces an audit entry the host writes
to `Workbooks.AuditEntry`:

```json
{
  "workbook_id": "...",
  "function": "server.tasks.notify_assignee",
  "classification": "effectful",
  "called_at": "2026-...",
  "duration_ms": 12,
  "effects": [
    { "kind": "http.post", "url": "https://api.example.com/...", "status": 200 },
    { "kind": "oban.enqueue", "worker": "send_email", "job_id": "..." }
  ],
  "trace_id": "01HQ..."
}
```

Effects are recorded for tracing and replay. The audit log is hash-chained
per workbook (see broker migration Phase 2).

`:mutation` calls also emit audit entries, but with `effects: []` — the
data changes themselves are tracked separately via Ash's change-tracking.

`:pure` and `:reactive` calls don't emit audit entries (high volume,
no security value).

## 7. Output: how the classifier surfaces results

At publish time (`workbook publish` or `mix watershed.publish`), the
classifier walks every server function and produces a manifest:

```json
{
  "server_functions": {
    "tasks.list": { "classification": "reactive", "stdlib_calls": ["db.read"] },
    "tasks.create": { "classification": "mutation", "stdlib_calls": ["db.write"] },
    "tasks.notify": {
      "classification": "effectful",
      "stdlib_calls": ["oban.enqueue"],
      "annotations": ["@effect"]
    }
  },
  "tools": { ... },
  "agents": { ... }
}
```

The manifest is registered with Watershed alongside the Lua source. At
request time, the runtime uses the manifest entry (not re-classification)
to decide how to dispatch.

## 8. Annotation grammar

Annotations follow a fixed pattern:

```
--@<name>[(<args>)]
```

Multiple annotations stack on consecutive lines:

```lua
--@effect
--@cache(60)
--@shared-data
my_function = function(ctx, args) ... end
```

Unknown annotations produce `ANNOTATION_UNKNOWN` errors. New annotations
require a minor-version bump of this spec and the classifier.

## 9. Errors raised by the classifier

| Code | Meaning |
|---|---|
| `CLASSIFIER_REJECTED` | A pattern that's structurally rejected (see §5). |
| `CLASSIFIER_AMBIGUOUS` | Static analysis can't determine classification; author must annotate. |
| `CACHE_INVALID_TARGET` | `--@cache` on a non-pure / non-reactive function. |
| `SHARED_DATA_NOT_AUTHORIZED` | Access to shared-tenant table without `--@shared-data`. |
| `ANNOTATION_UNKNOWN` | Annotation name not recognized. |
| `ANNOTATION_INVALID_ARG` | Annotation arg doesn't parse (e.g., `--@cache(notanumber)`). |
| `DYNAMIC_DISPATCH_DETECTED` | `db[...]`, `crypto[...]`, etc. with non-literal key. |
| `RECURSIVE_CALL_UNANNOTATED` | Server function calls itself without `--@recursive`. |
| `SUBSCRIBE_IN_SHORT_LIVED_CTX` | `pubsub.subscribe` in a server function. |

Every error includes the source file path, line, and column. Hint text
suggests the fix where possible (e.g., "add `--@effect` annotation" for
ambiguous conditionals).

## 10. Conformance

Classifier conformance tests live in [`conformance/classifier.md`](./conformance/classifier.md).
A host's classifier passes conformance when every test in that file
produces the expected classification (or expected error code).

## 11. Versioning

The classifier rules version with `stdlib.md`. Adding a new classification
category (unlikely; the four cover the cases we know) is a major bump.
Adding new annotations or new error codes is minor. Tightening an
already-rejected pattern (e.g., catching a new ambiguous case) is patch.

## 12. Open questions

For the vertical slice to resolve:

1. **`call.server(name, args)` for inter-function calls.** Useful for
   the "mutation + effect" split shown in §3.2. Not yet specified in
   `stdlib/`; needs its own section.
2. **`--@recursive max=N`** — what's a safe N? Probably 10–50. Decide
   when recursion shows up in real workbooks.
3. **Per-call audit entries for `:mutation` and `:effectful`** — what's
   the storage cost at scale? May need sampling for high-volume cases.
4. **Caching key derivation for `:reactive` functions** — depends on
   the read snapshot. Snapshot identity needs Phoenix.Sync support.
5. **Classifier output stability** — when does a re-classification at
   publish time invalidate an existing manifest? Probably any change
   forces re-publish of every function in the workbook to keep the
   manifest consistent.
