# `oban.*` conformance — token tests

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

The full oban suite needs a registered worker, which is host-specific
plumbing. v0 tests cover argument validation; integration tests come with
the broker Phase 2 work.

### test: oban.enqueue rejects unknown worker

`WORKER_NOT_FOUND` when worker isn't registered.

#+SCRIPT:
```lua
return oban.enqueue("not_a_real_worker", { x = 1 })
```

#+EXPECT: error
WORKER_NOT_FOUND

---

### test: oban.enqueue rejects oversized args

Args > 1MB raise `ARGS_TOO_LARGE`.

#+SCRIPT:
```lua
local big = string.rep("x", 1100000)   -- 1.1MB
return oban.enqueue("any_worker", { payload = big })
```

#+EXPECT: error
ARGS_TOO_LARGE

---

### test: oban.schedule rejects invalid cron

`CRON_INVALID` on syntax errors.

#+SCRIPT:
```lua
return oban.schedule("any_worker", "not a cron", {})
```

#+EXPECT: error
CRON_INVALID
