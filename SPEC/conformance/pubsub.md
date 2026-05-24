# `pubsub.*` conformance

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

### test: pubsub.broadcast succeeds with no subscribers

Broadcasts are fire-and-forget; no error when nobody's listening.

#+SCRIPT:
```lua
pubsub.broadcast("orphan-topic", { x = 1 })
return "ok"
```

#+EXPECT: exact
```json
"ok"
```

#+CLASSIFY: :effectful

---

### test: pubsub.subscribe rejected in regular server function

Subscribing from a per-request context raises `PUBSUB_CONTEXT_INVALID`.

#+SCRIPT:
```lua
pubsub.subscribe("any-topic", function() end)
return "should not reach"
```

#+EXPECT: error
PUBSUB_CONTEXT_INVALID
