# Resource-limit conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

Tests for per-call wall-clock, memory, and reductions caps. Runners may
configure relaxed caps for unrelated tests but must use production caps
for these.

### test: LUA_DEADLINE_EXCEEDED on infinite loop

A script that won't terminate must be killed by the wall-clock cap.

#+SCRIPT:
```lua
while true do end
```

#+EXPECT: error
LUA_DEADLINE_EXCEEDED

---

### test: LUA_MEMORY_EXCEEDED on unbounded growth

Allocating beyond the memory cap raises the corresponding error.

#+SCRIPT:
```lua
local big = {}
for i = 1, 1e8 do big[i] = string.rep("x", 1024) end
return #big
```

#+EXPECT: error
LUA_MEMORY_EXCEEDED
