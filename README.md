# Daytona — Local Dev Fork

This fork adds a fully configured local Docker development environment for Windows 11 Home with WSL2.

For the original Daytona documentation see [README_orig.md](README_orig.md).

---

## What's in this fork

| Addition | Purpose |
|----------|---------|
| `docker/docker-compose.local.yaml` | Daytona app services (api, proxy, runner, ssh-gateway) |
| `docker/.env` | Local secrets and config |
| `docker/runner-daemon.json` | DinD insecure-registry config for local container registry |
| `shared-infra/` | Reusable Docker Compose — postgres, redis, minio, dex, jaeger, otel, prometheus, grafana, registry |
| `build-and-run.sh` / `build-and-run.ps1` | One-shot build + deploy scripts |
| `CLAUDE.md` | Claude Code guidance for this repo |
| `docs/` | Architecture reference, troubleshooting KB (20 issues), flow diagrams |
| `.claude/memory/` | Claude Code session memory — architecture, debug patterns, file references |
| **Bug fixes** | PostHog feature flag gate, `User-Agent` browser header, hardcoded API base URL |

---

## Architecture

Windows + Docker Desktop with WSL2. Two Docker Compose projects that must start in order:

```
1. shared-infra  (ports 13000–13650)    2. daytona  (ports 12000–12150)
─────────────────────────────────────      ──────────────────────────────
postgres-shared      :13000                api          :12000
redis-shared         :13050                proxy        :12050
minio-shared         :13100/13150          runner       :12100  (Docker-in-Docker)
maildev-shared       :13200/13250          ssh-gateway  :12150
dex-shared (OIDC)    :13300
jaeger-shared        :13350
registry-shared      :13600
```

**Runner** is the worker that executes sandboxes. It runs its own Docker daemon internally (DinD). Sandbox containers live inside the runner — not visible in your host `docker ps`. See [Viewing sandboxes](#viewing-sandboxes).

---

## Networking on Windows 11 Home (WSL2 NAT)

Windows 11 Home uses a **NAT-based WSL2 network** — two separate IPs are in play and this matters for accessing the dashboard:

```
Windows host       127.0.0.1 / localhost
WSL2 NAT network   192.168.x.x  ← Docker containers bind here, not to localhost
```

Docker Desktop runs containers inside WSL2, so ports are bound to the **WSL2 IP**, not `localhost`:

| Access method | Dashboard loads | OIDC login works |
|---------------|----------------|-----------------|
| `http://localhost:12000` (no portproxy) | No | No |
| `http://<WSL2-IP>:12000` | **Yes** | No — `crypto.subtle` blocked on non-localhost HTTP |
| `http://localhost:12000` (with portproxy) | **Yes** | **Yes** |

**Why OIDC fails on the WSL2 IP:** The browser's `crypto.subtle` API (used for PKCE auth flow with Dex) is blocked on plain HTTP unless the origin is `localhost`. Accessing via the WSL2 IP triggers this restriction.

**Find your WSL2 IP:**
```bash
# In WSL2 terminal or Git Bash:
ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1

# Or from Windows PowerShell:
wsl hostname -I
```

**Fix — netsh portproxy** (run once per reboot, as Administrator):
```cmd
netsh interface portproxy add v4tov4 listenport=12000 listenaddress=127.0.0.1 connectport=12000 connectaddress=<WSL2-IP>
```
This forwards `localhost:12000 → <WSL2-IP>:12000`, satisfying `crypto.subtle`.

> The portproxy is **not persistent** — re-run after every Windows reboot.

---

## Quick start

### Prerequisites
- Windows 11 Home with Docker Desktop (WSL2 backend enabled)
- Git

### 1. Note your WSL2 IP
```bash
ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
```
Update `docker/.env` (`WSL2_IP=`) and `shared-infra/dex/config.yaml` if your IP differs.

### 2. Start shared infrastructure first
```bash
bash shared-infra/start-shared-infra.sh
```
Shared-infra must be running before Daytona services start — the API connects to postgres, redis, and minio at startup.

### 3. Build and run Daytona
```bash
bash build-and-run.sh
```

**Cold start:** First run pulls `daytonaio/sandbox:0.5.0-slim` (~1 GB) from Docker Hub into the runner's internal registry. This takes **3–10 min**. The sandbox won't be available until the snapshot state changes to `active`:
```bash
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT name, state FROM snapshot;'
# Wait until state = active
```

### 4. Set up portproxy for OIDC login

Run **as Administrator** in PowerShell or CMD (once per reboot):
```cmd
netsh interface portproxy add v4tov4 listenport=12000 listenaddress=127.0.0.1 connectport=<WSL2-IP>
```

### 5. Open the dashboard
```
http://localhost:12000/dashboard
```
Login: `admin@local.dev` / `password`

> If you skip portproxy, open `http://<WSL2-IP>:12000/dashboard` to see the UI — but OIDC login will fail.

### 6. Stop
```bash
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env down
bash shared-infra/start-shared-infra.sh --down
```

---

## Credentials

Replace `<WSL2-IP>` with your actual WSL2 IP from Step 1.

| Service | URL | Credentials |
|---------|-----|-------------|
| Dashboard (OIDC login) | http://localhost:12000/dashboard *(needs portproxy)* | admin@local.dev / password |
| Dashboard (view only) | http://\<WSL2-IP\>:12000/dashboard | OIDC login fails |
| PostgreSQL | \<WSL2-IP\>:13000 | admin / admin — DB: daytona |
| MinIO Console | http://\<WSL2-IP\>:13150 | minioadmin / minioadmin |
| Grafana | http://\<WSL2-IP\>:13550 | admin / admin |
| Registry UI | http://\<WSL2-IP\>:13650 | no auth |
| MailDev | http://\<WSL2-IP\>:13250 | no auth |
| Jaeger UI | http://\<WSL2-IP\>:13350 | no auth |

---

## Viewing sandboxes

Sandbox containers run **inside the runner's Docker-in-Docker** daemon — not visible on the host:

```bash
# List running sandbox containers (inside runner DinD)
docker exec <project>-runner-1 docker ps

# Check sandbox records in DB
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT id, state, snapshot, "createdAt" FROM sandbox ORDER BY "createdAt" DESC LIMIT 5;'
```

> The compose project name prefix (e.g. `daytona-fork`) is set in `docker/docker-compose.local.yaml` via `name:`.

---

## Common operational notes

**Startup order matters** — always start `shared-infra` before `build-and-run.sh`. The API fails to start if postgres or redis is unreachable.

**After `docker compose restart api`** — browser session is invalidated. Do a hard refresh (Ctrl+Shift+R) and log in again.

**After any dashboard source code change** — Vite bundles the dashboard into the API Docker image at build time. A code change requires:
```bash
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env up -d --force-recreate api
```
A simple container restart is not enough.

**Runner becomes UNRESPONSIVE after API restart** — wait 1–2 min. The runner self-recovers by re-posting its healthcheck. Verify:
```bash
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT state, NOW()-"lastChecked" AS staleness FROM runner;'
# Should show: ready | < 00:01:00
```

---

## Key logs and debugging

```bash
# API request logs (filtered — removes runner/healthcheck/OTel noise)
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs --since=5m api 2>&1 \
  | grep '"method"\|"statusCode"\|errored' \
  | grep -v "for-runner\|healthcheck\|OTLPExporter\|stack"

# Runner logs
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs -f runner

# Check runner + snapshot readiness
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT id, state, "availabilityScore", NOW()-"lastChecked" AS staleness FROM runner;'
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT name, state, "errorReason" FROM snapshot;'
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT "runnerId", state FROM snapshot_runner;'
```

See [docs/troubleshooting-kb.md](docs/troubleshooting-kb.md) for 20 known issues with root causes and fixes.

---

## Documentation

| File | Contents |
|------|----------|
| [docs/app-module-reference.md](docs/app-module-reference.md) | All services, ports, env vars, API endpoints, feature flag system |
| [docs/troubleshooting-kb.md](docs/troubleshooting-kb.md) | 20 issues — Symptom / Root Cause / Fix / Status |
| [docs/flow-diagrams.md](docs/flow-diagrams.md) | Mermaid diagrams for OIDC login, sandbox creation, snapshot lifecycle, proxy, SSH, runner healthcheck, startup order |
| [CLAUDE.md](CLAUDE.md) | Claude Code guidance — build commands, architecture, memory pointers |
| [.claude/memory/](.claude/memory/) | Claude Code session memory files |

---

## Known limitations (local dev)

| Feature | Status |
|---------|--------|
| Playground / Webhooks | Requires `SVIX_AUTH_TOKEN` (external paid service). Use `/dashboard/sandboxes` instead. |
| Multi-region | Single runner only. |
| HTTPS / TLS | HTTP only. OIDC requires `localhost` via netsh portproxy. |
| OTel traces | `OTLPExporter: Not Found` errors in API logs are harmless — telemetry path mismatch, not a functional issue. |
| Sandbox persistence | Sandbox containers live inside the runner. If the runner container restarts, all running sandboxes are lost. |
