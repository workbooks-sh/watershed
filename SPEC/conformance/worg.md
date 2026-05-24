# `worg.*` conformance — host-optional

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

Hosts without WORG support raise `NOT_IMPLEMENTED` for every call.
Runners report this as skip rather than fail.

### test: worg.parse on basic document

#+SCRIPT:
```lua
local doc = worg.parse("* TODO First task :tag:\n** Subtask\n")
return type(doc)
```

#+EXPECT: shape
```json
"@string"
```

(Result shape is host-defined; just verifies the function returns SOMETHING
on a host that supports WORG. Detailed shape tests go in WORG's own suite.)

---

### test: worg.update_todo on unknown id

#+SCRIPT:
```lua
return worg.update_todo("* TODO :tag:", "no-such-id", "DONE")
```

#+EXPECT: error
WORG_HEADLINE_NOT_FOUND
