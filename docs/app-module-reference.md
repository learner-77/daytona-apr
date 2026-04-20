# Daytona Fork - Application & Module Reference Guide

**Generated:** 2026-04-20
**Repository:** daytona-apr (Daytona fork)
**Structure:** Monorepo with TypeScript (NestJS), Go, and language-specific SDK clients

---

## Core Applications

### 1. API Service (apps/api)

**Purpose:** Main backend API. Handles sandbox lifecycle, authentication, organization management, webhooks, audit logging.

**Language:** TypeScript / NestJS  
**Port:** 3500 | **Docker Image:** daytonaio/daytona-api

#### Key Modules
- src/sandbox/ - Core sandbox management
- src/organization/ - Multi-tenancy, quotas, usage
- src/auth/ - JWT, OIDC, API keys
- src/audit/ - Audit logging, ClickHouse
- src/webhook/ - Webhook management
- src/object-storage/ - S3/MinIO integration
- src/config/ - Configuration management
- src/migrations/ - Database migrations

#### Key Environment Variables
PORT, DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD, DB_DATABASE, REDIS_HOST, REDIS_PORT, ENCRYPTION_KEY, ENCRYPTION_SALT, OIDC_ISSUER_BASE_URL, OIDC_CLIENT_ID, PROXY_DOMAIN, PROXY_API_KEY, DEFAULT_RUNNER_DOMAIN, DEFAULT_RUNNER_API_URL, DEFAULT_RUNNER_API_KEY, S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY, OTEL_ENABLED, OTEL_EXPORTER_OTLP_ENDPOINT, POSTHOG_API_KEY, POSTHOG_HOST, POSTHOG_ENVIRONMENT

#### Key Endpoints

##### `GET /api/config`
Returns dashboard configuration. No authentication required. Called by Dashboard on every page load.

**Response:**
```json
{
  "posthog": {
    "apiKey": "string",
    "host": "string"
  },
  "oidc": {
    "issuer": "string",
    "clientId": "string"
  },
  "environment": "docker-compose|production|...",
  "proxyTemplateUrl": "string",
  "proxyToolboxUrl": "string",
  "defaultSnapshot": "string",
  "dashboardUrl": "string",
  "sshGatewayCommand": "string",
  "rateLimit": {
    "enabled": "boolean",
    "requestsPerMinute": "number"
  }
}
```

---

## Feature Flags (PostHog)

**Client-Side:**
- Dashboard uses PostHog JS SDK for client-side feature flag evaluation
- PostHog config (apiKey, host) fetched via `GET /api/config`
- Key flag: `dashboard_create-sandbox` (FeatureFlags.DASHBOARD_CREATE_SANDBOX) — controls whether CreateSandboxSheet component renders
  - Must be enabled in PostHog project OR fallback `?? true` must be present in code
  - Local dev fix applied: fallback ensures flag works without PostHog project setup

**Server-Side:**
- API uses OpenFeature + PostHog provider for server-side flag evaluation
- Configured via env vars: `POSTHOG_API_KEY`, `POSTHOG_HOST`, `POSTHOG_ENVIRONMENT`

---

### 2. Runner Service (apps/runner)

**Purpose:** Executes and manages sandbox containers. Container lifecycle, resource allocation, Docker-in-Docker.

**Language:** Go 1.25.5  
**Port:** 3003 | **Docker Image:** daytonaio/daytona-runner  
**Special:** Docker-in-Docker (dind)

#### Key Packages
- cmd/runner/main.go - Entry point
- pkg/api/ - REST API server
- pkg/docker/ - Docker client wrapper
- pkg/runner/ - Runner orchestration
- pkg/runner/v2/executor/ - Sandbox execution
- pkg/runner/v2/healthcheck/ - Health monitoring
- pkg/daemon/ - Embedded daemon
- pkg/cache/ - Snapshot/volume caching

#### Key Environment Variables
API_PORT, DAYTONA_RUNNER_TOKEN, DAYTONA_API_URL, RUNNER_DOMAIN, RESOURCE_LIMITS_DISABLED, SSH_GATEWAY_ENABLE, AWS_ENDPOINT_URL, LOG_FILE_PATH

---

### 3. Proxy Service (apps/proxy)

**Purpose:** Reverse proxy for sandbox applications. Routes traffic, OIDC auth, session management.

**Language:** Go 1.25.4  
**Port:** 4000 | **Docker Image:** daytonaio/daytona-proxy

#### Key Packages
- cmd/proxy/main.go - Entry point
- pkg/proxy/proxy.go - Main logic
- pkg/proxy/auth.go - Authentication
- pkg/proxy/get_sandbox_target.go - Routing

#### Key Environment Variables
PROXY_PORT, PROXY_PROTOCOL, PROXY_API_KEY, DAYTONA_API_URL, OIDC_CLIENT_ID, OIDC_DOMAIN, REDIS_HOST, REDIS_PORT, TOOLBOX_ONLY_MODE

---

### 4. SSH Gateway Service (apps/ssh-gateway)

**Purpose:** SSH server for sandbox access. Authenticates users, tunnels connections.

**Language:** Go 1.25.4  
**Port:** 2222 | **Docker Image:** daytonaio/daytona-ssh-gateway

#### Implementation
- main.go - Complete SSH server implementation

#### Key Environment Variables
SSH_GATEWAY_PORT, API_URL, API_KEY, SSH_PRIVATE_KEY, SSH_HOST_KEY

---

### 5. Daemon Service (apps/daemon)

**Purpose:** Embedded in sandbox containers. Manages terminal sessions, recording, SSH tunneling, toolbox.

**Language:** Go 1.25.5  
**Execution:** Init process in sandbox

#### Key Packages
- cmd/daemon/main.go - Entry point
- pkg/session/ - Session management
- pkg/terminal/ - PTY management
- pkg/ssh/ - SSH tunneling
- pkg/recording/ - Session recording
- pkg/toolbox/ - Code inspection

---

### 6. Snapshot Manager (apps/snapshot-manager)

**Purpose:** Manages snapshot creation, storage, retrieval.

**Language:** Go 1.25.5  
**Docker Image:** daytonaio/daytona-snapshot-manager

---

### 7. Dashboard (apps/dashboard)

**Purpose:** Web frontend UI.

**Language:** TypeScript / Vite  
**URL:** http://localhost:3500/dashboard

#### New Sandbox Flow - Guard Chain

Three conditions must **all** be true for sandbox creation to be enabled:

1. **`writePermitted`** — User authorization check
   - User is OWNER of the organization, OR
   - User has WRITE_SANDBOXES role permission

2. **`canCreateSandbox`** — Organization and user state check
   - `writePermitted === true` AND
   - Selected organization is NOT suspended (`!selectedOrganization?.suspended`)

3. **`createSandboxEnabled`** — Feature flag check
   - PostHog flag `dashboard_create-sandbox` is enabled
   - Defaults to `true` via `?? true` fallback in client code (local dev)

**Sandbox creation allowed only when:** `canCreateSandbox && createSandboxEnabled === true`

---

### 8. CLI Application (apps/cli)

**Purpose:** Command-line interface.

**Language:** Go

---

### 9. OTEL Collector (apps/otel-collector)

**Purpose:** Telemetry aggregation.

**Docker Image:** otel/opentelemetry-collector-contrib:0.138.0  
**Port:** 4318

---

### 10. Documentation Site (apps/docs)

**Purpose:** API documentation.

**Docker Image:** daytonaio/daytona-docs

---

## Shared Libraries (libs/)

### API Clients
api-client, api-client-go, api-client-java, api-client-python, api-client-python-async, api-client-ruby, analytics-api-client, toolbox-api-client*, runner-api-client

### SDKs
sdk-typescript, sdk-python, sdk-go, sdk-java, sdk-ruby

### Shared Code
- common-go - Logging, telemetry, caching
- runner-proto - Protocol buffers
- computer-use - Computer use agent
- opencode-plugin - Editor plugin

---

## Service Communication

### Architecture
```
Clients (Web, SSH, CLI)
    |
    ├──> Proxy :4000
    ├──> SSH Gateway :2222
    └──> API :3500
            |
            ├──> PostgreSQL :5432
            ├──> Redis :6379
            ├──> Runner :3003
            ├──> Registry :6000
            └──> MinIO :9000
                    └──> Sandbox Containers
```

### Authentication
- API Key: Bearer token
- OIDC: OpenID Connect via Dex
- SSH Key: Public key authentication
- JWT: Internal token-based

---

## Architectural Patterns

1. Microservices - Independent containerized services
2. Event-Driven - EventEmitter, webhooks, audit events
3. Multi-Tenancy - Organization isolation with quotas
4. Container Orchestration - Docker DinD with snapshots
5. Caching - Redis, TTL policies
6. Observability - OpenTelemetry, Prometheus, ClickHouse, Jaeger
7. Security - OIDC, SSH keys, API keys, encryption

---

## Ports Summary

| Service | Internal | External |
|---------|----------|----------|
| API | 3500 | 3500 |
| Proxy | 4000 | 4000 |
| Runner | 3003 | 3003 |
| SSH Gateway | 2222 | 2222 |
| PostgreSQL | 5432 | N/A |
| Redis | 6379 | N/A |
| Registry | 6000 | 6000 |
| MinIO | 9000 | 9001 (console) |
| Dex (OIDC) | 5556 | 5556 |
| OTEL Collector | 4318 | N/A |
| Jaeger | 16686 | 16686 |

---

## Notes

- All services containerized via docker-compose
- Database migrations auto-run on API startup
- TLS optional for local development
- SSH keys must be base64-encoded
- All services log to stdout/stderr
- Health checks for API, Runner, Proxy
- Privileged mode required for Runner

