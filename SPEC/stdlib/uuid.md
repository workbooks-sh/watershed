# `uuid.*` — UUID generation

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

### `uuid.v4()`

**Classification:** `:effectful` (non-deterministic). **Portability:** required.

**Returns:** Random UUIDv4 string.

### `uuid.v7()`

**Classification:** `:effectful`. **Portability:** required.

**Returns:** Time-ordered UUIDv7 string. Preferred for new primary keys —
sequential-by-time benefits b-tree indexes.
