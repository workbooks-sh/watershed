# `json.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: json.parse roundtrip on simple object

Parse a small object correctly.

#+SCRIPT:
```lua
return json.parse('{"a":1,"b":"two","c":true,"d":null}')
```

#+EXPECT: exact
```json
{ "a": 1, "b": "two", "c": true, "d": null }
```

#+CLASSIFY: :pure

---

### test: json.parse fails on malformed input

`JSON_PARSE_FAILED` on syntax errors.

#+SCRIPT:
```lua
return json.parse('{not valid json')
```

#+EXPECT: error
JSON_PARSE_FAILED

---

### test: json.encode array vs object

Sequence tables encode as arrays; map tables encode as objects.

#+SCRIPT:
```lua
return {
  arr = json.encode({1, 2, 3}),
  obj = json.encode({a = 1, b = 2}),
  empty = json.encode({}),
}
```

#+EXPECT: shape
```json
{
  "arr": "[1,2,3]",
  "obj": "@string",
  "empty": "@string"
}
```

Note: empty-table encoding (`[]` vs `{}`) is host-defined for ambiguous cases.
Hosts must document the choice; tests don't pin it.

---

### test: json.encode rejects functions

`JSON_ENCODE_FAILED` on non-serializable values.

#+SCRIPT:
```lua
return json.encode({ callback = function() end })
```

#+EXPECT: error
JSON_ENCODE_FAILED
