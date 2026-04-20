# Daytona Platform — Flow Diagrams

**Local dev environment:**
- WSL2 host: `192.168.16.153`
- API: `http://192.168.16.153:12000` (internal `api:3500`)
- Proxy: `http://192.168.16.153:12050` (internal `proxy:4000`)
- Runner: `http://192.168.16.153:12100` (internal `runner:3003`)
- SSH Gateway: port `12150` (internal `2222`)
- Dex (OIDC): `http://192.168.16.153:13300/dex` (internal `dex-shared:5556`)
- PostgreSQL: `postgres-shared:5432`
- Redis: `redis-shared:6379`
- MinIO: `minio-shared:9000`
- Registry: `registry-shared:5000`

---

## Table of Contents

1. [Flow 1: OIDC Login Flow](#flow-1-oidc-login-flow)
2. [Flow 2: Sandbox Creation Flow](#flow-2-sandbox-creation-flow)
3. [Flow 3: Snapshot Lifecycle Flow](#flow-3-snapshot-lifecycle-flow)
4. [Flow 4: Sandbox Proxy / Preview Access Flow](#flow-4-sandbox-proxy--preview-access-flow)
5. [Flow 5: SSH Access to Sandbox](#flow-5-ssh-access-to-sandbox)
6. [Flow 6: Runner Health Check Loop](#flow-6-runner-health-check-loop)
7. [Flow 7: Service Startup and Initialization Order](#flow-7-service-startup-and-initialization-order)

---

## Flow 1: OIDC Login Flow

### Diagram

```mermaid
sequenceDiagram
    participant Browser
    participant Dashboard as Dashboard (api:3500/dashboard)
    participant API as API (api:3500)
    participant Dex as Dex OIDC (dex-shared:5556)

    Browser->>Dashboard: GET /dashboard
    Dashboard->>Browser: Return SPA HTML
    Browser->>Browser: Generate PKCE code_verifier + code_challenge<br/>(crypto.subtle — requires localhost or HTTPS)
    Browser->>Dex: GET /dex/auth?client_id=daytona&response_type=code<br/>&redirect_uri=http://192.168.16.153:12000<br/>&code_challenge=...&code_challenge_method=S256
    Dex->>Browser: 302 → /dex/auth/local (login page)
    Browser->>Dex: POST /dex/auth/local (email=admin@local.dev, password=password)
    Dex->>Dex: Verify bcrypt hash against staticPasswords
    Dex->>Browser: 302 → redirect_uri?code=<auth_code>&state=...
    Browser->>API: POST /api/auth/token<br/>{ code, code_verifier, redirect_uri }
    API->>Dex: POST /dex/token (code, code_verifier, client_id=daytona)<br/>(no client_secret — public client)
    Dex->>API: { access_token (JWT), id_token, refresh_token }
    API->>API: Validate JWT signature against Dex JWKS<br/>aud=daytona, iss=http://192.168.16.153:13300/dex
    API->>Browser: Set session cookie / return tokens
    Browser->>API: Subsequent requests with Authorization: Bearer <JWT>
    API->>API: Validate JWT on every request (OIDC guard)
```

### Step-by-Step Explanation

1. **Browser loads the Dashboard SPA.** The Dashboard is served by the API container itself at `http://192.168.16.153:12000/dashboard`. It is a React single-page app.

2. **PKCE challenge generation.** Before redirecting to Dex, the SPA generates a random `code_verifier` (high-entropy random string) and derives the `code_challenge` from it via SHA-256 using `crypto.subtle`. **Gotcha:** `crypto.subtle` is only available in a [secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts), meaning the browser must access the app via `https://` or `http://localhost`. If you access via `http://192.168.16.153:12000` directly, the PKCE step will throw a `crypto.subtle is undefined` error. Use `http://localhost:12000` instead, or add an SSL terminator.

3. **Authorization request to Dex.** The SPA redirects the browser to Dex's authorization endpoint with the PKCE challenge, `client_id=daytona`, and `response_type=code`. No client secret is involved because the `daytona` client is declared as `public: true` in `shared-infra/dex/config.yaml`.

4. **Dex login page.** Dex serves its own login page at `/dex/auth/local`. In local dev, `enablePasswordDB: true` enables username/password authentication using `staticPasswords`. The only pre-configured user is `admin@local.dev` / `password`.

5. **Credential verification.** Dex verifies the submitted password against the bcrypt hash stored in `config.yaml`. To add more users, generate a bcrypt hash with `htpasswd -bnBC 10 "" yourpassword | tr -d ':\n'` and add a new entry.

6. **Authorization code redirect.** Dex redirects back to the configured `redirect_uri` (either `http://192.168.16.153:12000` or `http://localhost:12000` — both are whitelisted) with a short-lived authorization `code` and the original `state` parameter.

7. **Token exchange.** The API (acting as the OAuth2 client on behalf of the SPA) sends the authorization code plus the original `code_verifier` to Dex's `/dex/token` endpoint. Because the client is public, no client secret is required — Dex verifies integrity via the PKCE mechanism.

8. **JWT issuance.** Dex returns a JWT `access_token` (and `id_token`). The JWT's `iss` claim is `http://192.168.16.153:13300/dex` and `aud` is `daytona`.

9. **API-side JWT validation.** The API validates the JWT signature against Dex's JWKS endpoint on every incoming request. The OIDC guard checks `iss`, `aud`, expiry, and signature. The API connects to Dex internally via `http://dex-shared:5556/dex` (`OIDC_ISSUER_BASE_URL` env var), but the JWT's `iss` claim uses the public URL (`PUBLIC_OIDC_DOMAIN`).

10. **Session established.** After validation, the API creates or updates the user record in PostgreSQL and returns the session to the browser. Subsequent API calls include `Authorization: Bearer <JWT>` in the header.

### Gotchas

- `crypto.subtle` requires a secure context. Always use `http://localhost:12000`, not the WSL2 IP, unless you add TLS.
- The `PUBLIC_OIDC_DOMAIN` env var in `docker-compose.local.yaml` must match the `iss` embedded in Dex JWTs (the `issuer:` field in `dex/config.yaml`). Mismatch → 401 on every request.
- Dex stores its state in a SQLite file (`/var/lib/dex/dex.db`) inside the container. This is ephemeral unless you mount a volume. Restart Dex → all sessions are invalidated.
- `allowedOrigins` in `dex/config.yaml` controls CORS for Dex's own endpoints. Ensure `http://192.168.16.153:12000` is listed if you test from the WSL2 IP.

---

## Flow 2: Sandbox Creation Flow

### Diagram

```mermaid
sequenceDiagram
    participant User
    participant Dashboard as Dashboard (SPA)
    participant PostHog as PostHog Service
    participant API as API (NestJS)
    participant DB as PostgreSQL
    participant Redis
    participant Runner as Runner (Go)
    participant DockerHub as Docker Hub
    participant Registry as registry-shared:5000

    Dashboard->>Dashboard: On page load, fetch config
    Dashboard->>API: GET /api/config (PostHog apiKey, host)
    API->>Dashboard: { PostHog config }
    Dashboard->>PostHog: Initialize PostHog JS SDK
    Dashboard->>PostHog: Evaluate feature flag via /decide<br/>(dashboard_create-sandbox)
    PostHog-->>Dashboard: flag=undefined/false → CreateSandboxSheet returns null (BLOCKED)
    PostHog-->>Dashboard: flag=true → CreateSandboxSheet renders normally
    
    Note over User,Dashboard: User clicks "New Sandbox" button

    User->>Dashboard: Click "New Sandbox"
    Dashboard->>Dashboard: CreateSandboxSheet checks useFeatureFlagEnabled()<br/>FeatureFlags.DASHBOARD_CREATE_SANDBOX
    alt Feature flag enabled
        Dashboard->>API: POST /api/sandboxes { snapshot, target, ... }
    else Feature flag disabled (no fallback)
        Dashboard->>Dashboard: Sheet returns null — button click does nothing
        Note over Dashboard: Local dev fix: ?? true fallback at CreateSandboxSheet.tsx:150
    end

    API->>API: getValidatedOrDefaultRegion(org, target)
    API->>DB: SELECT snapshot WHERE (org OR general) AND name=snapshot
    DB->>API: snapshot record
    API->>DB: SELECT snapshot_runner WHERE snapshotRef=ref AND state=READY
    DB->>API: runner IDs that have the snapshot
    API->>DB: SELECT runner WHERE id IN(runnerIds) AND state=READY<br/>AND NOT unschedulable AND NOT draining<br/>AND availabilityScore >= threshold
    DB->>API: available runners (sorted by availabilityScore DESC, top 10)
    API->>API: pick random runner from top 10
    API->>Redis: check warm-pool:skip:{snapshotId}
    Redis->>API: (cache miss — no warm pool sandbox available)
    API->>DB: INSERT sandbox (state=pending, runnerId=runner.id)
    API->>API: emit SandboxCreatedEvent (async, fire-and-forget)
    API->>User: 200 SandboxDto { id, state: "pending" }

    Note over API,Runner: Job dispatch via SandboxCreatedEvent listener

    API->>DB: INSERT job { type: CREATE_SANDBOX, resourceId: sandboxId, runnerId }
    Runner->>API: Poll GET /api/jobs?runnerId=... (every ~5s)
    API->>Runner: job { type: CREATE_SANDBOX, payload: { snapshot, registry, ... } }
    Runner->>Runner: Executor.createSandbox()
    Runner->>Runner: DockerClient.Create(ctx, sandboxDto)
    Runner->>Runner: Check existing container state
    Runner->>Registry: docker pull registry-shared:5000/daytona/<hash>:daytona
    Registry->>Runner: image layers (already cached from PULL_SNAPSHOT job)
    Runner->>Runner: docker run --privileged <image> (DinD container)
    Runner->>Runner: waitForDaemonRunning(containerIP, authToken)
    Runner->>API: POST /api/jobs/{jobId}/status { status: COMPLETED, result: { daemonVersion } }
    API->>DB: UPDATE sandbox SET state=STARTED
```

### Step-by-Step Explanation

**Step 0 (Dashboard Init): PostHog Feature Flag Gate**

- On page load, the dashboard fetches config from `GET /api/config` which includes PostHog `apiKey` and `host`.
- The dashboard initializes the PostHog JS SDK and evaluates the feature flag `dashboard_create-sandbox` via PostHog's `/decide` endpoint.
- The `CreateSandboxSheet` component checks `useFeatureFlagEnabled(FeatureFlags.DASHBOARD_CREATE_SANDBOX)`.
- If the flag returns `undefined` or `false` (e.g., not enabled in PostHog for local/docker-compose environments), the sheet component returns `null`. The "New Sandbox" button appears but clicking it does nothing.
- **Local dev fix:** `apps/dashboard/src/components/Sandbox/CreateSandboxSheet.tsx:150` uses a `?? true` fallback to default the flag to enabled when PostHog hasn't decided.

1. **API receives the creation request.** `POST /api/sandboxes` hits `SandboxController`, which calls `SandboxService.createFromSnapshot()`. The request body includes `snapshot` (name or UUID), `target` (region), resource params, env vars, labels.

2. **Region resolution.** `getValidatedOrDefaultRegion(organization, target)` validates the requested region or falls back to the `DEFAULT_REGION_ID` (`us` in local dev). Region must exist in the `region` table.

3. **Snapshot lookup.** The service queries the `snapshot` table for records matching the name/UUID where either `organizationId` matches or `general=true`. If multiple rows match, the one with `state=ACTIVE` is preferred. If none is ACTIVE, the request fails with a 400 error. The snapshot must also have a non-null `ref` field (the image reference in the registry).

4. **Regional availability check.** `snapshotService.isAvailableInRegion(snapshot.id, region.id)` queries the `snapshot_runner` table to verify at least one runner in the target region has the snapshot in `READY` state.

5. **Runner selection via `findAvailableRunners()`.** The service queries `snapshot_runner` for all runner IDs that have `snapshotRef=snapshot.ref` and `state=READY`. It then filters the `runner` table: `state=READY`, `unschedulable=false`, `draining=false`, `availabilityScore >= threshold` (default 10, from `RUNNER_AVAILABILITY_SCORE_THRESHOLD`). Results are sorted by `availabilityScore` descending and capped at 10 candidates. One is chosen at random from this list (load balancing across healthy runners).

6. **Warm pool check.** If no volumes are requested, the service checks Redis for a `warm-pool:skip:{snapshotId}` key. If absent, it tries `warmPoolService.fetchWarmPoolSandbox()` — a pre-created sandbox that can be immediately assigned. If a warm pool sandbox is found, the entire creation shortcut happens via `assignWarmPoolSandbox()` and the flow ends here.

7. **Quota validation.** `validateOrganizationQuotas()` checks CPU/memory/disk against the org's quota limits. Pending increments are tracked so they can be rolled back if a later step fails.

8. **Sandbox DB record insertion.** A `Sandbox` entity is constructed with `pending=true`, `runnerId=runner.id`, and inserted into the `sandbox` table. A `SandboxCreatedEvent` is emitted asynchronously (fire-and-forget). The API immediately returns the sandbox DTO to the caller — the sandbox is now in `pending` state.

9. **Job dispatch.** The `SandboxCreatedEvent` listener inserts a `CREATE_SANDBOX` job into the `job` table targeting the chosen runner.

10. **Runner polls for jobs.** The runner polls `GET /api/jobs` every ~5 seconds. It receives the `CREATE_SANDBOX` job with a payload containing the snapshot reference and registry credentials.

11. **Runner creates the container.** `Executor.createSandbox()` → `DockerClient.Create()`. The function first checks if the container already exists (idempotency). It pulls the image from `registry-shared:5000` (the internal registry where `PULL_SNAPSHOT` pre-staged it), then runs a privileged Docker-in-Docker container.

12. **Daemon readiness wait.** After the container starts, `waitForDaemonRunning(containerIP, authToken)` polls the container's internal daemon (port 2280) until it responds. This confirms the sandbox is fully ready.

13. **Job completion.** The runner posts `COMPLETED` to the job endpoint. The API event handler updates `sandbox.state = STARTED`.

### Key DB Tables

| Table | Role |
|---|---|
| `snapshot` | Snapshot metadata, `state`, `ref` (registry image ref), `general` flag |
| `snapshot_runner` | Junction: which runner has which snapshot (`state=READY` = image is in local registry) |
| `sandbox` | Sandbox records, `state`, `runnerId`, `pending` flag |
| `runner` | Runner records, `state`, `availabilityScore`, `unschedulable`, `draining` |
| `job` | Async job queue; polled by runners |

### Gotchas

- **PostHog feature flag blocks sandbox creation:** If the "New Sandbox" button click does nothing (no sheet opens, no API request logged), check that the PostHog feature flag `dashboard_create-sandbox` is enabled. In local dev environments, the flag is typically disabled by default. The fix is the `?? true` fallback in `apps/dashboard/src/components/Sandbox/CreateSandboxSheet.tsx:150`, which defaults the flag to enabled when PostHog hasn't decided.
- If `findAvailableRunners` returns an empty list, the API throws a 503. Root cause is almost always that `snapshot_runner.state` is not `READY` — the `PULL_SNAPSHOT` job hasn't completed yet, or completed with an error.
- The `availabilityScore` threshold (env `RUNNER_AVAILABILITY_SCORE_THRESHOLD=10`) gates runner selection. A runner that just started may have score 0 and be invisible to the scheduler until health checks raise its score.
- `pending=true` is a transient flag; if the API crashes after DB insert but before job dispatch, the sandbox is stuck `pending`. Clean up with `UPDATE sandbox SET pending=false WHERE state='pending'`.

---

## Flow 3: Snapshot Lifecycle Flow

### Diagram

```mermaid
flowchart TD
    A([API Startup\napp.service.ts onModuleInit]) --> B{Default snapshot\nalready in DB?}
    B -- Yes --> END1([Done — skip creation])
    B -- No --> C[INSERT snapshot\nstate=pending\ngeneral=true\nname=daytonaio/sandbox:0.5.0-slim]
    C --> D[API dispatches\nINSPECT_SNAPSHOT_IN_REGISTRY job\nto default runner]

    D --> E{Runner polls job queue}
    E --> F[Runner: inspectSnapshotInRegistry\nGET registry-shared:5000/v2/daytona/..../manifests/tag]

    F --> G{Image found\nin registry?}
    G -- Yes --> H[Return digest to API\nAPI updates snapshot_runner\nstate=READY\nAPI sets snapshot.state=active]
    H --> DONE([Snapshot ACTIVE\nsandboxes can be created])

    G -- No --> I[API dispatches\nPULL_SNAPSHOT job\nto runner]

    I --> J[Runner: PullSnapshot]
    J --> K[docker pull daytonaio/sandbox:0.5.0-slim\nfrom Docker Hub\nusing pull registry creds if set]
    K --> L[TagImage: daytona-<sha256hash>:daytona]
    L --> M[PushImage to\nregistry-shared:5000/daytona/\ndaytona-<hash>:daytona]
    M --> N[API updates snapshot.ref\n= registry-shared:5000/daytona/daytona-hash:daytona]
    N --> O[API creates snapshot_runner record\nstate=READY]
    O --> P[API sets snapshot.state=active]
    P --> DONE

    J --> ERR{Pull error?}
    ERR -- Docker Hub rate limit\nor network error --> Q[Job status=FAILED\nAPI sets snapshot.state=error]
    Q --> RETRY([Manual fix:\nUPDATE snapshot SET state='pending'\nthen restart API or re-dispatch job])
```

### Step-by-Step Explanation

1. **API `onModuleInit` hook.** When the API NestJS application starts, `AppService.onModuleInit()` runs. It checks whether the default snapshot (`daytonaio/sandbox:0.5.0-slim`, from `DEFAULT_SNAPSHOT` env var) already exists in the `snapshot` table for the admin organization.

2. **Snapshot record creation.** If not found, `snapshotService.createFromPull()` inserts a new snapshot record with `state=pending`, `general=true` (available to all organizations), and the image name as both `name` and `imageName`.

3. **INSPECT job dispatch.** After inserting the snapshot, the API dispatches an `INSPECT_SNAPSHOT_IN_REGISTRY` job to the default runner. This is a lightweight check: the runner calls the registry's HTTP API to see if the image already exists in `registry-shared:5000`. This matters on repeated API restarts — the image may already be cached from a previous session.

4. **Registry inspection.** The runner queries the registry manifest endpoint. If the digest response succeeds, the image is already present. The API updates `snapshot_runner.state=READY` and sets `snapshot.state=active`. The lifecycle is complete.

5. **PULL_SNAPSHOT job.** If the registry doesn't have the image, the API dispatches a `PULL_SNAPSHOT` job. The runner's `PullSnapshot()` function is called.

6. **Docker Hub pull.** `DockerClient.PullImage(ctx, "daytonaio/sandbox:0.5.0-slim", registry, nil)` performs a `docker pull` from Docker Hub. Registry credentials (for private images) are passed via the `Registry` struct in the job payload. Public images need no credentials.

7. **Tag for internal registry.** After the pull, `GetImageInfo()` retrieves the image's SHA256 digest. The image is re-tagged as `daytona-<sha256withoutprefix>:daytona`. This deterministic naming means the same image is never pushed twice.

8. **Push to internal registry.** The tagged image is pushed to `registry-shared:5000/daytona/daytona-<hash>:daytona`. The runner uses the registry credentials from its environment (admin/password, insecure HTTP allowed via `daemon.json`).

9. **API updates snapshot ref.** On job completion, the API stores the full registry reference in `snapshot.ref`. This is what the runner uses during sandbox creation to pull the image locally.

10. **snapshot_runner record.** A `snapshot_runner` row is created or updated with `runnerId`, `snapshotRef`, and `state=READY`. Multiple runners can have the same snapshot — each gets its own row.

11. **Snapshot becomes ACTIVE.** `snapshot.state` transitions to `active`. Sandbox creation calls that were waiting for the snapshot will now succeed.

### State Machine

```
pending → (INSPECT job) → active        [if already in registry]
pending → (PULL_SNAPSHOT job) → active  [if pulled from Hub and pushed to registry]
pending/pulling → error                 [if pull fails]
error → pending                         [manual DB fix to retry]
```

### Gotchas

- **Docker Hub rate limit:** Anonymous pulls are rate-limited at 100/6h per IP. In a shared NAT environment (all pulls from the same IP), this can cause `PULL_SNAPSHOT` to fail. Fix: configure Docker Hub credentials in the runner.
- **Insecure registry:** The runner must have `daemon.json` configured with `insecure-registries: ["registry-shared:5000"]` to push/pull from the HTTP-only local registry. This is mounted via `./runner-daemon.json:/etc/docker/daemon.json:ro` in `docker-compose.local.yaml`. If missing, `docker push` will fail with a TLS error.
- **Snapshot stuck in error state:** The API has no automatic retry for failed snapshots. Fix: `UPDATE snapshot SET state='pending' WHERE name='daytonaio/sandbox:0.5.0-slim';` then trigger a new job (or restart the API).
- **On API restart:** The `onModuleInit` check is idempotent — it skips creation if the snapshot already exists. However, if the snapshot is in `error` state, it also skips, leaving it broken. Manual intervention required.

---

## Flow 4: Sandbox Proxy / Preview Access Flow

### Diagram

```mermaid
sequenceDiagram
    participant Browser
    participant Proxy as Proxy (proxy:4000 / :12050)
    participant Redis as Redis (redis-shared:6379)
    participant API as API (api:3500)
    participant Runner as Runner (runner:3003)
    participant Container as Sandbox Container

    Browser->>Proxy: GET http://3000-<sandboxId>.proxy.localhost:12050/
    Proxy->>Proxy: parseHost(host)<br/>→ targetPort="3000", sandboxId="<id>"
    Proxy->>Redis: GET proxy:sandbox-public:<sandboxId>
    Redis->>Proxy: cache miss
    Proxy->>API: GET /api/preview/{sandboxId}/public
    API->>Proxy: { isPublic: false }
    Proxy->>Redis: SET proxy:sandbox-public:<sandboxId> false TTL=1h

    Note over Proxy: Sandbox is private — authentication required

    Proxy->>Proxy: Authenticate(ctx, sandboxId, port=3000)
    Proxy->>Proxy: Check request for auth cookie / X-Daytona-Preview-Token header
    alt Has valid auth token
        Proxy->>Redis: GET proxy:sandbox-auth-key-valid:<sandboxId>:<token>
        Redis->>Proxy: cache hit (valid=true)
    else No token / invalid token
        Proxy->>Browser: 302 → Dex OIDC login
        Browser->>Dex: OIDC flow (see Flow 1)
        Dex->>Browser: 302 → /callback?code=...
        Browser->>Proxy: GET /callback?code=...
        Proxy->>Dex: Exchange code for tokens
        Proxy->>API: Validate bearer token → check sandbox access
        Proxy->>Browser: Set daytona-sandbox-auth-<sandboxId> cookie
    end

    Proxy->>Redis: GET proxy:sandbox-runner-info:<sandboxId>
    Redis->>Proxy: cache miss
    Proxy->>API: GET /api/runners/by-sandbox/{sandboxId}
    API->>Proxy: { proxyUrl: "http://runner:3003", apiKey: "..." }
    Proxy->>Redis: SET proxy:sandbox-runner-info:<sandboxId> TTL=2min

    Proxy->>Runner: GET http://runner:3003/sandboxes/<sandboxId>/toolbox/proxy/3000/
    Note over Proxy,Runner: Adds X-Daytona-Authorization: Bearer <runnerApiKey>
    Runner->>Container: Forward to container 127.0.0.1:3000
    Container->>Runner: Response
    Runner->>Proxy: Response
    Proxy->>Browser: Response
```

### Step-by-Step Explanation

1. **Browser sends request with structured hostname.** The preview URL format is `http://<PORT>-<sandboxId>.proxy.localhost:12050`. The proxy's `parseHost()` function splits on the first `-` in the subdomain: `targetPort = "3000"`, `sandboxIdOrSignedToken = "<sandboxId>"`. The base domain (`proxy.localhost:12050`) is extracted but not used for routing.

2. **Public/private check.** The proxy checks its Redis cache (`proxy:sandbox-public:<sandboxId>`). On cache miss, it calls the API's preview endpoint. Public sandboxes skip authentication entirely. Private sandboxes (the default) proceed to the auth step.

3. **Authentication.** For private sandboxes, the proxy checks for a `daytona-sandbox-auth-<sandboxId>` signed cookie or an `X-Daytona-Preview-Token` header or a `DAYTONA_SANDBOX_AUTH_KEY` query parameter. The token is validated against the API (cached in Redis for 2 minutes if valid, 5 seconds if invalid). Terminal port (22222), toolbox port (2280), and recording dashboard port (33333) always require authentication even for public sandboxes.

4. **OIDC redirect for unauthenticated browsers.** If no valid token exists, the proxy initiates its own OIDC flow, redirecting the browser to Dex. After the callback, it validates the returned bearer token against the API (checking sandbox membership/access), then sets a signed cookie using `securecookie` keyed by `PROXY_API_KEY`.

5. **Runner info lookup.** Once authenticated, the proxy looks up which runner is hosting the sandbox. Redis caches this for 2 minutes (`proxy:sandbox-runner-info:<sandboxId>`). On miss, it calls `GET /api/runners/by-sandbox/{sandboxId}` which returns the runner's `proxyUrl` and `apiKey`.

6. **Forwarding to the runner.** The proxy builds the target URL: `http://runner:3003/sandboxes/<sandboxId>/toolbox/proxy/<port><path>`. It adds `X-Daytona-Authorization: Bearer <runnerApiKey>` and `X-Forwarded-Host` headers, then forwards the request transparently (including WebSocket upgrades).

7. **Runner to container.** The runner receives the request and forwards it to the sandbox container's internal IP on the requested port. The container runs a port proxy inside DinD that routes to the actual process.

8. **Last-activity update.** On each proxied request, `updateLastActivity()` is called asynchronously. It updates the sandbox's `lastActivity` timestamp in the API (rate-limited to once per 45 seconds via Redis cache), which prevents the sandbox from being auto-stopped.

### URL Pattern

```
PROXY_TEMPLATE_URL = http://{{PORT}}-{{sandboxId}}.proxy.localhost:12050
```

To access port 8080 of sandbox `abc123`:
```
http://8080-abc123.proxy.localhost:12050/
```

### Gotchas

- **`proxy.localhost` DNS resolution:** On most systems, `*.localhost` does not resolve as wildcard. Use `/etc/hosts` or a local DNS resolver (e.g., `dnsmasq`) to resolve `*.proxy.localhost` to `127.0.0.1`. Without this, the browser can't reach the proxy at all.
- **Cookie domain scoping:** The proxy sets cookies with a domain derived from the request host. If the cookie domain doesn't match the subdomain pattern, browsers reject the cookie, causing an authentication loop.
- **Cache invalidation:** Runner info is cached for 2 minutes. If a sandbox is migrated to a different runner (unusual but possible), requests may route to the wrong runner until the cache expires.
- **WebSocket support:** The proxy transparently handles WebSocket upgrades. The `ConnectionMonitor` wrapper ensures that `stopActivityPoll` is called when the WebSocket connection closes, preventing goroutine leaks.

---

## Flow 5: SSH Access to Sandbox

### Diagram

```mermaid
sequenceDiagram
    participant User as User Terminal
    participant Gateway as SSH Gateway (:12150 / internal :2222)
    participant API as API (api:3500)
    participant Runner as Runner (runner:3003)
    participant Container as Sandbox Container

    User->>Gateway: ssh -p 12150 <sandboxAuthToken>@192.168.16.153
    Note over Gateway: Username field = sandbox auth token
    Gateway->>Gateway: Extract auth token from SSH username
    Gateway->>API: GET /api/sandboxes/by-auth-token/{token}
    Note over Gateway,API: Request uses SSH_GATEWAY_API_KEY header
    API->>API: Look up sandbox by authToken\n(cached in TypeORM 10s)
    API->>Gateway: { sandboxId, runnerId, state, ... }
    Gateway->>Gateway: Verify sandbox state == STARTED
    Gateway->>Runner: GET http://runner:3003/sandboxes/{sandboxId}/runner-info
    Runner->>Gateway: { containerIP, sshPort: 22 }
    Gateway->>Container: TCP tunnel → containerIP:22
    Note over Gateway,Container: SSH session tunneled transparently
    User->>Container: Interactive SSH session established
```

### Step-by-Step Explanation

1. **User initiates SSH.** The user runs `ssh -p 12150 <token>@192.168.16.153` where `<token>` is the sandbox's auth token (a UUID-like string generated at sandbox creation time, stored in `sandbox.authToken`). The SSH username field carries the token — not an actual OS username.

2. **SSH Gateway intercepts.** The SSH Gateway listens on port 2222 internally (mapped to 12150 externally). It implements a custom SSH server. When a connection arrives, it extracts the "username" field, treating it as the sandbox auth token.

3. **Token validation against the API.** The gateway calls the API endpoint `GET /api/sandboxes/by-auth-token/{token}`. This request is authorized using the `SSH_GATEWAY_API_KEY`, which the API's `api-key.strategy.ts` validates and returns a `{ role: 'ssh-gateway' }` auth context. The API looks up the sandbox in PostgreSQL (with a 10-second TypeORM query cache).

4. **State check.** The gateway verifies that the sandbox is in `STARTED` state. Attempts to SSH into a stopped, pending, or errored sandbox are rejected at this step.

5. **Runner info lookup.** The gateway asks the runner for the container's network details — specifically the container IP address and SSH port (22 inside the DinD network).

6. **Tunnel establishment.** The gateway establishes a TCP tunnel from the SSH connection to `containerIP:22`. The inner container runs a standard `sshd`. The SSH host key presented to the user is the container's key (configured during `docker run`).

7. **Interactive session.** The user's terminal connects transparently to the sandbox container. From this point, all SSH traffic (including SCP, port forwarding, etc.) flows through the tunnel.

### Gotchas

- **Auth token vs. password:** The SSH Gateway uses the auth token as the SSH *username*, not the password. Most SSH clients default to using the local username. Always specify `<token>@<host>` explicitly.
- **Host key warnings:** Each new sandbox has a different SSH host key. Add `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null` to your SSH config for dev to avoid repeated "host key changed" warnings.
- **Container SSH daemon:** The sandbox container must have `sshd` running and configured to accept the sandbox's public key. The `SSH_PUBLIC_KEY` env var on the runner is injected into containers at creation time.
- **SSH Gateway → API connectivity:** The gateway connects to `http://api:3500/api` (configured via `API_URL` env var). If the API is unrestarted and the sandbox record is stale, token lookup may return 404.

---

## Flow 6: Runner Health Check Loop

### Diagram

```mermaid
sequenceDiagram
    participant Runner as Runner (Go)
    participant API as API (NestJS)
    participant DB as PostgreSQL

    loop Every ~10 seconds
        Runner->>API: POST /api/runners/{runnerId}/healthcheck<br/>{ services: [...], metrics: { cpu, mem, disk } }
        API->>API: RunnerService.handleHealthcheck(runnerId, data)
        API->>DB: UPDATE runner SET<br/>state=READY, lastChecked=now()<br/>availabilityScore=computed
        API->>Runner: 200 OK
    end

    Note over API: Background health monitor runs periodically

    loop API background health monitor (every ~30s)
        API->>DB: SELECT runner WHERE state != DECOMMISSIONED<br/>ORDER BY lastChecked ASC NULLS FIRST
        loop For each v2 runner
            API->>API: checkRunnerV2Health(runner)
            alt lastChecked within 60 seconds
                API->>API: Runner is healthy — no action
            else lastChecked > 60 seconds ago
                API->>DB: UPDATE runner SET state=UNRESPONSIVE
                API->>API: emit RunnerStateUpdatedEvent
            end
        end
    end

    Note over Runner,API: Runner reconnects after network blip

    Runner->>API: POST /api/runners/{runnerId}/healthcheck (resumed)
    API->>DB: UPDATE runner SET state=READY, lastChecked=now()
    API->>API: emit RunnerStateUpdatedEvent (UNRESPONSIVE → READY)
```

### Step-by-Step Explanation

1. **Runner health report.** The runner (Go process) sends a `POST /api/runners/{runnerId}/healthcheck` request every ~10 seconds. The payload includes a list of service health statuses and system metrics (CPU, memory, disk).

2. **API updates runner state.** `RunnerService.handleHealthcheck()` receives the report. If all services are healthy, `runner.state` is set to `READY` and `runner.lastChecked` is updated to `now()`. The `availabilityScore` is recomputed from the reported metrics.

3. **Unhealthy service handling.** If any service in the payload reports `unhealthy`, the runner's state is set to `UNRESPONSIVE` despite the check-in. The unhealthy services are logged with their `errorReason`.

4. **API-side staleness monitor.** Separately, a background cron task on the API queries all non-decommissioned runners ordered by `lastChecked ASC` (oldest first). For v2 runners (`apiVersion='2'`), the API does not actively poll the runner — it only checks the `lastChecked` timestamp.

5. **Stale threshold.** The health check threshold is 60 seconds (6 missed healthchecks at ~10s each). If `now() - runner.lastChecked > 60s`, the runner is marked `UNRESPONSIVE`.

6. **Grace period on API restart.** If `runner.lastChecked < apiServiceStartTime`, the runner gets a grace period equal to `max(60s, timeSinceApiStart)`. This prevents all runners from being marked unresponsive immediately after an API restart before runners have had a chance to check in.

7. **Automatic recovery.** When the runner reconnects and sends a healthcheck, `handleHealthcheck()` unconditionally sets `state=READY` and updates `lastChecked`. The `RunnerStateUpdatedEvent` is emitted, which may trigger re-scheduling of pending jobs assigned to that runner.

8. **Availability score.** The `availabilityScore` (0–100) is used by `findAvailableRunners()` to prefer healthy, lightly loaded runners. It is computed from CPU/memory/disk headroom. Runners below the threshold (default 10) are excluded from sandbox scheduling even if their state is `READY`.

### Gotchas

- **Runner ID registration:** Before health checks are accepted, the runner must have registered itself with the API (on startup). A runner that has never registered has no row in the `runner` table and healthcheck calls will return 404.
- **Clock skew:** The stale check compares timestamps. If the API container and runner container have significant clock drift (NTP misconfiguration), runners may appear stale or immune to staleness detection.
- **Score threshold tuning:** `RUNNER_AVAILABILITY_SCORE_THRESHOLD=10` in the compose file. On a heavily loaded dev machine, the runner's score may dip below 10 intermittently, making it invisible to the scheduler and causing "no runners available" errors. Lower the threshold for dev.

---

## Flow 7: Service Startup and Initialization Order

### Diagram

```mermaid
flowchart TD
    A([Docker Compose: docker compose up]) --> B

    subgraph SharedInfra [shared-infra network — start-shared-infra.sh]
        B[postgres-shared:5432\nPostgreSQL] 
        C[redis-shared:6379\nRedis]
        D[minio-shared:9000\nMinIO object storage]
        E[dex-shared:5556\nDex OIDC]
        F[registry-shared:5000\nDocker Registry]
        G[maildev-shared:1025\nMaildev SMTP]
        H[otel-collector-shared:4318\nOTel Collector]
    end

    subgraph DaytonaNet [daytona-network — build-and-run.sh]
        I[proxy\nport 12050:4000\nNo heavy deps — starts fast]
        J[runner\nport 12100:3003\nPrivileged DinD container]
        K[api\nport 12000:3500\nDepends on proxy + runner]
        L[ssh-gateway\nport 12150:2222]
    end

    SharedInfra -->|shared-infra network must be up| DaytonaNet

    I --> K
    J --> K

    K --> K1[NestJS bootstrap\nSwagger, CORS, pipes, filters]
    K1 --> K2[TypeORM connects\nto postgres-shared:5432]
    K2 --> K3{RUN_MIGRATIONS=true?}
    K3 -- Yes --> K4[Run pending DB migrations]
    K4 --> K5[AppService.onModuleInit]
    K3 -- No --> K5
    K5 --> K6{Default snapshot\nexists in DB?}
    K6 -- No --> K7[INSERT snapshot\nstate=pending\ngeneral=true]
    K7 --> K8[Dispatch INSPECT_SNAPSHOT_IN_REGISTRY job\nto default runner]
    K6 -- Yes --> K9
    K8 --> K9[Start health check monitor\ncron task]
    K9 --> K10([API fully ready\nhttp://192.168.16.153:12000])

    J --> J1[Go process starts\nDocker client initialized via FromEnv]
    J1 --> J2[Write daemon + plugin binaries]
    J2 --> J3[Start net rules manager\niptables for network isolation]
    J3 --> J4[Register runner with API\nPOST /api/runners]
    J4 --> J5[Start job poller\nGET /api/jobs every ~5s]
    J5 --> J6[Start healthcheck sender\nPOST /api/runners/healthcheck every ~10s]
    J6 --> J7([Runner fully ready\nhttp://192.168.16.153:12100])

    J5 -->|Picks up INSPECT_SNAPSHOT job| K8
    K8 -->|If image not in registry| PULL[Dispatch PULL_SNAPSHOT job]
    PULL -->|Runner executes| PULLRESULT[docker pull from Docker Hub\ndocker push to registry-shared:5000]
    PULLRESULT --> ACTIVE([snapshot.state = active\nPlatform ready for sandbox creation])
```

### Step-by-Step Explanation

1. **Shared infrastructure first.** The shared-infra services (PostgreSQL, Redis, MinIO, Dex, Registry, Maildev, OTel Collector) must be running on the `shared-infra` Docker network before the Daytona services start. Run `bash shared-infra/start-shared-infra.sh` first. These services are external to the main compose project (`external: true` in the networks section).

2. **Proxy starts first.** The proxy (`daytona-proxy:local-latest`) has no heavy startup dependencies. It connects to Redis and Dex on startup for cache initialization, then immediately begins accepting connections. It is listed as a `depends_on` prerequisite for the API.

3. **Runner starts.** The runner container is `privileged: true` to support Docker-in-Docker. On startup:
   - The Go process calls `client.NewClientWithOpts(client.FromEnv, ...)` to create a Docker client that connects to the DinD Docker daemon inside the runner container.
   - Static binaries (the Daytona daemon and computer-use plugin) are written to disk.
   - The net rules manager initializes `iptables` rules for inter-sandbox network isolation.
   - The runner registers itself with the API via `POST /api/runners`.
   - Job polling begins. The runner also starts sending healthchecks every ~10 seconds.

4. **API starts last.** The API (`depends_on: [proxy, runner]`) starts after both. NestJS bootstraps:
   - Pino logger, global exception filter, validation pipe, CORS, Swagger, audit interceptor.
   - TypeORM connects to `postgres-shared:5432` and, if `RUN_MIGRATIONS=true`, runs pending TypeORM migrations automatically.

5. **Database migrations.** Migrations are TypeORM migration files. They create tables (`sandbox`, `runner`, `snapshot`, `snapshot_runner`, `job`, `organization`, etc.) and apply schema changes. On first run, all migrations apply. On subsequent runs, only unapplied ones run. **Do not skip migrations** — the schema must match the entity definitions.

6. **`AppService.onModuleInit`.** After the module is fully initialized, this lifecycle hook runs. It seeds the admin user, admin organization, and default snapshot. The default snapshot name comes from `DEFAULT_SNAPSHOT=daytonaio/sandbox:0.5.0-slim`.

7. **INSPECT_SNAPSHOT job.** If the snapshot is new, the API dispatches an `INSPECT_SNAPSHOT_IN_REGISTRY` job. The runner (which is already polling) picks it up within ~5 seconds and checks `registry-shared:5000` for the image.

8. **PULL_SNAPSHOT job (if needed).** If the image is not in the registry, a `PULL_SNAPSHOT` job follows. The runner pulls `daytonaio/sandbox:0.5.0-slim` from Docker Hub (~3–5 minutes on a cold start depending on bandwidth), tags it, and pushes it to the internal registry.

9. **Platform becomes ready.** Once the snapshot is `active`, all components are operational. Users can log in via `http://localhost:12000` (not the WSL2 IP — see OIDC flow gotchas), create sandboxes, and access previews.

### Startup Timing Reference

| Service | Expected startup time | Readiness signal |
|---|---|---|
| postgres-shared | ~5s | TCP port 5432 accepting |
| redis-shared | ~2s | TCP port 6379 accepting |
| minio-shared | ~5s | HTTP /minio/health/live |
| dex-shared | ~3s | HTTP /dex/healthz |
| registry-shared | ~2s | HTTP /v2/ returns 200 |
| proxy | ~3s | HTTP /health returns 200 |
| runner | ~10s | Registers with API |
| api | ~15–30s | Migrations + module init |
| snapshot active | ~3–10min | PULL_SNAPSHOT job completes |

### Gotchas

- **Order matters:** If the Daytona compose stack starts before `shared-infra`, the API will fail to connect to PostgreSQL and crash-loop. Use `restart: always` (which is set) to self-heal once shared-infra comes up, but it causes noisy logs.
- **Runner registration race:** If the runner starts before the API is ready to accept registrations, the registration call fails. The runner should retry registration — check runner logs if the runner shows as unregistered after startup.
- **`daemon.json` for insecure registry:** The runner's `daemon.json` (mounted from `./runner-daemon.json`) must include `"insecure-registries": ["registry-shared:5000"]`. Without it, all image pushes to the local registry fail with TLS errors.
- **Migration failures:** If a migration fails (e.g., a constraint violation from existing data), the API will not start. Check the API logs for `MigrationExecutor` error messages. Sometimes dropping the database and restarting from scratch is the fastest fix in dev.
- **MinIO bucket creation:** The `S3_DEFAULT_BUCKET=daytona` bucket must exist. MinIO does not auto-create buckets. The API's startup code may create it, but if permissions are wrong, snapshot uploads will fail silently.

---

*Document generated from source code analysis of commit tree at `daytona-apr` repository. Local dev configuration from `docker/docker-compose.local.yaml` and `shared-infra/dex/config.yaml`.*
