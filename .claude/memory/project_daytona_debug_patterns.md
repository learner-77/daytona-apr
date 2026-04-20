---
name: Daytona debugging patterns and gotchas
description: Key debugging commands, DB queries, and known gotchas for the Daytona local dev environment
type: project
originSessionId: dd76bd2e-80e1-4860-a8eb-afa92f791e7a
---
# Daytona — Debugging Patterns

## Check System Health

```bash
# All services running?
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env ps
docker compose -f shared-infra/docker-compose.shared-infra.yaml ps

# API health
curl -s http://192.168.16.153:12000/api/health

# Runner state in DB
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT id, state, "availabilityScore", NOW()-"lastChecked" AS staleness FROM runner;'

# Snapshot state
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT name, state, "errorReason", ref FROM snapshot;'

# snapshot_runner readiness
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT "runnerId", state, "snapshotRef" FROM snapshot_runner;'

# Sandbox records
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT id, state, "errorReason", snapshot FROM sandbox ORDER BY "createdAt" DESC LIMIT 5;'

# MinIO bucket exists?
docker run --rm --network shared-infra --entrypoint sh minio/mc:latest \
  -c 'mc alias set s http://minio-shared:9000 minioadmin minioadmin && mc ls s'
```

## Fix: Snapshot stuck in error state

```bash
# Delete errored snapshot, restart API to recreate it
docker exec postgres-shared psql -U admin -d daytona -c \
  "DELETE FROM snapshot WHERE name = 'daytonaio/sandbox:0.5.0-slim';"
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env restart api
# Wait for: "Default snapshot created successfully" in logs
# Then wait 3-10 min for runner to pull image and snapshot to become active
```

## Fix: Runner UNRESPONSIVE after API restart

Wait 1–2 minutes. Runner self-recovers by re-posting to /api/runners/healthcheck. Verify with:
```bash
docker exec postgres-shared psql -U admin -d daytona -c \
  'SELECT state, NOW()-"lastChecked" FROM runner;'
# Should show: ready | < 00:01:00
```

## Fix: "New Sandbox" click does nothing (no sheet opens, no POST fired)

Root cause: PostHog feature flag `dashboard_create-sandbox` returns `undefined` for the
`docker-compose`/`local` environment. `CreateSandboxSheet.tsx:150` gates on this flag —
when `undefined`, the component returns `null` at line 321, so clicking "New Sandbox" opens
nothing and fires no API request.

Fix already applied in our fork: `?? true` fallback on line 150. If regressed, re-apply:
```ts
// apps/dashboard/src/components/Sandbox/CreateSandboxSheet.tsx:150
const createSandboxEnabled = useFeatureFlagEnabled(FeatureFlags.DASHBOARD_CREATE_SANDBOX) ?? true
```
Then rebuild and force-recreate:
```bash
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env up -d --force-recreate api
```

## API Request Logging

LOG_REQUESTS_ENABLED=true is set in docker-compose.local.yaml. Logs include full req/res JSON via pino-http. Filter useful entries:
```bash
docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs --since=3m api 2>&1 \
  | grep '"method"\|"statusCode"\|errored' \
  | grep -v "for-runner\|healthcheck\|OTLPExporter\|stack\|node_modules"
```

## Known Gotchas

1. **crypto.subtle**: Fails on http://192.168.16.153 — browser blocks Web Crypto on non-localhost HTTP. Use netsh portproxy or localhost.
2. **Runner DinD insecure registry**: docker/runner-daemon.json is mounted into runner to allow HTTP push to registry-shared:5000. "Attempting next endpoint" log line is normal — Docker tries HTTPS first, falls back to HTTP.
3. **Snapshot PULL takes time**: First cold start pulls daytonaio/sandbox:0.5.0-slim (~1GB) from Docker Hub. Can take 3–10 min. Watch runner logs.
4. **Webhook/Playground 503**: Playground feature requires SVIX_AUTH_TOKEN (paid service). Not configured for local dev. Use /dashboard/sandboxes instead.
5. **API restart invalidates session**: After `docker compose restart api`, browser session is lost. Hard refresh + re-login required.
6. **MinIO bucket**: Must exist before sandbox creation. build-and-run.sh creates it automatically now. Manual: `docker run --rm --network shared-infra --entrypoint sh minio/mc:latest -c 'mc alias set s http://minio-shared:9000 minioadmin minioadmin && mc mb s/daytona'`
7. **PostHog feature flag `dashboard_create-sandbox`**: Not enabled in PostHog for local/docker-compose environment. Returns `undefined`, which makes `CreateSandboxSheet` return `null`. Fix: `?? true` fallback in `CreateSandboxSheet.tsx:150`. Rebuild API image after changing dashboard code.
8. **OTLPExporter 404 errors in logs**: `OTLPExporterError: Not Found` spam in API logs is harmless — OTel collector HTTP path mismatch. Filter: `grep -v "OTLPExporter\|stack\|node_modules"`.

## Resolved Issues

- **Issue 17 (Sandbox creation POST not firing)**: RESOLVED — PostHog flag + `?? true` fix. See fix above.
- **Issue 13 (Snapshot error state)**: RESOLVED — DELETE from snapshot table + restart API.
- **Issue 14 (MinIO bucket missing)**: RESOLVED — automated in build-and-run.sh Step 5.
- **Issue 12 (Registry TLS error)**: RESOLVED — runner-daemon.json with insecure-registries.

## Unresolved Issues

- Playground/Svix: non-functional without SVIX_AUTH_TOKEN (external paid service).
