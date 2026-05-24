# `fs.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: fs.put + fs.get roundtrip

Write and read back a small blob.

#+SCRIPT:
```lua
fs.put("hello.txt", "world", { content_type = "text/plain" })
local got = fs.get("hello.txt")
return { bytes = got.bytes, content_type = got.content_type }
```

#+EXPECT: exact
```json
{ "bytes": "world", "content_type": "text/plain" }
```

#+CLASSIFY: :mutation

---

### test: fs.get on missing path

`FS_NOT_FOUND` for nonexistent blobs.

#+SCRIPT:
```lua
return fs.get("not/a/real/path.txt")
```

#+EXPECT: error
FS_NOT_FOUND

---

### test: fs.put rejects path traversal

Paths containing `..` or leading `/` are rejected at the boundary.

#+SCRIPT:
```lua
return fs.put("../escape.txt", "nope")
```

#+EXPECT: error
FS_PATH_INVALID

---

### test: fs.list with prefix

Listing returns only matching paths.

#+SCRIPT:
```lua
fs.put("a/one.txt", "1")
fs.put("a/two.txt", "2")
fs.put("b/three.txt", "3")
local entries = fs.list("a/")
local paths = {}
for i, e in ipairs(entries) do paths[i] = e.path end
table.sort(paths)
return paths
```

#+EXPECT: exact
```json
["a/one.txt", "a/two.txt"]
```

---

### test: fs.delete removes the blob

After delete, `fs.get` returns `FS_NOT_FOUND`.

#+SCRIPT:
```lua
fs.put("removable.txt", "x")
fs.delete("removable.txt")
local ok, err = pcall(function() fs.get("removable.txt") end)
return { ok = ok, code = err and err.code }
```

#+EXPECT: exact
```json
{ "ok": false, "code": "FS_NOT_FOUND" }
```
