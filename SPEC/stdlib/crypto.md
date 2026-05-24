# `crypto.*` — Hashing and signing

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

OTP `:crypto` + `:public_key` primitives, wrapped to be Lua-callable.

### `crypto.hash(algo, data)`

**Classification:** `:pure`. **Portability:** required.

**Args:**
- `algo` (string, required) — `"sha256"`, `"sha512"`, `"blake2b"`.
- `data` (string, required) — Bytes to hash.

**Returns:** Hex-encoded digest string.

**Errors:**
- `CRYPTO_ALGO_UNSUPPORTED`.

### `crypto.hmac(algo, key, data)`

**Classification:** `:pure`. **Portability:** required.

**Args:**
- `algo` (string, required) — `"sha256"`, `"sha512"`.
- `key` (string, required) — Secret key.
- `data` (string, required) — Bytes to MAC.

**Returns:** Hex-encoded MAC string.

**Errors:**
- `CRYPTO_ALGO_UNSUPPORTED`.

**Note:** Signing with author keys (Ed25519) is NOT exposed here — that's a host
concern, not a workbook concern. Lua scripts can request signatures via
`broker.fetch("/ops/sign/...")`.
