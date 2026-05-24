# `uuid.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: uuid.v4 returns a uuid string

Shape check.

#+SCRIPT:
```lua
return uuid.v4()
```

#+EXPECT: shape
```json
"@uuid"
```

#+CLASSIFY: :effectful

---

### test: uuid.v4 returns distinct values

Two calls produce distinct UUIDs.

#+SCRIPT:
```lua
return uuid.v4() ~= uuid.v4()
```

#+EXPECT: exact
```json
true
```

---

### test: uuid.v7 returns a uuid string

Shape check for v7.

#+SCRIPT:
```lua
return uuid.v7()
```

#+EXPECT: shape
```json
"@uuid"
```

---

### test: uuid.v7 is time-ordered

Two v7s in sequence: the second sorts ≥ the first as strings.

#+SCRIPT:
```lua
local a = uuid.v7()
local b = uuid.v7()
return b >= a
```

#+EXPECT: exact
```json
true
```
