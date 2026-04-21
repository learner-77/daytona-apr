# Daytona Fork — Local Docker Development Troubleshooting Knowledge Base

**Environment:** Windows 11 + Docker Desktop (WSL2 NAT mode)
**WSL2 IP:** `192.168.16.153`
**Last updated:** 2026-04-19

---

## Summary Table

| # | Issue | Status |
|---|-------|--------|
| 1 | WSL2 IP not detected in build script | Resolved |
| 2 | Old ports (3500/4000) showing alongside new ports in Docker Desktop | Resolved |
| 3 | `otel-collector` container conflict on restart | Resolved |
| 4 | PostgreSQL "database daytona does not exist" | Resolved |
| 5 | `DEFAULT_SNAPSHOT` env var missing | Resolved |
| 6 | CORS error from Dex (OIDC) | Resolved |
| 7 | Wrong OIDC `redirect_uri` | Resolved |
| 8 | `crypto.subtle` only available in HTTPS | Resolved (Workaround) |
| 9 | Dex "invalid credentials" after grant access | Resolved |
| 10 | Dex password hash mismatch | Resolved |
| 11 | Dex container "Permission denied" on `/var/lib/dex/dex.db` | Resolved |
| 12 | Registry TLS error during sandbox creation | Resolved |
| 13 | Snapshot stuck in error state | Resolved |
| 14 | MinIO `daytona` bucket missing | Resolved |
| 15 | Runner marked UNRESPONSIVE after API restart | Resolved (Wait) |
| 16 | Webhook service 503 error (Playground feature) | Unresolved |
| 17 | Sandbox creation POST not made from dashboard | Resolved |
| 18 | OTLPExporter 404 errors in API logs | Known / Low Priority |
| 19 | "Refused to set unsafe header 'User-Agent'" in browser console | Resolved |
| 20 | POST /api/webhooks/.../app-portal-access → 503 on Sandboxes page | Known / Not a blocker |

---

## Issues and Solutions

---

### Issue 1 — WSL2 IP Not Detected in Build Script

**Symptom:** The build/run script showed `localhost` instead of the WSL2 IP (`192.168.16.153`) when detecting the host address.

**Root Cause:** The script relied on `/proc/version` to detect whether it was running on Linux. This file does not exist when running from Windows Git Bash (not inside WSL), so the WSL2 IP detection branch was never reached.

**Fix:** Added a Windows-host detection path that:
1. Checks `docker info | grep "OSType.*linux"` to confirm Docker is Linux-backed.
2. Runs `wsl hostname -I` to retrieve the actual WSL2 IP.

**Status:** Resolved

---

### Issue 2 — Old Ports (3500/4000) Showing Alongside New Ports in Docker Desktop

**Symptom:** Docker Desktop showed both old ports (`3500`, `4000`) and new ports (`12000`, `12050`) bound simultaneously.

**Root Cause:** Two Compose files were being stacked — a base `docker-compose.yaml` and the local override `docker-compose.local.yaml` — causing port definitions from both files to be merged.

**Fix:** Use **only** `docker/docker-compose.local.yaml`. Never combine it with a base Compose file for local development.

**Status:** Resolved

---

### Issue 3 — `otel-collector` Container Conflict on Restart

**Symptom:** Docker reported a container name conflict error for `otel-collector` when trying to bring services back up.

**Root Cause:** The previous `otel-collector` container was not removed before starting new containers.

**Fix:** Run `docker compose down -v` before restarting to remove all containers (including named ones) and volumes.

**Status:** Resolved

---

### Issue 4 — PostgreSQL "database daytona does not exist"

**Symptom:** The API failed on startup with a database connection error: `database "daytona" does not exist`.

**Root Cause:** The shared Postgres instance (`postgres-shared`) is initialized with only the default `postgres` database. The `daytona` database must be created separately; it is not part of the shared-infra Postgres init script.

**Fix:** Added a step to `build-and-run.sh` (Step 4) that creates the `daytona` database inside `postgres-shared` if it does not already exist:

```bash
docker exec postgres-shared psql -U postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname='daytona'" \
  | grep -q 1 || docker exec postgres-shared psql -U postgres -c "CREATE DATABASE daytona"
```

**Status:** Resolved

---

### Issue 5 — `DEFAULT_SNAPSHOT` Env Var Missing

**Symptom:** The API logged an error about an undefined `DEFAULT_SNAPSHOT` environment variable on startup.

**Root Cause:** The env var was not present in the local Compose file's `api` service definition.

**Fix:** Added the following to the `api` service in `docker/docker-compose.local.yaml`:

```yaml
environment:
  DEFAULT_SNAPSHOT: daytonaio/sandbox:0.5.0-slim
```

**Status:** Resolved

---

### Issue 6 — CORS Error from Dex (OIDC)

**Symptom:** The browser console showed a CORS error when the dashboard attempted to reach the Dex OIDC provider.

**Root Cause:** The `web` section of `shared-infra/dex/config.yaml` did not include an `allowedOrigins` list, so Dex rejected cross-origin requests from the dashboard.

**Fix:** Added the dashboard origin to the Dex web config:

```yaml
web:
  allowedOrigins:
    - http://192.168.16.153:12000
```

**Status:** Resolved

---

### Issue 7 — Wrong OIDC `redirect_uri`

**Symptom:** Dex rejected the login redirect with an invalid `redirect_uri` error.

**Root Cause:** The dashboard computes `redirect_uri` as `window.location.origin` (the bare origin, no path). The `redirectURIs` in `dex/config.yaml` contained a path suffix, which did not match.

**Fix:** Set `redirectURIs` in `dex/config.yaml` to bare origins (no trailing path):

```yaml
redirectURIs:
  - http://192.168.16.153:12000
  - http://localhost:12000
```

**Status:** Resolved

---

### Issue 8 — `crypto.subtle` Only Available in HTTPS (Web Crypto API Error)

**Symptom:** Browser showed: `Authentication Error: Crypto.subtle is available only in secure contexts (HTTPS)`.

**Root Cause:** The browser's Web Crypto API (`crypto.subtle`) is restricted to secure contexts — either HTTPS or `localhost`. Accessing the dashboard via the WSL2 IP on plain HTTP causes the browser to block it.

**Fix (Workaround):** Use Windows `netsh` port forwarding to expose the WSL2 service on `localhost`:

```cmd
netsh interface portproxy add v4tov4 listenport=12000 listenaddress=0.0.0.0 connectport=12000 connectaddress=192.168.16.153
```

Then access the dashboard at `http://localhost:12000`.

**Additional required changes when using this approach:**
- Update `PUBLIC_OIDC_DOMAIN` in the dashboard env to use `localhost`.
- Update the Dex issuer and `redirectURIs` to use `http://localhost:12000`.

**Status:** Resolved (Workaround — `netsh` port forwarding required on each Windows boot or set as a persistent rule)

---

### Issue 9 — Dex "Invalid Credentials" After Grant Access

**Symptom:** Login via the Dex form succeeded, but the "Grant Access" confirmation page returned "invalid credentials".

**Root Cause:** The Dex `staticClients` entry had `secret: daytona-secret` configured. The dashboard uses the PKCE flow, which is a public client flow and does not send a client secret. Dex rejected the mismatch.

**Fix:** Changed the static client in `dex/config.yaml` to a public client by removing the `secret` field and adding `public: true`:

```yaml
staticClients:
  - id: daytona-dashboard
    public: true
    name: Daytona Dashboard
    redirectURIs:
      - http://localhost:12000
```

**Status:** Resolved

---

### Issue 10 — Dex Password Hash Mismatch

**Symptom:** Logging in with `admin@local.dev` / `password` failed with invalid credentials.

**Root Cause:** The bcrypt hash stored in `dex/config.yaml` under `staticPasswords` did not correspond to the string `"password"`.

**Fix:** Generated a correct bcrypt hash using Python:

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'password', bcrypt.gensalt(10)).decode())"
```

Replace the `hash` field in `dex/config.yaml` with the generated value. One confirmed working hash:

```
$2b$10$RcuxplfEBLzGGhc5db.jz.wMF.ejphg3Wgw3j8Jwh5lp.UhOBT5am
```

**Status:** Resolved

---

### Issue 11 — Dex Container "Permission Denied" on `/var/lib/dex/dex.db`

**Symptom:** Dex container log showed: `touch: /var/lib/dex/dex.db: Permission denied`.

**Root Cause:** The Dex container image runs as a non-root user by default. The mounted volume at `/var/lib/dex` was owned by root, preventing the non-root process from writing to it.

**Fix:** Added `user: root` to the `dex` service definition in `shared-infra/docker-compose.shared-infra.yaml`:

```yaml
services:
  dex:
    user: root
```

**Status:** Resolved

---

### Issue 12 — Registry TLS Error During Sandbox Creation

**Symptom:** Sandbox creation failed with: `Get "https://registry-shared:5000/v2/": http: server gave HTTP response to HTTPS client`.

**Root Cause:** The runner uses Docker-in-Docker (DinD). The DinD daemon's `/etc/docker/daemon.json` only listed `registry:6000` as an insecure registry, not `registry-shared:5000`. Docker tried HTTPS first, failed, and the pull was blocked.

**Fix:** Created `docker/runner-daemon.json`:

```json
{
  "insecure-registries": ["registry-shared:5000", "192.168.16.153:13600"]
}
```

Mounted it into the runner service in `docker/docker-compose.local.yaml`:

```yaml
services:
  runner:
    volumes:
      - ./runner-daemon.json:/etc/docker/daemon.json:ro
```

**Note:** Docker logs an error when it tries HTTPS first and falls back to HTTP. The subsequent "Attempting next endpoint" log line is normal behavior, not a persistent failure.

**Status:** Resolved

---

### Issue 13 — Snapshot Stuck in Error State

**Symptom:** The default snapshot `daytonaio/sandbox:0.5.0-slim` showed status `error` in the DB, and all sandbox creation attempts failed.

**Root Cause:** A prior registry TLS failure (Issue 12) caused the snapshot pull to fail mid-flight, and the API recorded the snapshot record with status `error`. On subsequent API restarts, the API only creates a new snapshot record if one does not exist — so the errored record persisted indefinitely.

**Fix:**
1. Delete the errored snapshot record from the database:

   ```sql
   DELETE FROM snapshot WHERE name = 'daytonaio/sandbox:0.5.0-slim';
   ```

2. Restart the API. It will recreate the snapshot record in `pending` state and the runner will pull the image fresh.

**Status:** Resolved

---

### Issue 14 — MinIO `daytona` Bucket Missing

**Symptom:** Sandbox or storage operations would fail because the required MinIO bucket did not exist.

**Root Cause:** MinIO starts with an empty state. The `daytona` bucket is not automatically created by any init script.

**Fix:** Create the bucket using the `minio/mc` client container:

```bash
docker run --rm --network shared-infra --entrypoint sh minio/mc:latest \
  -c 'mc alias set s http://minio-shared:9000 minioadmin minioadmin && mc mb s/daytona'
```

This was also added as **Step 5** in `build-and-run.sh` so it runs automatically on each fresh setup.

**Status:** Resolved

---

### Issue 15 — Runner Marked UNRESPONSIVE After API Restart

**Symptom:** Immediately after an API restart, sandbox creation failed silently — no DB record was created for the new sandbox.

**Root Cause:** When the API restarts, the runner loses its gRPC/HTTP connection temporarily and misses one or more health-check cycles. If the runner's `lastChecked` timestamp becomes too stale (observed threshold: ~922 seconds in one case), the API marks the runner as `UNRESPONSIVE` and refuses to schedule work on it. The runner automatically re-registers, but there is a window where requests are silently dropped.

**Fix:** After restarting the API, wait 1–2 minutes before attempting sandbox creation. Verify runner state with:

```sql
SELECT state, NOW() - "lastChecked" AS staleness FROM runner;
```

The runner should show `state = 'ready'` and `staleness < 60s` before proceeding.

**Note:** No manual intervention is needed beyond waiting. The runner recovers automatically.

**Status:** Resolved (Wait required after API restart)

---

### Issue 19 — "Refused to Set Unsafe Header 'User-Agent'" in Browser Console

**Symptom:** Browser console shows `Refused to set unsafe header "User-Agent"` when dashboard makes API calls. Sandbox creation form may fail silently or API requests may not fire correctly.

**Root Cause:** `libs/api-client/src/configuration.ts:97` unconditionally sets `'User-Agent': api-client-typescript/${version}` on every request. Browsers treat `User-Agent` as a forbidden header and block any JavaScript attempt to set it (per Fetch spec).

**Fix:** Made the header conditional on environment — only set in Node.js, skip in browser:

```typescript
// libs/api-client/src/configuration.ts ~line 96
...(typeof window === 'undefined'
    ? { 'User-Agent': `api-client-typescript/${packageJson.version}` }
    : {}),
```

Rebuild API image and force-recreate container after the change.

**Status:** Resolved

---

### Issue 20 — POST /api/webhooks/.../app-portal-access → 503 on Sandboxes Page

**Symptom:** Network tab shows `POST /api/webhooks/organizations/:id/app-portal-access` returning 503 Service Unavailable when visiting `/dashboard/sandboxes`.

**Root Cause:** The `SvixProvider` component fires this call on navigation to the Webhooks route. It requires `SVIX_AUTH_TOKEN` which is not configured in local dev. The 503 is the expected response when Svix is disabled.

**Fix:** Not a blocker for sandbox creation — only affects `/dashboard/webhooks` (Playground) page. Use `/dashboard/sandboxes` for sandbox management. No fix needed unless Svix integration is required.

**Status:** Known / Not a blocker

---

### Issue 16 — Webhook Service 503 Error (Playground Feature)

**Symptom:** `POST /api/webhooks/.../app-portal-access` returned HTTP 503 with body: `Webhook service is not configured`.

**Root Cause:** Daytona's Playground feature depends on [Svix](https://www.svix.com/), a paid external webhook service. The `SVIX_AUTH_TOKEN` environment variable is not set in the local development configuration, so the webhook service is effectively disabled.

**Workaround:** Use the regular Sandboxes page (`/dashboard/sandboxes`) for all sandbox creation and management instead of the Playground page.

**Status:** Unresolved — Playground is non-functional without a Svix subscription and `SVIX_AUTH_TOKEN` configured.

---

### Issue 17 — Sandbox Creation POST Not Made from Dashboard

**Symptom:** Clicking "New Sandbox" on the dashboard resulted in no `POST /api/sandbox` request being logged by the API.

**Root Cause:** PostHog feature flag `dashboard_create-sandbox` returns `undefined` (not `true`) for the `docker-compose`/`local` environment because the flag is not enabled in Daytona's PostHog project for local dev. `CreateSandboxSheet.tsx:150` uses `useFeatureFlagEnabled(FeatureFlags.DASHBOARD_CREATE_SANDBOX)` — when `undefined`, the component returns `null` at line 321, so clicking "New Sandbox" opens nothing and fires no API request.

**Fix:** Changed line 150 in `apps/dashboard/src/components/Sandbox/CreateSandboxSheet.tsx` from `useFeatureFlagEnabled(FeatureFlags.DASHBOARD_CREATE_SANDBOX)` to `useFeatureFlagEnabled(FeatureFlags.DASHBOARD_CREATE_SANDBOX) ?? true`. Then rebuilt the API image and force-recreated the container:

```bash
docker build -t daytona-api:local-latest -f apps/api/Dockerfile . && docker compose -f docker/docker-compose.local.yaml --env-file docker/.env up -d --force-recreate api
```

**Status:** Resolved

---

### Issue 18 — OTLPExporter 404 Errors in API Logs

**Symptom:** `OTLPExporterError: Not Found` / `404 page not found` errors appear constantly in API logs.

**Root Cause:** The API sends OpenTelemetry traces to the OTel collector endpoint, but the collector's HTTP endpoint returns 404 for the specific OTLP path the exporter is using. This is a misconfiguration in the OTel collector config, not a critical error.

**Fix:** These errors are harmless noise — telemetry data is not collected but the API functions normally. Filter them out when reading logs:

```bash
| grep -v "OTLPExporter\|stack\|node_modules"
```

**Status:** Known / Low Priority

---

## System Architecture Quick Reference

### Daytona Services (local fork)

| Service | Host Port | Internal Port | Notes |
|---------|-----------|---------------|-------|
| Dashboard (frontend) | 12000 | 3000 | Access via `http://localhost:12000` (see Issue 8) |
| API | 12050 | 3986 | REST API |
| Runner | 12100 | — | Docker-in-Docker runner |
| (reserved) | 12101–12650 | — | Available for additional Daytona services |

### Shared Infrastructure Services

| Service | Host Port | Internal Port | Notes |
|---------|-----------|---------------|-------|
| Dex (OIDC) | 13000 | 5556 | OIDC provider for dashboard auth |
| PostgreSQL | 13100 | 5432 | Shared Postgres; `daytona` DB must be created manually |
| MinIO (S3) | 13200 | 9000 | Object storage; `daytona` bucket must be created |
| MinIO Console | 13201 | 9001 | Web UI for MinIO |
| Registry (shared) | 13600 | 5000 | Local Docker registry; insecure HTTP |
| Jaeger / OTEL | 13400 | 16686 | Distributed tracing UI |
| otel-collector | 13401 | 4317/4318 | OpenTelemetry collector (gRPC/HTTP) |

> **Network note:** All shared-infra containers communicate over the `shared-infra` Docker network by service name (e.g., `postgres-shared`, `minio-shared`, `registry-shared`). Daytona services join this same network and reach shared-infra by those names.

### WSL2 / Windows Networking

| Item | Value |
|------|-------|
| WSL2 IP (NAT) | `192.168.16.153` |
| Windows localhost | `127.0.0.1` |
| Port forwarding | `netsh interface portproxy add v4tov4 listenport=12000 listenaddress=0.0.0.0 connectport=12000 connectaddress=192.168.16.153` |

> **Tip:** The `netsh` portproxy rule is not persistent across Windows reboots by default. Add it to a startup script or use `netsh interface portproxy show all` to verify it is active.
