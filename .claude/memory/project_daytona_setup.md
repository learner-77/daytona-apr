---
name: Daytona local dev environment setup
description: Full context of the Daytona fork local Docker dev environment on Windows/WSL2 — architecture, ports, networks, credentials, and what was built
type: project
originSessionId: dd76bd2e-80e1-4860-a8eb-afa92f791e7a
---
# Daytona Fork — Local Dev Environment

**Repo:** C:\tools\my_codebases\daytona_apr_fork\daytona-apr
**Branch:** claude/musing-booth-406e94
**Git user:** learner-77

## Architecture

Windows + Docker Desktop with WSL2 NAT backend. WSL2 IP: **192.168.16.153**

Two Docker Compose projects:
1. **shared-infra** — reusable services on port range 13000–13900 (network: `shared-infra`, external)
2. **daytona-learner77-fork** — Daytona app services on port range 12000–12650 (network: `daytona-network` + joins `shared-infra`)

## Daytona Services (12000–12650)

| Service      | External Port | Internal | Image                      |
|-------------|--------------|----------|---------------------------|
| api          | 12000        | 3500     | daytona-api:local-latest   |
| proxy        | 12050        | 4000     | daytona-proxy:local-latest |
| runner       | 12100        | 3003     | daytona-runner:local-latest|
| ssh-gateway  | 12150        | 2222     | daytona-ssh-gateway:local-latest |

Dashboard URL: http://192.168.16.153:12000/dashboard
API URL: http://192.168.16.153:12000/api

## Shared-Infra Services (13000–13650)

| Service         | External Port(s) | Container Name        |
|----------------|------------------|-----------------------|
| PostgreSQL      | 13000            | postgres-shared       |
| Redis           | 13050            | redis-shared          |
| MinIO (S3 API)  | 13100 / 13150    | minio-shared          |
| MailDev         | 13200 / 13250    | maildev-shared        |
| Dex (OIDC)      | 13300            | dex-shared            |
| Jaeger          | 13350            | jaeger-shared         |
| OTel Collector  | 13400 / 13450    | otel-collector-shared |
| Prometheus      | 13500            | prometheus-shared     |
| Grafana         | 13550            | grafana-shared        |
| Registry        | 13600            | registry-shared       |
| Registry UI     | 13650            | registry-ui-shared    |

## Key Credentials

- PostgreSQL: admin / admin, DB: daytona
- MinIO: minioadmin / minioadmin, bucket: daytona
- Dex OIDC test user: admin@local.dev / password
- Registry: no auth (open), HTTP only
- Grafana: admin / admin

## OIDC / Authentication

- Dex issuer: http://192.168.16.153:13300/dex
- Client ID: daytona, public: true (PKCE, no secret)
- crypto.subtle requires localhost or HTTPS — use netsh portproxy or access via localhost
- netsh command: `netsh interface portproxy add v4tov4 listenport=12000 listenaddress=0.0.0.0 connectport=12000 connectaddress=192.168.16.153` (not persistent across reboots)

## Runner — Docker-in-Docker

Runner uses DinD (base image: docker:28.2.2-dind-alpine3.22). Its internal Docker daemon reads /etc/docker/daemon.json. We mount docker/runner-daemon.json into it to allow HTTP push/pull to registry-shared:5000.

## Default Snapshot

DEFAULT_SNAPSHOT=daytonaio/sandbox:0.5.0-slim
After first startup, runner pulls it from Docker Hub and pushes to registry-shared:5000. Takes 3–10 min on cold start. If snapshot gets stuck in error state, delete from DB and restart API.

## Why: Key decisions
- Shared-infra pattern: reusable services (postgres, redis, minio, dex, etc.) shared across multiple Docker projects without port conflicts
- Port ranges: 13000–13900 for shared, 12000–12650 for daytona — no overlap
- Dex in shared-infra: OIDC provider reusable by any app; daytona is just one client
