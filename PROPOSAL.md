# Venice Inference Organizer — Proposal

**Project:** venice-inference-organizer (VIO)  
**Status:** Revision 2 — public specification  
**Repo:** https://github.com/maximusmaximus/venice-inference-organizer  
**Companion (optional):** https://github.com/maximusmaximus/venice-key-manager

This document is the public proposal. It describes VIO as a standalone service any operator can run on a single host. It does not document other machines, overlays, or sibling stacks.

---

## 1. Problem

Venice.ai publishes hundreds of models across text, image, video, TTS, ASR, music, embeddings, inpaint, and upscale. IDs ship and retire often. Venice’s own guidance is to discover at runtime:

- `GET https://api.venice.ai/api/v1/models`
- `GET https://api.venice.ai/api/v1/models/traits`

Traits only expose a few aliases (`default`, `most_intelligent`, `default_code`, …). That is not five budget lanes, and it does not remember that one agent may need a planner, a coder, an image model, and a TTS voice at once.

Apps that pin raw model IDs go stale. Operators also accumulate many Venice keys and lose track of which key belongs to which consumer.

## 2. What VIO is

VIO is a **catalog and resolve service**, not an inference proxy.

- On a schedule it pulls the live Venice catalog and traits.
- It scores each model **inside its own modality** and tags a lane.
- It elects a primary plus two fallbacks per type × lane.
- Apps and agents call VIO at startup (and when the snapshot changes) to learn the current IDs.
- They then call Venice directly with those IDs.

Default Venice base URL: `https://api.venice.ai/api/v1`.

## 3. Lanes

Lanes are per type. Cheap text is not sorted against cheap video.

| Lane | Intent |
| --- | --- |
| `extra_low` | Cheapest viable (classifiers, tight loops, low-cost image/TTS) |
| `low` | Fast daily driver |
| `medium` | Balanced / near Venice `default` |
| `high` | Specialist (code, reasoning, long context) |
| `extra_high` | Best allowed after privacy + budget filters |

Suggested defaults: new apps start at `medium`. A multi-slot agent’s coder slot starts at `high`.

Election uses public Venice fields only: type, pricing, context length, capabilities (function calling, reasoning, vision, code), privacy class (`private`, `anonymized`, `e2ee`, …), and traits aliases. Manual overrides live in a local YAML/JSON file, never in application source.

## 4. App profiles and user prefs

Layered, last write wins:

1. Platform election (VIO snapshot)
2. App profile (declared slots)
3. User global lane cap
4. Per-app prefs
5. Per-slot prefs
6. Hard pin (specific model ID)

A pin dies if Venice retires the ID. VIO serves the elected fallback and flags the pref.

Generic multi-slot example (not a named product):

```yaml
app: example-agent
slots:
  planner: { type: text, lane: medium }
  coder:   { type: text, lane: high, prefer: [function_calling, code] }
  image:   { type: image, lane: low }
  tts:     { type: tts, lane: extra_low }
```

Users change lanes or pins through the dashboard, HTTP prefs API, or MCP `vio_set_pref`.

## 5. HTTP API

Bind loopback by default (`VIO_HOST=127.0.0.1`, `VIO_PORT=8787`). Gate mutating routes with `VIO_SERVICE_TOKEN`.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | Dashboard (catalog + keys) |
| GET | `/v1/health` | Catalog age, Venice reachable, Key Manager present |
| POST | `/v1/refresh` | Force catalog pull + re-elect |
| GET | `/v1/catalog` | Tagged snapshot |
| GET | `/v1/resolve` | One slot → model id + fallbacks |
| GET | `/v1/bundle` | Every slot for an app |
| GET/PUT | `/v1/prefs/{app}` | Layered prefs |
| GET | `/v1/changelog` | Add / retire / retag since last snapshot |
| GET | `/v1/keys` | Masked inventory + bindings |
| GET | `/v1/keys/{id}` | One key, metadata only |
| POST | `/v1/keys` | Mint INFERENCE key and bind |
| PATCH | `/v1/keys/{id}` | Description, limits, expiry, binding |
| POST | `/v1/keys/{id}/cycle` | Mint replacement, rebind, optionally revoke old |
| DELETE | `/v1/keys/{id}` | Revoke + drop binding |

Resolve query: `app`, `slot` or `role`, optional `lane`, optional `type`.

Example:

```http
GET /v1/resolve?app=example-agent&slot=planner&lane=medium
```

```json
{
  "app": "example-agent",
  "slot": "planner",
  "type": "text",
  "lane": "medium",
  "model": "<venice-model-id>",
  "fallbacks": ["<id-2>", "<id-3>"],
  "privacy": "private",
  "snapshot": "2026-09-27T00:00:00Z",
  "key_status": "ok"
}
```

If VIO is down, clients should use the last cached snapshot on disk.

## 6. MCP surface

VIO is the directory plane. It is **not** a clone of `@veniceai/mcp-server` (31 Venice inference tools). Pair that official server when a host needs chat, image, video, audio, or embeddings tools.

Transports: stdio (Cursor, Claude Desktop, coding agents) and optional streamable HTTP on the same loopback port, gated by the service token.

### Tools

| Tool | Purpose |
| --- | --- |
| `vio_health` | Service + catalog age + optional Key Manager probe |
| `vio_refresh` | Force catalog pull + re-elect |
| `vio_catalog` / `vio_list_models` | Filter by type, lane, privacy, capability |
| `vio_resolve` | One slot → current model id + fallbacks |
| `vio_bundle` | All slots for an app |
| `vio_get_profile` / `vio_get_prefs` | Read layered prefs |
| `vio_set_pref` / `vio_set_prefs` | Write global / app / slot / pin |
| `vio_changelog` | Diff since a snapshot |
| `vio_list_keys` | Masked inventory + what each key is used for |
| `vio_assign_key` / `vio_bind_key` | Bind app/slot to a key id |
| `vio_update_key` | PATCH description, limits, expiry |
| `vio_cycle_key` | Mint replacement INFERENCE key, rebind, optional revoke |
| `vio_revoke_key` | Revoke and unbind |

### Resources

- `vio://catalog` — latest tagged snapshot
- `vio://elections` — primary + fallbacks per type × lane
- `vio://keys` — masked inventory + bindings (no secrets)
- `vio://profiles/{app}` — resolved prefs and slots
- `vio://changelog` — model add / retire / retag
- `vio://health` — catalog age, Key Manager present, Venice reachable

### Prompts

- `vio_pick_lane` — map a task to `extra_low` … `extra_high`
- `vio_onboard_app` — generate a multi-slot profile
- `vio_rotate_consumer` — walk an agent through rotate + rebind

Typical agent startup:

```
vio_health → vio_bundle(app) → (if key stale) vio_cycle_key → call Venice with resolved model ids
```

## 7. Keys dashboard

VIO ships a local page (`GET /`) that lists every Venice key visible on this host and **what it is used for**.

Columns:

- Description
- Last 6 characters (`last6Chars`)
- Type (`INFERENCE` / `ADMIN`)
- Category (from Key Manager if present)
- Bound consumer: `app`, `slot` (planner / coder / image / tts)
- Lane
- Current-period spend vs cap, trailing 7d
- Last used, expiry
- Status: ok / low / expired / retired / unbound / keymaster-offline
- Source badge: `key-manager` / `venice-admin` / `vio-binding-only`

Full secrets never appear in the table. Create/cycle secrets show once in a one-shot modal, then are discarded.

### 7.1 Optional Venice Key Manager (Key Master)

If [Venice Key Manager](https://github.com/maximusmaximus/venice-key-manager) is installed on **this host**, VIO uses it as the key-ops plane. Discovery, in order, all local:

1. `VIO_KEYMASTER_URL` (default `http://127.0.0.1:8660`) `GET /api/health` — expect `{ "status": "ok", "app": "venice-key-manager" }`
2. CLI `venice-key-manager` on `PATH`
3. Python module `venice_key_manager`

Timeout is short (`VIO_KEYMASTER_TIMEOUT`, default 2.5s). Miss = `keymaster_present: false`. VIO does not scan other hosts.

Auth uses `VIO_KEYMASTER_TOKEN` as `X-Access-Token` or Bearer. Token lives in env or a `0600` file, never in git.

When Key Manager is present, VIO joins its `/api/keys` inventory (categories, notes, spend) with VIO bindings. When it is absent, VIO falls back to Venice `GET /api/v1/api_keys` if `VENICE_ADMIN_KEY` is set. If neither is available, the dashboard shows bindings only and a banner explaining how to enable inventory.

VIO does not reimplement Key Manager spend charts. Its unique pane is the **consumer map**: which app/slot uses which key for which lane.

### 7.2 Binding table

Local file `data/bindings.json` (gitignored). Metadata only — no secrets:

```json
{
  "app": "example-agent",
  "slot": "planner",
  "lane": "medium",
  "key_id": "<venice-key-uuid>",
  "last6": "2V2jNW",
  "category": "Agents",
  "updated_at": "2026-09-27T00:00:00Z"
}
```

Secrets stay in the agent’s own secret store (or a Key Manager session).

## 8. Agents can update their keys — confirmed

Yes. An agent authenticated with `VIO_SERVICE_TOKEN` may mutate **its own bound keys**.

Allowed:

- `PATCH` description, `expiresAt`, `consumptionLimit`, `limitPeriod`
- Bind this app/slot to an existing key id after the operator stores the secret locally
- Cycle: mint a new `INFERENCE` key with the same caps/category, rebind this agent’s slots, optionally delete the old id
- Receive the new secret **once** over the authenticated channel, then persist it in the agent’s own store

Not allowed for a leaf agent:

- Mint `ADMIN` keys (explicit admin flag + admin backend only)
- Cycle or revoke another app’s key
- Read another consumer’s secret

Backend order for mutate:

1. Key Manager `/api/keys*` if present
2. Else Venice `GET/POST/PATCH/DELETE /api/v1/api_keys` using `VENICE_ADMIN_KEY`
3. Else mutate returns `503 key_ops_unavailable` while catalog/resolve stay up

Venice `PATCH /api_keys` updates metadata only; it does not reissue the secret. Real rotation is create + rebind + delete (Key Manager `cycle`).

If Venice retires a **model** id, resolve serves the fallback and flags the pref. If Venice deletes a **key** id, resolve still returns the model but marks `key_status: retired` so the agent knows to cycle and rewrite its local `VENICE_API_KEY`.

## 9. Security

- Never commit `.env`, admin keys, service tokens, Key Manager tokens, or full Venice secrets
- List views: `last6Chars` only
- Full secret: one-shot on create/cycle, then gone from VIO state
- Dashboard never echoes `VENICE_ADMIN_KEY` or `VIO_KEYMASTER_TOKEN`
- Default mint type is `INFERENCE`
- Bind `127.0.0.1` in examples and compose; do not publish the port without a token

## 10. Public-repo hygiene

This repository ships **VIO only**. Key Manager is a separate optional project.

Keep in public docs:

- Lane model, HTTP + MCP contracts, generic profile YAML
- Public Venice endpoints only
- Loopback bind examples and empty `.env.example`
- Generic slots (`planner` / `coder` / `image` / `tts`)
- Optional Key Manager discovery via env, defaulting to loopback

Do not publish:

- Hostnames, tunnels, private DNS, LAN or overlay names
- Private IPs or compose that wires other services
- Paths, users, or unit files tied to one operator box
- Other local apps as required dependencies
- Chat IDs, bot tokens, wallet addresses, live API keys

Language rule: say “an agent or app on the same host,” not a product map of other systems.

## 11. Build cut

**Phase 1**

- Text + image catalog, five lanes, HTTP resolve/bundle, JSON prefs
- MCP stdio: health, catalog, resolve, bundle, prefs
- Dashboard: elections + keys table
- Cache last snapshot to disk

**Phase 2**

- Remaining Venice types (video, tts, asr, music, embeddings, inpaint, upscale)
- Key Manager join + agent cycle/update tools
- Streamable HTTP MCP
- Changelog resource

**Phase 3**

- Richer scoring notes, optional curator review queue
- Packaged skill files for common agent runtimes

## 12. Operator checklist

1. Clone this repo. Copy `.env.example` → `.env`. Set `VENICE_API_KEY`.
2. Optional: set `VENICE_ADMIN_KEY` if you want key inventory without Key Manager.
3. Optional: run Venice Key Manager on the same host and set `VIO_KEYMASTER_URL` + `VIO_KEYMASTER_TOKEN`.
4. `vio serve` (or `docker compose up`) on loopback.
5. Point each app at `/v1/bundle` or MCP `vio_bundle` on startup.
6. Store inference secrets in the app’s own env; store only bindings in VIO.

## 13. Non-goals

- Proxying chat, image, or video through VIO
- Replacing `@veniceai/mcp-server`
- Replacing Venice Key Manager
- Multi-host service discovery
- Storing full API secrets in the dashboard database
