# `http.*` conformance — token tests

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

Full HTTP testing needs a controllable upstream (test echo server). v0
tests cover egress-control failure modes that need no upstream.

### test: http.get rejects RFC1918 destinations

Internal IPs blocked by the egress proxy.

#+SCRIPT:
```lua
return http.get("http://10.0.0.1/anything")
```

#+EXPECT: error
HTTP_HOST_BLOCKED

---

### test: http.get rejects malformed URL

DNS or URL parse failure surfaces as `HTTP_DNS_FAILED`.

#+SCRIPT:
```lua
return http.get("http://this-host-cannot-possibly-exist-watershed-conformance.invalid/")
```

#+EXPECT: error
HTTP_DNS_FAILED
