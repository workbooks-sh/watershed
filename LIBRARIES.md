# Watershed — External Library Due Diligence

This document is the reference for every external library Watershed depends on per
[`PLAN.md`](./PLAN.md) §11 and [`DECISIONS.md`](./DECISIONS.md) §2.12. For each
library we record current Hex version, maintenance status, license, what we
use it for, key APIs, integration points, gotchas, open questions, and the
alternatives we rejected. **Keep current** by re-verifying versions and
maintenance flags at each quarterly review (or whenever you bump a major
version of any item below). Versions noted as of May 2026.

---

## 1. Summary table

| Library | Version | License | Status | Role |
|---|---|---|---|---|
| `ash` | `~> 3.26` | MIT | green | Resource modeling / actions / policies |
| `ash_postgres` | `~> 2.9` | MIT | green | Postgres data layer for Ash |
| `ash_authentication` | `~> 4.13` (5.0-rc) | MIT | green | Magic-link + OIDC + sessions |
| `ash_authentication_phoenix` | `~> 2.16` (3.0-rc) | MIT | green | Phoenix routes/plugs for auth |
| `ash_admin` | `~> 1.1` | MIT | green | Admin UI over Ash resources |
| `ash_json_api` | `~> 1.6` | MIT | green | JSON:API surface |
| `phoenix` | `~> 1.8` | MIT | green | Web framework |
| `phoenix_live_view` | `~> 1.1` | MIT | green | Server-rendered interactive UI |
| `phoenix_live_dashboard` | `~> 0.8` | MIT | yellow | Telemetry + process dashboard (pre-1.0; release cadence slow) |
| `phoenix_sync` | `~> 0.6` | Apache-2.0 | yellow | Electric integration; **beta**; query support limited |
| `phoenix_pubsub` | `~> 2.2` | MIT | green | Cluster broadcast |
| `oban` | `~> 2.22` | Apache-2.0 | green | Background jobs |
| `oban_web` | `~> 2.12` | Apache-2.0 | green | Job queue UI (open-sourced 2.11+) |
| `luerl` | `~> 1.5` | Apache-2.0 | yellow | Lua 5.3 interpreter in Erlang; small maintainer team; 5.2→5.3 migration "WIP" |
| `ex_aws_s3` | `~> 2.5` | MIT | green | S3-compatible client (default pick) |
| `req_s3` | `~> 0.2` | Apache-2.0 | yellow | Newer Req plugin; pre-1.0; smaller surface |
| `req` | `~> 0.5` | Apache-2.0 | green | HTTP client |
| `:telemetry` | `~> 1.4` | Apache-2.0 | green | Metric dispatch (OTP stdlib-adjacent) |
| `opentelemetry_phoenix` | `~> 2.0` | Apache-2.0 | yellow | Phoenix OTel; release cadence slow (last v2.0.1 Feb 2025) |
| `:public_key` / `:crypto` | OTP | Apache-2.0 (Erlang/OTP) | green | Signing + verification |

Legend: **green** = healthy, actively maintained, low risk to depend on; **yellow** =
maintained but pre-1.0, single-maintainer, or otherwise carries upgrade/feature risk;
**red** = avoid (none in the current pick list — anything red got cut).

---

## 2. Compatibility matrix

Which libraries depend on which. Helps when bumping versions: a major bump to a
"depended-on" row usually drags a coordinated bump elsewhere.

| Library | Direct deps inside Watershed's pick list |
|---|---|
| `ash_postgres` | `ash`, ecto, `:postgrex` |
| `ash_authentication` | `ash` |
| `ash_authentication_phoenix` | `ash_authentication`, `phoenix`, `phoenix_live_view` |
| `ash_admin` | `ash`, `phoenix`, `phoenix_live_view` |
| `ash_json_api` | `ash`, `phoenix` (when mounted in router) |
| `phoenix_live_view` | `phoenix`, `phoenix_pubsub` |
| `phoenix_live_dashboard` | `phoenix_live_view`, `:telemetry` |
| `phoenix_sync` | `phoenix`, Electric (embedded or HTTP), Postgres logical replication |
| `oban` | ecto, `:postgrex` |
| `oban_web` | `oban`, `phoenix_live_view` |
| `luerl` | OTP only (no Hex deps) |
| `ex_aws_s3` | `ex_aws` |
| `req_s3` | `req` |
| `opentelemetry_phoenix` | `:telemetry`, opentelemetry-erlang core, `OpentelemetryBandit` *or* `OpentelemetryCowboy` |

**Implication for upgrades:** an `ash` major bump (e.g., 3 → 4 someday) cascades
through `ash_postgres`, `ash_authentication`, `ash_authentication_phoenix`,
`ash_admin`, and `ash_json_api`. Plan ash bumps as a coordinated release.

The `phoenix` 1.x line has been stable since 2022; LiveView 1.0 landed and 1.1 is
the working line. Bumping LiveView is the riskier axis (more API surface evolves).

---

## 3. Per-library sections

### `ash` — resource modeling, actions, policies, multitenancy

- **Current Hex version**: `~> 3.26` ([hex.pm/packages/ash](https://hex.pm/packages/ash))
- **Maintenance status**: green — released May 22, 2026; weekly release cadence; maintained by `ash-project` org under Zach Daniel
- **License**: MIT
- **What we use it for**: Resource definitions for every Watershed domain — `Identity` (User, AuthorKey, Session), `Workbooks` (Workbook, Lease, AuditEntry, ToolHandler), `Agents`, `Orgs`. Stdlib `db.*` calls route through Ash actions. Ash policies enforce row-level multitenancy (DECISIONS §2.8)
- **Key APIs / patterns**: `Ash.Resource`, `Ash.Domain`, action DSL (`actions do`), `Ash.Policy.Authorizer`, calculations, aggregates, `Ash.create/2`, `Ash.read/2`, `Ash.update/2`. Multitenancy via `multitenancy do strategy :attribute end`
- **Integration points with other Watershed libraries**: `ash_postgres` is the storage backend; `ash_authentication` extends User resources; `ash_admin` browses any Ash resource for free; `ash_json_api` exposes Ash actions as JSON:API; Phoenix.Sync shape definitions can be derived from Ash read actions
- **Known gotchas / limitations**:
  - **Ash 3.0 was a hard break from 2.x.** `Ash.Api` → `Ash.Domain`; `default_accept` went from "all writable attributes" to `[]`; anonymous-function changes can no longer be atomic without `require_atomic? false` or a module change. Older blog posts/screencasts still teach 2.x patterns — verify against current docs
  - Atomic-update model is strict; for non-atomic operations you need either module changes implementing `atomic/3` or explicit `require_atomic? false`
  - Policy debugging benefits hugely from `Ash.can?` and the policy explanation tooling — don't try to read policy failures from raw error structs
- **What we'd need to verify**: That the schema-to-Ash codegen we'll write (PLAN §5) can target the Ash 3.x DSL cleanly. Verify that `Ash.Domain` modules generated at runtime (vs compile-time) work — Ash typically expects compile-time domains
- **Alternatives considered**: Plain Ecto (rejected — Ash 2.12 explicitly chose Ash to get policies, actions, JSON:API, admin UI for free); `Absinthe`-only model (loses transactional action semantics)

### `ash_postgres` — Postgres data layer for Ash

- **Current Hex version**: `~> 2.9` ([hex.pm/packages/ash_postgres](https://hex.pm/packages/ash_postgres))
- **Maintenance status**: green — 2.9.1 released May 1, 2026; same maintenance team as `ash`
- **License**: MIT
- **What we use it for**: Persistence layer for every Ash resource. Owns migration generation (`mix ash_postgres.generate_migrations`), schema diffing, foreign key + index inference, custom Postgres types (citext, ltree, jsonb)
- **Key APIs / patterns**: `use Ash.Resource, data_layer: AshPostgres.DataLayer`, `postgres do table "tasks"; repo MyApp.Repo end`, manual indexes via `references do …`, custom indexes via the `postgres do …` block, fragment expressions in calculations
- **Integration points with other Watershed libraries**: Sits between `ash` and `ecto`/`:postgrex`. Phoenix.Sync (Electric) reads the same Postgres WAL; AshPostgres's table definitions are what Electric replicates from
- **Known gotchas / limitations**:
  - Migrations are generated, not hand-written — review the diff every time. A schema field rename without an explicit hint can become drop+add (data loss)
  - The `mix ash_postgres.generate_migrations` step needs to run on the developer machine; CI-generated migrations get awkward when multiple developers race
  - Custom SQL via `fragment(...)` is the escape hatch; works but doesn't compose with Ash filtering across the boundary
- **What we'd need to verify**: That AshPostgres tables play nicely with Electric replication publications — Electric requires logical replication and tables with primary keys (Ash gives us PKs for free, but verify the `REPLICA IDENTITY` setting)
- **Alternatives considered**: Plain Ecto (loses Ash integration); ETS/Mnesia data layers exist but don't give us persistence

### `ash_authentication` — auth strategies (magic-link, OAuth2, OIDC, passkeys)

- **Current Hex version**: `~> 4.13` stable; `5.0.0-rc.9` available ([hex.pm/packages/ash_authentication](https://hex.pm/packages/ash_authentication))
- **Maintenance status**: green — 4.13.7 released January 13, 2026; active 5.0 release-candidate line
- **License**: MIT
- **What we use it for**: All identity surface. Magic-link strategy for passwordless signin; OAuth2 strategy configured against WorkOS endpoints for SSO. Replaces broker's bespoke TS auth (DECISIONS §2.11). Author signing keys + sessions are Ash resources extended with auth
- **Key APIs / patterns**: `AshAuthentication.Strategy.MagicLink`, `AshAuthentication.Strategy.OAuth2`, `AshAuthentication.Strategy.Oidc`, `authentication do strategies do …`. Token resource for refresh/revocation. `AshAuthentication.Phoenix.Plug` for current-user assignment
- **Integration points with other Watershed libraries**: Extends an Ash `User` resource; Phoenix integration lives in `ash_authentication_phoenix`; Oban handles deferred sends (magic-link email)
- **Known gotchas / limitations**:
  - The OIDC strategy builds on top of OAuth2 + `assent`. For WorkOS, configuring `openid_configuration_uri`, `client_id`, `client_secret`, `id_token_signed_response_alg`, and `id_token_ttl_seconds` is required
  - WorkOS is **not in the pre-built strategy list** (Apple, Auth0, GitHub, Google, OIDC, Slack are). We use the generic OIDC strategy pointing at WorkOS's discovery document. This is supported but not documented as a turnkey provider — verify the redirect URI + JWKS rotation behavior in Phase 1
  - 5.0 is in rc; the 4.x line is what we'd start on. Plan a 5.0 bump when stable
  - Magic-link tokens need a delivery side-car (email/SMS) — `ash_authentication` defines the strategy but you wire up Swoosh/Bamboo/whatever email transport
- **What we'd need to verify**: That WorkOS's OIDC discovery document (`/.well-known/openid-configuration`) is fully consumable by the AshAuthentication OIDC strategy without bespoke patches. Confirm session cookie compatibility with the existing broker session contract (so we can shadow-cutover, per broker-fly-migration.md Phase 1)
- **Alternatives considered**: `pow` (older, less Ash-native); `ueberauth` + custom resource code (more wiring); rolling our own (DECISIONS §2.12 explicitly rejects)

### `ash_authentication_phoenix` — Phoenix integration for AshAuthentication

- **Current Hex version**: `~> 2.16` stable; `3.0.0-rc.6` available ([hex.pm/packages/ash_authentication_phoenix](https://hex.pm/packages/ash_authentication_phoenix))
- **Maintenance status**: green — 2.16.0 released April 7, 2026; release cadence aligned with `ash_authentication`
- **License**: MIT
- **What we use it for**: Auth routes (`/sign-in`, `/sign-out`, `/auth/:strategy/callback`), the `ash_authentication_live_session` macro for LiveView auth, generated sign-in UI for the magic-link + WorkOS flows on the admin/operator surface
- **Key APIs / patterns**: `use AshAuthentication.Phoenix.Router`, `sign_in_route`, `sign_out_route`, `auth_routes`, `AshAuthentication.Phoenix.Components.SignIn`, `:load_from_session` plug
- **Integration points with other Watershed libraries**: Requires `ash_authentication` (mandatory peer); requires `phoenix` and `phoenix_live_view`; the generated sign-in UI is LiveView-based
- **Known gotchas / limitations**:
  - Default sign-in UI is opinionated. We probably want a Watershed-branded login for `workbooks.sh`. Easy to override but you're then writing LiveView, not just config
  - 3.0 rc tracks `ash_authentication` 5.0; pair upgrades
  - LiveView session integration assumes Phoenix.Token-style cookies. If we ever serve auth across origins (`file://` workbooks), session-cookie auth doesn't apply there — we hand out bearer tokens to the workbook artifact and verify those through the broker layer, not through the LiveView session
- **What we'd need to verify**: That the generated callback route handles WorkOS's `state` + `nonce` semantics correctly under the OIDC strategy
- **Alternatives considered**: Hand-writing the auth routes — possible but undoes the "use libraries" decision

### `ash_admin` — admin UI for Ash resources

- **Current Hex version**: `~> 1.1` ([hex.pm/packages/ash_admin](https://hex.pm/packages/ash_admin))
- **Maintenance status**: green — 1.1.0 released April 13, 2026; same `ash-project` team
- **License**: MIT
- **What we use it for**: The `/admin` console for operators — browse Workbooks, Users, Agents, AuditEntries; run actions like "revoke session" or "rotate signing key" through the Ash action UI. Replaces the broker's bespoke `/v1/admin/*` routes (DECISIONS §2.11)
- **Key APIs / patterns**: `forward "/admin", AshAdmin.Router` (mounted under an auth-gated scope), `admin do show? true end` per resource, action UIs auto-generated from Ash action definitions
- **Integration points with other Watershed libraries**: Composes with `phoenix_live_dashboard` and `oban_web` to form the full operator console (PLAN §6). Mount all three under `/admin/*` behind the same operator-role policy
- **Known gotchas / limitations**:
  - Generated UI is functional, not pretty. Fine for operator-only; do not put recipient-facing flows behind it
  - Every resource you mark `show? true` becomes visible — review carefully so you don't expose internals
  - Heavy actions still execute synchronously through LiveView. Long-running actions should enqueue Oban jobs, not run inline
- **What we'd need to verify**: That `ash_admin` 1.1 plays nicely with Ash 3.26's resource definitions for our specific actions; that auth-gating via `ash_authentication_phoenix` covers admin routes the same way it covers app routes
- **Alternatives considered**: `kaffy` (Phoenix admin, not Ash-aware); `torch` (Ecto-only); roll-our-own (DECISIONS §2.12 explicitly rejects building bespoke admin)

### `ash_json_api` — JSON:API shape generation

- **Current Hex version**: `~> 1.6` ([hex.pm/packages/ash_json_api](https://hex.pm/packages/ash_json_api))
- **Maintenance status**: green — 1.6.6 released May 21, 2026; active
- **License**: MIT
- **What we use it for**: Preserves the broker's URL contract (PLAN §11). The legacy broker exposes ~dozens of REST endpoints; rebuilding them as Ash JSON:API endpoints (with thin Phoenix wrapper routes where the legacy URL shape differs from JSON:API conventions) keeps the workbook CLI's HTTP calls working through cutover
- **Key APIs / patterns**: `use AshJsonApi.Resource`, `json_api do type "workbook"; routes do …`, mounted via `AshJsonApi.Router.forward`, content-negotiation through `application/vnd.api+json`
- **Integration points with other Watershed libraries**: Sits in front of `ash` + Phoenix router; respects `ash_authentication`'s current-user assignment; works alongside `phoenix_sync` (one library handles request/response, the other handles streaming shapes)
- **Known gotchas / limitations**:
  - JSON:API spec is opinionated about resource identifiers, sparse fieldsets, includes. The legacy broker routes do not follow JSON:API conventions — expect to keep a layer of thin Phoenix routes that hand-shape responses to match the legacy URL/body contract during shadow-write phases
  - Filter syntax in JSON:API queries is verbose. For complex queries, prefer custom Phoenix routes calling Ash actions directly
- **What we'd need to verify**: That generated route paths can be customized enough to mirror the broker's URL structure without sprinkling alias routes everywhere
- **Alternatives considered**: Hand-rolled JSON controllers (fine for two routes, painful for forty); `absinthe` GraphQL (different shape than what the workbook CLI sends today)

### `phoenix` — the web framework

- **Current Hex version**: `~> 1.8` ([hex.pm/packages/phoenix](https://hex.pm/packages/phoenix))
- **Maintenance status**: green — 1.8.7 released May 6, 2026; maintained by Chris McCord, Jose Valim, Steffen Deusch
- **License**: MIT
- **What we use it for**: HTTP + WebSocket frontend for everything. Hosts Ash resources via controllers, mounts `ash_json_api`, mounts `phoenix_sync` shape routes, mounts the admin LiveView under `/admin`
- **Key APIs / patterns**: `Phoenix.Router`, `Phoenix.Controller`, `Phoenix.Endpoint`, `Plug.Conn`, `Phoenix.Token` for stateless tokens. Bandit (default since 1.7) or Cowboy as adapter
- **Integration points with other Watershed libraries**: Foundation under everything. LiveView, LiveDashboard, AshAdmin, ObanWeb all mount via Phoenix.Router. PubSub adapter is configured through Endpoint
- **Known gotchas / limitations**:
  - We default to Bandit unless something explicitly requires Cowboy (Cowboy has slightly more mature WebSocket edge-case handling but Bandit's gap is closed for our needs)
  - `Plug.Telemetry` must be active in the endpoint pipeline for `opentelemetry_phoenix` to attach
  - File uploads via `Plug.Upload` are tempfile-based; for streaming uploads (blob storage) use Phoenix's chunked transfer mode with explicit stream handling
- **What we'd need to verify**: Nothing fundamental
- **Alternatives considered**: None — Phoenix is the BEAM web framework

### `phoenix_live_view` — interactive server-rendered UI

- **Current Hex version**: `~> 1.1` ([hex.pm/packages/phoenix_live_view](https://hex.pm/packages/phoenix_live_view))
- **Maintenance status**: green — 1.1.30 released May 5, 2026; Chris McCord + Steffen Deusch + Jose Valim
- **License**: MIT
- **What we use it for**: Powers the entire `/admin` operator console. `ash_admin`, `phoenix_live_dashboard`, `oban_web` are all LiveView-based. Watershed itself does NOT use LiveView for user-facing workbook UI — that stays Svelte 5 inside the .html artifact (PLAN §1)
- **Key APIs / patterns**: `use Phoenix.LiveView`, `handle_event/3`, `mount/3`, `~H` HEEx templates, `live_render/2`, `live_session/3`, streams + LiveStream API
- **Integration points with other Watershed libraries**: All three admin-surface libraries live here; auth lives in `ash_authentication_phoenix`'s `ash_authentication_live_session` macro
- **Known gotchas / limitations**:
  - LiveView 1.0 was a coordinated cut from 0.20.x — anything older than 1.0 docs is suspect
  - WebSocket reconnection state can be subtle; rely on `Phoenix.PubSub` for cross-process notifications, not on assumed-stable LV state
  - Streams (instead of `@items` lists) are the recommended pattern for any non-trivial collection — older blog posts still teach the lists pattern
- **What we'd need to verify**: Nothing fundamental
- **Alternatives considered**: Server-rendered + htmx (would have to rebuild every Ash admin / Oban Web / LiveDashboard surface manually); SPA admin (much more work for an operator-only console)

### `phoenix_live_dashboard` — runtime / telemetry dashboard

- **Current Hex version**: `~> 0.8` ([hex.pm/packages/phoenix_live_dashboard](https://hex.pm/packages/phoenix_live_dashboard))
- **Maintenance status**: **yellow** — 0.8.7 released April 28, 2025; cadence has slowed (no 2025/2026 release for over a year as of doc date); pre-1.0 forever
- **License**: MIT
- **What we use it for**: Operator visibility — process tree, ETS tables, telemetry metrics, request log, network ports, applications, BEAM VM stats. Mounted at `/admin/dashboard` behind operator auth
- **Key APIs / patterns**: `live_dashboard "/dashboard", metrics: MyApp.Telemetry`, `Phoenix.LiveDashboard.PageBuilder` for custom pages, `:telemetry_metrics` for declaring metrics
- **Integration points with other Watershed libraries**: Consumes `:telemetry` events; LiveView under the hood; pairs with `opentelemetry_phoenix` (LiveDashboard for local introspection, OTel for production tracing pipeline)
- **Known gotchas / limitations**:
  - Pre-1.0 since 2020. No reason to think it's abandoned (last release April 2025, ownership changes Feb 2025) but cadence is slow. Treat as load-bearing-but-static
  - Metrics tab requires you to define a `MyApp.Telemetry` module with `:telemetry_metrics` declarations. Default Phoenix scaffolds include this; verify Watershed's scaffold does too
  - The request log tab in production needs `:logger` configured to route through `Phoenix.LiveDashboard.RequestLogger` — easy to miss in non-dev envs
- **What we'd need to verify**: That the dashboard works at all when mounted behind `ash_authentication_phoenix`-style session auth (it does, but the route scope wiring is the bit to get right)
- **Alternatives considered**: External APM only (Datadog, Honeycomb) — fine for production tracing but doesn't give you the same in-product process-tree introspection. We use both: LiveDashboard for in-app, OTel for off-box

### `phoenix_sync` — Electric integration for reactive shapes

- **Current Hex version**: `~> 0.6` ([hex.pm/packages/phoenix_sync](https://hex.pm/packages/phoenix_sync))
- **Maintenance status**: **yellow** — 0.6.1 released October 13, 2025; **beta status** per the README; maintained by Electric SQL team alongside `electric` itself (which is 1.0 as of March 2025)
- **License**: Apache-2.0
- **What we use it for**: The reactive surface. Reactive Lua functions (classified `:reactive` per PLAN §4) are translated into Electric shape subscriptions through Phoenix.Sync. Client receives initial snapshot + WAL-driven incremental updates over HTTP/WebSocket
- **Key APIs / patterns**: `Phoenix.Sync.Router` (mounts shape routes), `Phoenix.Sync.Client` for server-side subscriptions, `Phoenix.Sync.Writer` for batched optimistic-write reconciliation, `:embedded` vs `:http` modes (embedded includes Electric as a dep; HTTP consumes an external Electric instance)
- **Integration points with other Watershed libraries**: Reads from the same Postgres that `ash_postgres` writes to. **Requires Postgres logical replication enabled** and tables with primary keys (Ash gives us these). Tables typically need `REPLICA IDENTITY FULL` for arbitrary `WHERE` filters
- **Known gotchas / limitations**:
  - **Query support is limited to `where` conditions.** Joins, `order_by`, `limit`, preloads are roadmapped but not in 0.6. Reactive shape design has to live within this limit — denormalize, or accept that the Lua function whose classification escapes a single-table where will be rejected by the classifier (PLAN §4)
  - Beta status — API may break before 1.0. Phoenix.Sync is a load-bearing piece of the architecture; an API break could ripple
  - Logical replication is a per-database Postgres setting (`wal_level = logical`). Fly managed Postgres supports it but it's not on by default — make this a Phase 0 task
  - Embedded mode means BEAM hosts Electric as an OTP app; HTTP mode means a separate Electric process. For the single-Phoenix-app vision (PLAN §6) we use embedded
  - The DECISIONS §2.7 "when to revisit" callout already flags this: if `phoenix_sync`'s shape semantics don't map onto our Lua reactive classifications, we'd need a custom reactivity layer
- **What we'd need to verify**: (a) every Lua-translatable reactive query fits in `WHERE`-only Electric shapes; (b) embedded mode plus Ash multitenancy plus shape filtering interact correctly — specifically, that the shape's `WHERE` includes the tenant column so cross-tenant rows never leak via Electric replication; (c) `Phoenix.Sync.Writer` matches the semantics Watershed wants for mutation reconciliation
- **Alternatives considered**: Roll our own Electric-on-Phoenix subscription layer (months of work — DECISIONS §2.7 rejects); LiveView for everything (loses the cross-origin/`file://` workbook compatibility — Phoenix.Sync's HTTP API works from any origin); raw Postgres LISTEN/NOTIFY (no snapshot semantics, no fan-out story)

### `phoenix_pubsub` — broadcast/subscribe

- **Current Hex version**: `~> 2.2` ([hex.pm/packages/phoenix_pubsub](https://hex.pm/packages/phoenix_pubsub))
- **Maintenance status**: green — 2.2.0 released October 22, 2025; 132M+ all-time downloads
- **License**: MIT
- **What we use it for**: The `pubsub.*` stdlib namespace's underlying transport. Workbook-scoped topics for cross-process broadcasts (e.g., an Oban worker finishing a job notifies subscribers). Also the LiveView/Channel substrate
- **Key APIs / patterns**: `Phoenix.PubSub.broadcast/3`, `Phoenix.PubSub.subscribe/2`, PG2 / Redis adapters; default adapter is `Phoenix.PubSub.PG2` (Erlang process groups, no external dep)
- **Integration points with other Watershed libraries**: Required by LiveView; used by Phoenix Channels; Watershed stdlib's `pubsub.broadcast` and `pubsub.subscribe` bind here
- **Known gotchas / limitations**:
  - PG2 adapter requires distributed Erlang for cross-node delivery. On Fly, that means Cluster.Strategy.LibCluster or equivalent — single-node deployments work out of the box, multi-node needs explicit clustering
  - Message ordering is per-process, not global. Don't assume FIFO across subscribers
- **What we'd need to verify**: Multi-region Fly deployment story — if Watershed scales to two regions, PubSub clustering across regions needs Postgres-LISTEN-based or Redis-based adapter; PG2 won't cross WAN cleanly
- **Alternatives considered**: Roll-our-own via Postgres LISTEN/NOTIFY (would lose LiveView integration); Redis pub/sub (added dep)

### `oban` — background jobs

- **Current Hex version**: `~> 2.22` ([hex.pm/packages/oban](https://hex.pm/packages/oban))
- **Maintenance status**: green — 2.22.1 released April 30, 2026; maintained by Parker Selbert (sorentwo); commercial Oban Pro funds the open-source line
- **License**: Apache-2.0 (open-source Oban). Oban Pro is separate, paid, optional
- **What we use it for**: All background work. Stdlib `oban.*` calls enqueue; workers can be Elixir modules or Lua handlers wrapped in a generic Elixir worker. Magic-link email send, audit-chain hashing, blob upload finalization, agent invocation retries
- **Key APIs / patterns**: `use Oban.Worker, queue: :default`, `MyWorker.new(args) |> Oban.insert/1`, `perform/1` callback, retry strategies, unique jobs, cron via `Oban.Plugins.Cron`
- **Integration points with other Watershed libraries**: Shares Postgres with `ash_postgres`; `oban_web` is the inspector; Phoenix.PubSub for job event broadcasting
- **Known gotchas / limitations**:
  - Pro features (workflows, chunks, global limits, hooks, structured args) cost money. Worth the spend at scale; not needed for v1
  - Default `queue: :default` is fine for a vertical slice but at scale you want per-concern queues with explicit concurrency limits
  - Pulse-based heartbeat for distributed cancellation can churn the `oban_peers` table; tune accordingly under load
- **What we'd need to verify**: Nothing fundamental
- **Alternatives considered**: Exq (Redis-backed — added infra); Verk (less actively maintained); raw GenServer pools (no persistence, no retries, no Oban Web)

### `oban_web` — job queue inspector UI

- **Current Hex version**: `~> 2.12` ([hex.pm/packages/oban_web](https://hex.pm/packages/oban_web))
- **Maintenance status**: green — 2.12.4 released May 11, 2026; open-sourced at 2.11 (was paid-only previously). Same maintainer as `oban`
- **License**: Apache-2.0 (since 2.11 — older versions were proprietary)
- **What we use it for**: Operator view into Oban queues. Browse jobs by state (available, executing, completed, retryable, cancelled, discarded), retry/cancel from UI, inspect args + error stacktraces. Mounted at `/admin/oban` behind operator auth
- **Key APIs / patterns**: `oban_dashboard "/oban"` mount macro; LiveView under the hood; resolver pattern for permissions (`resolver: MyApp.Resolver`)
- **Integration points with other Watershed libraries**: Reads from the same Oban table; composes with `ash_admin` and `phoenix_live_dashboard` to form the operator console
- **Known gotchas / limitations**:
  - **Was paid until 2.11.** Anything tagged "Oban Web" online from before mid-2024 is the paid-license version with different installation. Use only 2.11+ docs
  - Retry-from-UI uses Oban's normal retry path — same backoff rules apply
  - Bulk operations (cancel all retryable jobs in a queue) can issue large transactions; in big backlogs, prefer scripted cleanup
- **What we'd need to verify**: That the open-source Apache-2.0 license is what's actually shipping on the hex package (it is — confirmed via hex.pm)
- **Alternatives considered**: Bespoke LiveView (PLAN §11 + DECISIONS §2.12 explicitly reject); third-party `oban_dashboard` packages (community forks, less battle-tested)

### `luerl` — pure-Erlang Lua interpreter

- **Current Hex version**: `~> 1.5` ([hex.pm/packages/luerl](https://hex.pm/packages/luerl))
- **Maintenance status**: **yellow** — 1.5.1 released December 3, 2025; maintained primarily by Robert Virding (co-creator of Erlang); small contributor base; 16 open issues, 3 open PRs on GitHub
- **License**: Apache-2.0
- **What we use it for**: The execution substrate for **every Watershed server function**. Lua source blocks in `server/*.lua`, agent tools inside org-mode source blocks, the entire stdlib (`db.*`, `broker.*`, `oban.*`, etc.) binds into Luerl. Sandbox per call. (DECISIONS §2.3 makes this the primary execution model.)
- **Key APIs / patterns**: `:luerl.init/0`, `:luerl.do/2`, `:luerl.call_function/3`, `:luerl_new` (the newer Erlang-native API), userdata for binding Elixir values, sandboxing via the `setup_libs` callback
- **Integration points with other Watershed libraries**: Watershed's stdlib bindings call Ash, Oban, Phoenix.PubSub, Req from Erlang/Elixir code triggered by Luerl function calls. Classifier (PLAN §4) walks the parsed Lua AST that Luerl exposes
- **Known gotchas / limitations**:
  - **Implements Lua 5.3**, but the project README still notes "The migration from Lua 5.2 to 5.3 is very much Work-In-Progress." Verify the 5.3-specific features we want (integer/float subtype, bitwise ops, integer division `//`, `goto`) are stable in 1.5
  - **Performance**: Luerl is an interpreter on the BEAM. Counts of operations per second are far below `mlua`/native Lua. For Watershed's per-call workloads (10ms–1s human-driven traffic) this is fine; for tight compute loops it isn't. Out-of-scope work goes to sandbox VMs (DECISIONS §2.10, deferred from v1)
  - **Resource limits**: There's no built-in "max instructions" knob like Wasmtime's fuel. Implementing per-call wall-clock + memory caps is on Watershed (likely via a supervising process that kills the Luerl process after a deadline)
  - **Single-maintainer risk**: Robert Virding is the canonical maintainer. If the project stalls, the BEAM-Lua ecosystem has no comparable replacement. Mitigation: be prepared to vendor + patch
  - Erlang-native API (`:luerl_new`) is the recommended one; older `:luerl` API is still in the docs but the new one composes better with OTP supervision
- **What we'd need to verify**: (a) Sandbox tightness — that we can prevent Lua code from reaching arbitrary Erlang via metatable trickery; (b) the wall-clock + memory cap pattern we'll layer on top works under sustained load; (c) error messages from inside Lua bubble up cleanly enough for authors to debug their own scripts
- **Alternatives considered**: `mlua` via NIF (DECISIONS §2.3 and §2.10 explicitly reject — NIF crashes take down the BEAM scheduler); Port-driven external process (rejected — adds an IPC boundary on every call); WASM Lua in BEAM (deferred to "added when luerl interpretation is the measured bottleneck", PLAN §14)

### `ex_aws_s3` — S3-compatible client

- **Current Hex version**: `~> 2.5` ([hex.pm/packages/ex_aws_s3](https://hex.pm/packages/ex_aws_s3))
- **Maintenance status**: green — 2.5.9 released December 9, 2025; community-maintained (`ex-aws` org)
- **License**: MIT
- **What we use it for**: Blob storage operations against R2 (default) or any S3-compatible backend per env config. Put/get/delete/list of workbook artifacts and per-workbook fs.* objects (PLAN §11 / DECISIONS §2.11)
- **Key APIs / patterns**: `ExAws.S3.put_object/4`, `ExAws.S3.get_object/3`, `ExAws.S3.list_objects_v2/2`, `ExAws.request/1` or `ExAws.request!/1`. Endpoint override via `config :ex_aws, :s3, scheme:, host:, port:` — this is what enables R2/Backblaze/MinIO
- **Integration points with other Watershed libraries**: Underlies the `fs.*` stdlib namespace; uses `:hackney` or configurable HTTP client; AWS region semantics matter for signing — R2 uses `auto` region
- **Known gotchas / limitations**:
  - Mature, but the API is verbose (the operation + execute split is the ExAws idiom; flowing nicely through `|>` takes practice)
  - Multipart uploads have their own API path; for large blobs (>5GB or memory-bound streaming) use the multipart helpers, not `put_object`
  - Some R2-specific quirks: presigned URL signatures need `:virtual_host_style false` or path-style addressing depending on the bucket config — test this end to end in Phase 3
  - Hackney as the default HTTP backend is fine but conflicts with Req-based stacks if you mix HTTP clients (we'd standardize on Req everywhere except for `ex_aws_s3`'s internal calls)
- **What we'd need to verify**: That presigned-URL generation against R2 matches the URL contract the workbook CLI expects; that multipart upload semantics work for the blob sizes we actually ship
- **Alternatives considered**: `req_s3` (newer, smaller surface — see below); raw HTTP + manual SigV4 (rolling our own, rejected)

### `req_s3` — Req plugin for S3-compatible services

- **Current Hex version**: `~> 0.2` ([hex.pm/packages/req_s3](https://hex.pm/packages/req_s3))
- **Maintenance status**: **yellow** — 0.2.3 released August 16, 2024 (no release in over a year as of doc date); 42 stars, 53 commits; maintained by Wojtek Mach (Req's primary maintainer, so good provenance) but low cadence; pre-1.0
- **License**: Apache-2.0
- **What we use it for**: **Not picked as primary.** Listed here because PLAN §11 names it as the alternative. We pick `ex_aws_s3` as primary because it has wider production usage and richer API surface; `req_s3` is the lighter alternative if we want to standardize the HTTP stack entirely on Req
- **Key APIs / patterns**: `req = Req.new() |> ReqS3.attach()`, then standard Req calls with `s3://` URL scheme; supports `AWS_ENDPOINT_URL_S3` env var; URL presigning via `ReqS3.presign_url/2`
- **Integration points with other Watershed libraries**: Builds on `req`; reuses the same HTTP pool; could replace `ex_aws_s3` for a uniform Req-based HTTP stack
- **Known gotchas / limitations**:
  - Pre-1.0, minimal release cadence — feature gaps vs `ex_aws_s3` are non-trivial (multipart uploads, ACL handling, lifecycle config). For Watershed v1 needs (put/get/list/delete/presign), it has parity
  - One maintainer, slow cadence — even from a trusted source, the upgrade path is unknown
  - 0.2.3 vs the live Req at 0.5.18 — the version skew is jarring; verify compat before adopting
- **What we'd need to verify**: That basic put/get/list/delete/presign all work against R2 with our auth config; whether the maintenance gap is permanent or just slow
- **Alternatives considered**: `ex_aws_s3` (our pick). Recommendation: **start with `ex_aws_s3`**, revisit `req_s3` only if we want to simplify the HTTP stack later

### `req` — HTTP client

- **Current Hex version**: `~> 0.5` ([hex.pm/packages/req](https://hex.pm/packages/req))
- **Maintenance status**: green — 0.5.18 released May 20, 2026; maintained by Wojtek Mach (former Phoenix core team); 727 dependents
- **License**: Apache-2.0
- **What we use it for**: All outbound HTTP not going through `ex_aws_s3`. The `http.*` stdlib namespace's underlying transport. WorkOS API calls (token exchange, user lookup), webhook fan-out, arbitrary user-controlled outbound from Lua source blocks (rate-limited + audited)
- **Key APIs / patterns**: `Req.get/2`, `Req.post/2`, `Req.new/1`, retry / cache / redirect / decompression all built in. Plug-based middleware via `Req.Request.append_request_steps/2`
- **Integration points with other Watershed libraries**: `req_s3` builds on it; `:telemetry` events fire from Req for tracing; OpenTelemetry can attach via a Req step
- **Known gotchas / limitations**:
  - Pre-1.0 but extremely stable and widely adopted. API still gets incremental changes between minor releases — check the changelog
  - Finch (the underlying HTTP/2 pool) needs explicit pool configuration for production; defaults are OK for low traffic, deliberate config required for high concurrency
  - SSE / WebSocket are not native — use Mint or `:gun` for those
- **What we'd need to verify**: Nothing fundamental
- **Alternatives considered**: `httpoison` (older, less batteries-included), `Tesla` (good but more middleware ceremony), `:hackney` directly (used by ExAws — but not what we'd write new code against)

### `:telemetry` — metric dispatch

- **Current Hex version**: `~> 1.4` ([hex.pm/packages/telemetry](https://hex.pm/packages/telemetry))
- **Maintenance status**: green — 1.4.2 released May 11, 2026; effectively de-facto stdlib; maintained by Jose Valim + Wojtek Mach + Arkadiusz Gil
- **License**: Apache-2.0
- **What we use it for**: Universal metric pipe. Every library above (Phoenix, LiveView, Ash, Ecto, Oban, Req) emits `:telemetry` events. Watershed adds events for its own surfaces (Lua call latency, classifier decisions, stdlib function timings). LiveDashboard subscribes for in-process dashboards; OpenTelemetry forwards off-box
- **Key APIs / patterns**: `:telemetry.execute/3`, `:telemetry.attach/4`, `:telemetry_metrics` for typed metric declarations, `:telemetry_poller` for periodic sampling
- **Integration points with other Watershed libraries**: Every library above and below
- **Known gotchas / limitations**:
  - Handler functions must not crash — a raising handler is automatically detached. Wrap in try/rescue if you're calling into user code
  - High-frequency events (hot loops) can have measurable overhead — be deliberate about what's emitted per request vs per batch
- **What we'd need to verify**: Nothing
- **Alternatives considered**: None — telemetry is the BEAM-standard metric dispatch layer

### `opentelemetry_phoenix` — Phoenix OTel integration

- **Current Hex version**: `~> 2.0` ([hex.pm/packages/opentelemetry_phoenix](https://hex.pm/packages/opentelemetry_phoenix))
- **Maintenance status**: **yellow** — 2.0.1 released February 21, 2025 (no release in over a year as of doc date); maintained by the `opentelemetry-beam` org; release cadence is slow but the underlying OTel spec it tracks is stable
- **License**: Apache-2.0
- **What we use it for**: Off-box tracing. Wraps every Phoenix request in an OTel span, including LiveView mount/handle_event spans (toggleable via `liveview: false`). Exports through any OTLP-compatible backend (Honeycomb, Tempo, Jaeger, Datadog)
- **Key APIs / patterns**: `OpentelemetryPhoenix.setup(adapter: :bandit)` in `application.start/2`. Requires `Plug.Telemetry` in the endpoint pipeline. Adapter must match the actual server (`:bandit` for Bandit, `:cowboy2` for Cowboy). Pair with `OpentelemetryBandit` or `OpentelemetryCowboy` for full request lifecycle coverage
- **Integration points with other Watershed libraries**: Subscribes to `:telemetry` events; pairs with OpentelemetryEcto, OpentelemetryOban, OpentelemetryReq for full-stack tracing
- **Known gotchas / limitations**:
  - **Without the matching server adapter** (Bandit or Cowboy), traces lose the outermost request span and durations are misleading. This is a common misconfiguration
  - Slow release cadence — fine because OTel semconv is stable, but if a Phoenix internal telemetry event changes, the patch may lag
  - LiveView tracing can be noisy in chatty dashboards. Disable for `/admin/dashboard` if it generates span pressure
- **What we'd need to verify**: Bandit adapter parity with Cowboy adapter for our use cases
- **Alternatives considered**: Bespoke `:telemetry` → log lines (no distributed tracing); pure metrics (no traces); commercial APM agents (Datadog, New Relic — fine but more expensive and proprietary)

### `:public_key` + `:crypto` — OTP stdlib for signing/verification

- **Current Hex version**: ships with OTP (currently OTP 27)
- **Maintenance status**: green — Erlang/OTP team
- **License**: Apache-2.0 (Erlang/OTP)
- **What we use it for**: Author-key signing + verification (per-author Ed25519 keys, per-workbook signature on artifacts), audit-log hash chaining, JWT verification for WorkOS OIDC ID tokens, anything else that needs primitive crypto. **No third-party crypto library.** OTP stdlib is enough
- **Key APIs / patterns**: `:crypto.hash/2`, `:crypto.sign/4`, `:crypto.verify/5`, `:public_key.pem_decode/1`, `:public_key.generate_key/1`, `:crypto.strong_rand_bytes/1`
- **Integration points with other Watershed libraries**: The `crypto.*` stdlib namespace binds here. `ash_authentication`'s OIDC strategy uses `:public_key` and `:crypto` internally for JWT verification; we reuse the same primitives in stdlib bindings
- **Known gotchas / limitations**:
  - APIs are crusty (positional args, atom flags). Wrap them in a small Watershed module rather than scattering raw calls
  - Ed25519 sign/verify requires `:crypto.sign(:eddsa, :none, msg, [priv, :ed25519])` and matching verify — easy to get the option list wrong; write a tested wrapper once
  - `strong_rand_bytes` is the only source of cryptographic randomness — never use `:rand` for security
- **What we'd need to verify**: That OTP 27's crypto bindings cover everything the broker's TS code does today (they will — OTP is more, not less, capable than node:crypto for our use)
- **Alternatives considered**: None — OTP stdlib is the right answer

### WorkOS — handled via `ash_authentication`'s OIDC strategy

- **No separate library needed.** WorkOS is a generic OIDC provider; the OIDC strategy in `ash_authentication` 4.13.7 (or 5.0-rc) handles WorkOS via discovery URL + client credentials. There is **no `ash_authentication_workos` package** and we don't need one
- **Configuration approach**: register an `oidc` strategy in the User resource pointing at `https://api.workos.com/sso/oidc/.well-known/openid-configuration` (or the per-org connection's OIDC endpoint, depending on whether we use AuthKit or per-connection). Client ID + secret from WorkOS dashboard go in app config. Redirect URI registered with WorkOS matches the auto-generated `/auth/oidc/callback` Phoenix route
- **What we'd need to verify**: That WorkOS's `state` and `nonce` round-trip through ash_authentication without issue (it should — both are OIDC-standard); that ID token signature verification works against WorkOS's published JWKS; that `email`/`given_name`/`family_name` claim mapping matches what we expect to write into the User resource
- **No new library risk** — risk is concentrated in `ash_authentication` itself (already accounted for above)

---

## 4. Gaps and questions

Things we either can't confirm from the web or that we'd have to build because no
listed library covers them.

### Operationally unresolved (need Phase-0 verification, not new libraries)

1. **Phoenix.Sync + Ash multitenancy interaction.** Every shape's `WHERE` clause
   must include the tenant column, or Electric will replicate cross-tenant rows
   into the shape stream. There is no library bridging "Ash multitenancy" to
   "Phoenix.Sync shape definition" today. We will likely write a small helper
   in Watershed (`Watershed.Sync.tenant_shape/2`) — small but explicit code.
2. **Luerl resource limits.** No built-in instruction counter or memory cap.
   We have to layer wall-clock + heap caps via a supervising process pattern
   (start a transient Luerl process, kill after deadline, capture result).
   This is custom code on top of `luerl`.
3. **Luerl ↔ Ash bindings.** This is the genuinely custom code per
   DECISIONS §2.12 — Watershed differentiator, not library work.
4. **WorkOS OIDC end-to-end.** Generic OIDC works in theory; verify in Phase 1
   with a shadow tenant.

### Library-shaped gaps with no obvious off-the-shelf answer

5. **Sandboxed Lua wall-clock + memory cap pattern.** No Hex package exists.
   The pattern (supervising process + `:erlang.process_info(pid, :reductions)`
   polling + `Process.exit/2`) is standard BEAM — write it once, test, ship.
6. **Email transport for magic-link.** `ash_authentication` defines the
   strategy but doesn't send. We need to pick `Swoosh` (most common,
   maintained, provider-agnostic) for the actual SMTP/API send. Add to the
   list when we commit. Not yet picked — out of scope of this doc but flagged
   as a gap to close before broker Phase 1.
7. **Lua AST walker for the classifier.** Luerl exposes the parsed AST via
   `luerl_parse` — we walk it ourselves. No library; custom code per
   PLAN §4.
8. **Distributed clustering on Fly multi-region.** PubSub PG2 is single-region.
   For multi-region we'd add `libcluster` (Hex) plus a Postgres-LISTEN or Redis
   adapter for PubSub. Not needed for v1; flagged for when traffic spans
   regions.
9. **WorkOS Directory Sync / SCIM** (if we ever do it). Not covered by
   `ash_authentication`. Would be hand-rolled against WorkOS REST API via
   `req`. Out of scope for v1.

### Doc keep-current checklist

When reviewing this doc each quarter:

- Re-pull current Hex versions on every row (versions move).
- Re-check the **yellow** rows specifically (`phoenix_live_dashboard`,
  `phoenix_sync`, `luerl`, `req_s3`, `opentelemetry_phoenix`) — if any has
  gone red, plan a replacement or fork.
- Check `ash_authentication` 5.0 status — if stable, plan the bump alongside
  `ash_authentication_phoenix` 3.0.
- Re-check `phoenix_sync` for `JOIN` / `ORDER BY` / `LIMIT` support — when it
  lands, expand the set of Lua functions the classifier can mark `:reactive`.
- Re-check `luerl` for 5.3 stabilization status and any sandboxing additions.
