# `agent.*` — Multi-agent invocation

> Part of the [Watershed stdlib](./README.md). See [error-codes.md](./error-codes.md)
> for the codes referenced below.

Sub-agent calls from inside source blocks. Not used for top-level agent definition
(agents are `.org` files; see DECISIONS §2.9).

### `agent.invoke(path, args)`

**Classification:** `:effectful`. **Portability:** required.

Run an org-mode agent by file path. The WORG executor walks the agent's DAG and
returns when the agent reaches a terminal state.

**Args:**
- `path` (string, required) — Path to the `.org` agent file, relative to the
  workbook root. e.g., `"agents/researcher.org"`.
- `args` (table, optional) — Initial inputs threaded to the agent's first stage.

**Returns:** `{ run_id = "...", status = "DONE"|"FAILED"|"PAUSED"|..., outputs = {...} }`.

**Errors:**
- `AGENT_NOT_FOUND`.
- `AGENT_BUDGET_EXCEEDED` — cost cap on the agent or a stage was hit.
- `AGENT_FAILED` — terminal failure; the run remains queryable via `agent.state`.

### `agent.state(run_id)`

**Classification:** `:effectful` (reads live state). **Portability:** required.

Fetch the current state of an agent run.

**Args:**
- `run_id` (string, required).

**Returns:** Full run state — stages, transitions, logbook entries, results.
Shape matches the `/ops/agents/runs/:id` API response.

**Errors:**
- `AGENT_RUN_NOT_FOUND`.
