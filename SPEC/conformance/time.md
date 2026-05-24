# `time.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: time.now returns ISO 8601 UTC

Format check, not exact-value (clock moves).

#+SCRIPT:
```lua
return time.now()
```

#+EXPECT: shape
```json
"@timestamp"
```

#+CLASSIFY: :effectful

---

### test: time.monotonic returns a number

Returns milliseconds as a number.

#+SCRIPT:
```lua
local t = time.monotonic()
return type(t)
```

#+EXPECT: exact
```json
"number"
```

---

### test: time.monotonic is non-decreasing

Two consecutive calls: second ≥ first.

#+SCRIPT:
```lua
local a = time.monotonic()
local b = time.monotonic()
return b >= a
```

#+EXPECT: exact
```json
true
```
