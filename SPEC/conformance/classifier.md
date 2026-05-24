# `classifier.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

The classifier (PLAN.md §4) is a publish-time check that labels server
functions. Conformance tests for the classifier verify category assignment.

### classifier test: pure function

A function calling only `:pure` stdlib functions classifies as `:reactive`-
eligible (no effects, but reads no host state either; safe to mark as
`:reactive` since the caller's intent decides).

#+SCRIPT:
```lua
local function hash_string(args)
  return crypto.hash("sha256", args.input)
end
return classifier.classify(hash_string)
```

#+EXPECT: exact
```json
":reactive"
```

(The runner provides `classifier.classify` as a host-specific helper for
conformance tests; not part of the user-facing stdlib.)

---

### classifier test: reactive function

A function calling only `db.read*` is `:reactive`.

#+SCRIPT:
```lua
local function list_open(args)
  return db.read("tasks", { where = { status = "open" } })
end
return classifier.classify(list_open)
```

#+EXPECT: exact
```json
":reactive"
```

---

### classifier test: mutation function

A function calling `db.write` is `:mutation`.

#+SCRIPT:
```lua
local function create(args)
  return db.write("tasks", { text = args.text, status = "open" })
end
return classifier.classify(create)
```

#+EXPECT: exact
```json
":mutation"
```

---

### classifier test: effectful function

A function calling `oban.enqueue` is `:effectful`.

#+SCRIPT:
```lua
local function notify(args)
  oban.enqueue("send_email", { to = args.email })
end
return classifier.classify(notify)
```

#+EXPECT: exact
```json
":effectful"
```

---

### classifier test: rejects conditional effect without annotation

A function with a conditional `oban.enqueue` call must be marked `--@effect`
or the classifier rejects.

#+SCRIPT:
```lua
local function maybe_notify(args)
  if args.notify then
    oban.enqueue("send_email", { to = args.email })
  end
end
return classifier.classify(maybe_notify)
```

#+EXPECT: error
CLASSIFIER_REJECTED

---

### classifier test: accepts conditional effect with annotation

With `--@effect`, the same function is accepted as `:effectful`.

#+SCRIPT:
```lua
local function maybe_notify(args)
  --@effect
  if args.notify then
    oban.enqueue("send_email", { to = args.email })
  end
end
return classifier.classify(maybe_notify)
```

#+EXPECT: exact
```json
":effectful"
```

---

### classifier test: rejects effect inside db.transaction

Effects inside a transaction are forbidden — `:mutation` and `:effectful`
don't mix transactionally.

#+SCRIPT:
```lua
local function bad(args)
  db.transaction(function()
    db.write("tasks", { text = args.text })
    oban.enqueue("send_email", { to = args.email })
  end)
end
return classifier.classify(bad)
```

#+EXPECT: error
CLASSIFIER_REJECTED
