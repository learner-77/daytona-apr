---
name: Daytona project file reference
description: All key files created or modified in the Daytona fork — docker compose, scripts, env, markdown docs — with their purpose
type: reference
originSessionId: dd76bd2e-80e1-4860-a8eb-afa92f791e7a
---
# Daytona Fork — File Reference

All paths relative to: C:\tools\my_codebases\daytona_apr_fork\daytona-apr

## Docker / Runtime Files

| File | Purpose |
|------|---------|
| `docker/docker-compose.local.yaml` | Main compose for Daytona services (api, proxy, runner, ssh-gateway). Uses --env-file docker/.env. Joins shared-infra network. |
| `docker/.env` | Secrets and external URLs — WSL2_IP, ENCRYPTION_KEY, DB_*, S3_*, OIDC, SSH_GATEWAY_*, DASHBOARD_*, SMTP_*, POSTHOG_* |
| `docker/runner-daemon.json` | DinD daemon config mounted into runner. Adds registry-shared:5000 and 192.168.16.153:13600 as insecure registries. |
| `shared-infra/docker-compose.shared-infra.yaml` | All shared services (postgres, redis, minio, maildev, dex, jaeger, otel, prometheus, grafana, registry, registry-ui). Port range 13000–13650. |
| `shared-infra/dex/config.yaml` | Dex OIDC config — issuer, public client for daytona, bcrypt password hash for admin@local.dev/password |
| `shared-infra/otel/otel-collector-config.yaml` | OTel collector config — forwards to jaeger-shared |
| `shared-infra/prometheus/prometheus.yml` | Prometheus scrape config |
| `shared-infra/postgres/init-databases.sql` | Runs on first postgres start — creates daytona database (though build script also handles this) |
| `shared-infra/CREDENTIALS.md` | Credentials reference for all shared services |

## Scripts

| File | Purpose |
|------|---------|
| `build-and-run.sh` | Main build + deploy script. Steps: sync upstream → build 4 Docker images → verify compose file → create daytona DB in postgres-shared → create daytona bucket in MinIO → docker compose up |
| `shared-infra/start-shared-infra.sh` | Start/stop/status shared-infra. Creates Docker network if missing. Supports --down and --status flags. |

## Source Code Changes (fork-specific patches)

| File | Change | Why |
|------|--------|-----|
| `apps/dashboard/src/components/Sandbox/CreateSandboxSheet.tsx:150` | Added `?? true` fallback to `useFeatureFlagEnabled(FeatureFlags.DASHBOARD_CREATE_SANDBOX)` | PostHog flag not enabled for local/docker-compose env — without this the sheet returns null and sandbox creation is silently blocked |

## Documentation (docs/)

| File | Purpose |
|------|---------|
| `docs/app-module-reference.md` | Comprehensive reference for all apps/services (api, runner, proxy, ssh-gateway, daemon, snapshot-manager, dashboard, cli) and shared libs. Ports, packages, env vars, communication patterns. Includes /api/config schema, PostHog feature flag system, sandbox creation guard chain. |
| `docs/troubleshooting-kb.md` | Knowledge base of 18 issues encountered during setup — each with Symptom, Root Cause, Fix, Status. Summary table + system port reference. |
| `docs/flow-diagrams.md` | Mermaid sequence/flow diagrams + verbose step-by-step for 7 key flows: OIDC Login, Sandbox Creation (incl. PostHog gate), Snapshot Lifecycle, Proxy/Preview, SSH Access, Runner Health Check, Startup Order. |
| `CLAUDE.md` | Root-level guidance for Claude Code — build commands, architecture, memory section, port reference, debug commands. |

## Key Config Notes

**docker/docker-compose.local.yaml important env vars on api:**
- LOG_REQUESTS_ENABLED=true (enables pino-http request logging for debugging)
- DEFAULT_SNAPSHOT=daytonaio/sandbox:0.5.0-slim
- OIDC_ISSUER_BASE_URL=http://dex-shared:5556/dex (internal)
- PUBLIC_OIDC_DOMAIN=http://192.168.16.153:13300/dex (browser-facing)
- INTERNAL_REGISTRY_URL=http://registry-shared:5000
- TRANSIENT_REGISTRY_URL=http://registry-shared:5000
- POSTHOG_API_KEY=phc_bYtEsdMDrNLydXPD4tufkBrHKgfO2zbycM30LOowYNv
- POSTHOG_HOST=https://d18ag4dodbta3l.cloudfront.net
- POSTHOG_ENVIRONMENT=local

**runner service:**
- privileged: true (required for DinD)
- volumes: ./runner-daemon.json:/etc/docker/daemon.json:ro

**Run commands:**
```bash
# Start shared infra first
bash shared-infra/start-shared-infra.sh

# Build and run Daytona
bash build-and-run.sh

# View logs (filtered)
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs --since=3m api 2>&1 \
  | grep '"method"\|"statusCode"\|errored' | grep -v "for-runner\|healthcheck\|OTLPExporter\|stack"

# Stop
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env down
```

**After any dashboard source code change:**
```bash
# Must rebuild API image (dashboard is bundled into it) then force-recreate
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env up -d --force-recreate api
```
