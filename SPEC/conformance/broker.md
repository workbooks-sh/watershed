# `broker.*` conformance — token tests

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

Full broker testing needs the operations API stack. v0 tests cover
the surface-level failure modes.

### test: broker.fetch rejects unknown endpoint

`BROKER_ENDPOINT_NOT_FOUND`.

#+SCRIPT:
```lua
return broker.fetch("/ops/not-a-real-endpoint")
```

#+EXPECT: error
BROKER_ENDPOINT_NOT_FOUND

---

### test: broker.execute rejects unknown connection

`CONNECTION_NOT_FOUND`.

#+SCRIPT:
```lua
return broker.execute("not-a-real-connection", "any.action", {})
```

#+EXPECT: error
CONNECTION_NOT_FOUND
