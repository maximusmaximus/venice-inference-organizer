# Venice Inference Organizer (VIO)

Live [Venice.ai](https://venice.ai) model catalog, five quality/cost lanes, HTTP + MCP resolve service, and an optional keys dashboard.

VIO is a **directory**, not a proxy. Apps and agents still call `https://api.venice.ai/api/v1`. On startup they ask VIO which model IDs currently fit their slots, then use those IDs against Venice.

**Proposal:** [PROPOSAL.md](PROPOSAL.md)

## What it does

- Refresh Venice `GET /models` and `GET /models/traits` on a schedule
- Tag every model inside its own modality into `extra_low` … `extra_high`
- Elect a primary plus fallbacks per type × lane
- Resolve one slot or a whole app bundle over HTTP or MCP
- Let users pin or retarget lanes without hard-coding model IDs
- Show a keys dashboard: each key, last 6 characters, and what it is used for
- Optionally join [Venice Key Manager](https://github.com/maximusmaximus/venice-key-manager) if that tool is installed on the same host
- Let bound agents update or cycle their own inference keys

## Lanes (per modality)

| Lane | Intent |
| --- | --- |
| `extra_low` | Cheapest viable |
| `low` | Fast daily driver |
| `medium` | Balanced default |
| `high` | Specialist (code, reasoning, long context) |
| `extra_high` | Best allowed after privacy + budget |

Cheap text is never ranked against cheap video.

## Quick start

```bash
git clone https://github.com/maximusmaximus/venice-inference-organizer.git
cd venice-inference-organizer
cp .env.example .env
# set VENICE_API_KEY (inference is enough for catalog refresh)
pip install -e .
vio serve
```

Default bind is loopback (`127.0.0.1:8787`). Do not publish this port to the internet without a service token.

```bash
curl -H "Authorization: Bearer $VIO_SERVICE_TOKEN" \
  "http://127.0.0.1:8787/v1/resolve?app=example-agent&slot=planner&lane=medium"
```

## MCP

VIO exposes catalog, resolve, prefs, and key-binding tools. It does **not** reimplement the official Venice MCP (`@veniceai/mcp-server`). Pair that package if you want chat/image/video tools.

```json
{
  "mcpServers": {
    "vio": {
      "command": "python",
      "args": ["-m", "vio.mcp_server"],
      "env": {
        "VIO_SERVICE_TOKEN": "change-me",
        "VENICE_API_KEY": "your-inference-key"
      }
    }
  }
}
```

## Optional Key Manager

If [Venice Key Manager](https://github.com/maximusmaximus/venice-key-manager) is running on this host (default `http://127.0.0.1:8660`), the VIO dashboard joins its key inventory and categories with VIO consumer bindings. If it is not installed, VIO lists keys from Venice when `VENICE_ADMIN_KEY` is set.

## Security

- Never commit `.env`, live tokens, or full API secrets
- Dashboard and `GET /v1/keys` show `last6Chars` only
- Create/cycle returns a secret **once**; VIO stores `key_id` + last 6
- Leaf agents receive `INFERENCE` keys only

## License

MIT. See [LICENSE](LICENSE).
