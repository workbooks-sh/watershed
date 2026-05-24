# Watershed

**A backend standard for AI-agent-authored applications.**

Watershed is the spec — and a reference implementation — for backends
that host long-lived, agent-operable applications. It bundles a small
Lua stdlib (the surface agents call into), a luerl-based runtime (Lua
on the BEAM), and a Postgres + Ash + Phoenix.Sync + Oban data layer
into a single, portable contract. Self-hosted on a stock Phoenix +
Postgres + Fly stack. No Cloudflare dependency. No vendor lock-in.

## Why a standard

Most "backend for an AI app" stacks pick a database, glue an HTTP
framework on top, and call it done. That works until the next agent
needs to talk to the same data — at which point you discover every
team built a different shape and nothing composes.

Watershed defines:

- **A Lua surface (~30–50 functions)** that agent-authored scripts
  call: `db.*`, `broker.*`, `agent.*`, `oban.*`, `pubsub.*`, `http.*`,
  `worg.*`, etc. Same surface for server scripts and per-app tool
  handlers.
- **A data layer contract** built on Postgres + Ash + Phoenix.Sync
  (Electric) + Oban — so reactive queries, background jobs, and
  multi-tenancy aren't bolted on later.
- **An operator surface** — every action available via API is also
  available via CLI, same identifiers, same response shapes, JSON-by-
  default for agent consumption.
- **A portability guarantee** — the same Lua and the same Ash data
  model run against any conforming host (reference Phoenix
  implementation today, future Rust + mlua, future browser-side Lua).

## Design priorities

- **Agent-first developer experience.** In a working deployment, a
  human never has to open the admin UI. The CLI and API are primary;
  the dashboard is a convenience.
- **Portability over magic.** No closed runtime, no vendor-specific
  APIs in the contract. R2 is the default blob backend but explicitly
  swappable for any S3-compatible store.
- **Source of truth is files.** Schemas, agent definitions, and
  server functions are authored in plain files (org-mode + Lua) that
  fit existing agent workflows. No forms-in-a-dashboard authoring.

## What Watershed is *not*

- Not a database. (Uses Postgres.)
- Not a UI framework.
- Not Cloudflare-dependent.
- Not a hosting product — anyone can self-host.
- Not a Convex clone. (Borrows ideas — reactive queries, schema-as-API
  — without the closed-runtime constraint.)

## Layout

```
watershed/
├── PLAN.md              what we're building + build sequence
├── DECISIONS.md         why we chose what we chose
├── LIBRARIES.md         external library due diligence
├── SPEC/                the standard
│   ├── stdlib/          function-by-function reference per module
│   ├── conformance/     what an implementation must satisfy
│   ├── schema.md        data model contract
│   ├── classification.md  function classification (pure / effect / etc.)
│   └── versioning.md    compatibility rules
└── experiments/         prototype workbenches + findings
```

## Status

Watershed is in **planning / spec phase**. The vertical-slice
implementation is the next concrete move. See [`PLAN.md`](./PLAN.md)
§12 for sequence and [`DECISIONS.md`](./DECISIONS.md) for the
reasoning trail.

The reference implementation will be an Elixir/Phoenix app
(`Watershed.*` module namespace) deployable to Fly. Implementations in
other languages — Rust + mlua, browser-side — are explicitly in scope
for the portability contract.
