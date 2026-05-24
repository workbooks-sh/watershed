# `crypto.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: crypto.hash sha256 of empty string

Known-value test for SHA-256 of empty input.

#+SCRIPT:
```lua
return crypto.hash("sha256", "")
```

#+EXPECT: exact
```json
"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
```

#+CLASSIFY: :pure

---

### test: crypto.hash sha256 of "hello"

Known-value test for SHA-256 of `"hello"`.

#+SCRIPT:
```lua
return crypto.hash("sha256", "hello")
```

#+EXPECT: exact
```json
"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
```

---

### test: crypto.hash rejects unknown algorithm

`CRYPTO_ALGO_UNSUPPORTED` on unsupported algo names.

#+SCRIPT:
```lua
return crypto.hash("md4", "anything")
```

#+EXPECT: error
CRYPTO_ALGO_UNSUPPORTED

---

### test: crypto.hmac sha256 known value

HMAC-SHA256 with key `"key"` and data `"The quick brown fox jumps over the lazy dog"`.

#+SCRIPT:
```lua
return crypto.hmac("sha256", "key", "The quick brown fox jumps over the lazy dog")
```

#+EXPECT: exact
```json
"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
```
