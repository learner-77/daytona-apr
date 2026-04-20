# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Memory & Project Context

**Always read these before starting any task in this repo:**

1. **Memory files** at [`.claude/memory/`](.claude/memory/) in this repo — start with [`MEMORY.md`](.claude/memory/MEMORY.md) (index), then load relevant entries. These contain architecture decisions, debugging patterns, port assignments, credentials, and session feedback. (Also mirrored to `C:\Users\admin\.claude\projects\C--tools-my-codebases-daytona-apr-fork-daytona-apr\memory\` for user-level persistence.)
2. **[docs/app-module-reference.md](docs/app-module-reference.md)** — comprehensive reference for all apps, shared libs, ports, env vars, and inter-service communication.
3. **[docs/troubleshooting-kb.md](docs/troubleshooting-kb.md)** — 17 known issues with Symptom / Root Cause / Fix / Status. Check here before debugging.
4. **[docs/flow-diagrams.md](docs/flow-diagrams.md)** — Mermaid sequence diagrams + verbose step-by-step for 7 key flows (login, sandbox creation, snapshot lifecycle, proxy/preview, SSH, runner healthcheck, startup order).
5. **[docker/docker-compose.local.yaml](docker/docker-compose.local.yaml)** and **[docker/.env](docker/.env)** — local service definitions and secrets.
6. **[build-and-run.sh](build-and-run.sh)** and **[shared-infra/start-shared-infra.sh](shared-infra/start-shared-infra.sh)** — authoritative startup scripts.

**Always update memory and docs when you discover something new** — new ports, env vars, gotchas, fixes, or architectural insights that are not obvious from reading the code. Update the relevant memory file and add/update entries in the troubleshooting-kb and flow-diagrams as appropriate.

---

## Repository Overview

Daytona is a cloud development environment platform. This is a fork with a local Docker dev setup.

**Monorepo tooling:** Nx + Yarn workspaces. All Nx targets are defined in each app's `project.json`.

### Apps (`apps/`)

| App | Language | Role |
|-----|----------|------|
| `api` | TypeScript / NestJS | Core REST API, orchestrates sandboxes, runners, snapshots |
| `dashboard` | TypeScript / React + Vite | Web UI at `/dashboard` |
| `runner` | Go + Docker-in-Docker | Executes sandbox containers; runs dockerd internally |
| `proxy` | Go | Reverse proxy for sandbox preview URLs |
| `ssh-gateway` | Go | SSH multiplexer for sandbox SSH access |
| `daemon` | Go | Agent running inside each sandbox container |
| `cli` | Go | Daytona CLI tool |
| `snapshot-manager` | Go | Manages snapshot lifecycle (build/push/tag) |
| `docs` | Astro / MDX | Public documentation site |

### Shared Libraries (`libs/`)

Generated API clients and SDKs: `api-client`, `runner-api-client`, `toolbox-api-client`, `analytics-api-client`, `sdk-typescript`, `sdk-python`.

---

## Local Development Environment

### Architecture

Two Docker Compose projects:

- **shared-infra** (ports 13000–13900) — reusable services: PostgreSQL, Redis, MinIO, Dex (OIDC), Jaeger, OTel, Prometheus, Grafana, container registry, MailDev. Network: `shared-infra`.
- **daytona** (ports 12000–12650) — Daytona app services: api, proxy, runner, ssh-gateway. Networks: `daytona-network` + joins `shared-infra`.

WSL2 IP: `192.168.16.153`. Dashboard: `http://192.168.16.153:12000/dashboard`.

### Startup

```bash
# 1. Start shared infrastructure first
bash shared-infra/start-shared-infra.sh

# 2. Build Docker images and start Daytona services
bash build-and-run.sh
```

After cold start, wait 3–10 min for runner to pull `daytonaio/sandbox:0.5.0-slim` from Docker Hub.

### Viewing logs

```bash
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs -f api
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs -f runner
```

### Stopping

```bash
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env down
bash shared-infra/start-shared-infra.sh --down
```

---

## Build Commands

### TypeScript / NestJS (api, dashboard)

```bash
# Build a single app
yarn nx build api
yarn nx build dashboard

# Run tests
yarn nx test api

# Lint
yarn lint:ts

# Build all (development)
yarn build

# Build all (production)
yarn build:production
```

### Go apps (runner, proxy, ssh-gateway, daemon, cli, snapshot-manager)

```bash
# Build
cd apps/runner && go build ./...
cd apps/proxy && go build ./...

# Test
cd apps/runner && go test ./...

# Run linter
cd apps/runner && golangci-lint run
```

### Docker images (local)

```bash
# Build individual images (from repo root)
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
docker build -t daytona-runner:local-latest -f apps/runner/Dockerfile .
docker build -t daytona-proxy:local-latest -f apps/proxy/Dockerfile .
docker build -t daytona-ssh-gateway:local-latest -f apps/ssh-gateway/Dockerfile .
```

### Database migrations (api)

```bash
yarn migration:generate        # generate migration file
yarn migration:run:pre-deploy  # run pre-deploy migrations
yarn migration:run:post-deploy # run post-deploy migrations
```

---

## Key Architecture Details

### API (NestJS)

- Entry: `apps/api/src/main.ts`
- Config: `apps/api/src/config/configuration.ts` — reads all env vars. `LOG_REQUESTS_ENABLED=true` enables pino-http request logging.
- TypeORM entities in `apps/api/src/*/entities/`. Two migration tracks: `pre-deploy` and `post-deploy`.
- Sandbox creation path: `sandbox.service.ts` → validates snapshot (must be ACTIVE), finds runner via `runner.service.ts` → `snapshot_runner` table must have `state=READY` for that snapshotRef.

### Runner (Go + DinD)

- Base image: `docker:28.2.2-dind-alpine3.22`
- Runs `dockerd` internally alongside the runner binary. The runner's Docker client talks to its own internal dockerd, not the host.
- `docker/runner-daemon.json` is volume-mounted into the runner at `/etc/docker/daemon.json` to allow HTTP push/pull to `registry-shared:5000` (insecure registry).
- Default snapshot `daytonaio/sandbox:0.5.0-slim` is pulled from Docker Hub and pushed to the internal registry during first startup.

### OIDC Authentication

- Dex runs in shared-infra at port 13300. Test user: `admin@local.dev` / `password`.
- Browser must access the app via `localhost` (not WSL2 IP) because `crypto.subtle` requires localhost or HTTPS.
- Use: `netsh interface portproxy add v4tov4 listenport=12000 listenaddress=0.0.0.0 connectport=12000 connectaddress=192.168.16.153` (not persistent — re-run after reboot).

### Playground / Webhook Features

Require `SVIX_AUTH_TOKEN` (external paid service). Not configured in local dev — use `/dashboard/sandboxes` instead of `/dashboard/playground`.

---

## Port Reference

| Service | Port |
|---------|------|
| Daytona API / Dashboard | 12000 |
| Daytona Proxy | 12050 |
| Daytona Runner | 12100 |
| Daytona SSH Gateway | 12150 |
| PostgreSQL | 13000 |
| Redis | 13050 |
| MinIO S3 API | 13100 |
| MinIO Console | 13150 |
| MailDev SMTP | 13200 |
| MailDev UI | 13250 |
| Dex OIDC | 13300 |
| Jaeger UI | 13350 |
| OTel gRPC | 13400 |
| OTel HTTP | 13450 |
| Prometheus | 13500 |
| Grafana | 13550 |
| Container Registry | 13600 |
| Registry UI | 13650 |

---

## Quick Debug Commands

```bash
# Runner and snapshot state
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT id, state, "availabilityScore", NOW()-"lastChecked" AS staleness FROM runner;'

docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT name, state, "errorReason" FROM snapshot;'

docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT "runnerId", state, "snapshotRef" FROM snapshot_runner;'

# Recent sandbox records
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT id, state, "errorReason", snapshot FROM sandbox ORDER BY "createdAt" DESC LIMIT 5;'

# Filter API logs for requests (excludes health/runner noise)
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs --since=3m api 2>&1 \
  | grep '"method"\|"statusCode"\|errored' | grep -v "for-runner\|healthcheck"
```
