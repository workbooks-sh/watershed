# `agent.*` conformance — token tests

> Part of the [Watershed conformance suite](./README.md). Tests assume the
> format documented in the [README §1.2](./README.md#12-test-block-format).

Agent invocation requires a published agent. v0 tests cover the
not-found path.

### test: agent.invoke rejects unknown path

`AGENT_NOT_FOUND` when no agent file exists at the path.

#+SCRIPT:
```lua
return agent.invoke("agents/does_not_exist.org", { topic = "x" })
```

#+EXPECT: error
AGENT_NOT_FOUND

---

### test: agent.state rejects unknown run

`AGENT_RUN_NOT_FOUND` for missing run IDs.

#+SCRIPT:
```lua
return agent.state("00000000-0000-0000-0000-000000000000")
```

#+EXPECT: error
AGENT_RUN_NOT_FOUND
