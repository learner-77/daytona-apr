# Custom Configuration: daytona-learner77-fork

## Project Setup

**Project Name:** `daytona-learner77-fork`  
**Port Range:** 12000 - 12650 (50-port intervals)  
**Base Compose File:** `docker/docker-compose.yaml`  
**Override File:** `docker/docker-compose.local.yaml`

## Port Mapping Reference

| Service | Internal Port | External Port | Access URL |
|---------|---------------|---------------|-----------|
| API | 3500 | **12000** | http://localhost:12000 |
| Dashboard | 3500 | **12000** | http://localhost:12000/dashboard |
| Proxy | 4000 | **12050** | http://localhost:12050 |
| Runner | 3003 | **12100** | http://localhost:12100 |
| SSH Gateway | 2222 | **12150** | ssh://localhost:12150 |
| PostgreSQL | 5432 | **12200** | localhost:12200 |
| PgAdmin | 80 | **12250** | http://localhost:12250 |
| Redis | 6379 | **12300** | localhost:12300 |
| Registry (Docker) | 6000 | **12350** | http://localhost:12350 |
| Registry UI | 80 | **12400** | http://localhost:12400 |
| MailDev | 1080 | **12450** | http://localhost:12450 |
| MinIO (S3) | 9000 | **12500** | http://localhost:12500 |
| MinIO Console | 9001 | **12550** | http://localhost:12550 |
| Jaeger Tracing | 16686 | **12600** | http://localhost:12600 |
| Dex (OIDC) | 5556 | **12650** | http://localhost:12650/dex |

## Environment Variables Updated

The following key environment variables have been updated in `docker-compose.local.yaml`:

```yaml
# API Service
PROXY_DOMAIN=proxy.localhost:12050
PROXY_TEMPLATE_URL=http://{{PORT}}-{{sandboxId}}.proxy.localhost:12050
PUBLIC_OIDC_DOMAIN=http://localhost:12650/dex
DASHBOARD_URL=http://localhost:12000/dashboard
DASHBOARD_BASE_API_URL=http://localhost:12000

# SSH Gateway
SSH_GATEWAY_URL=localhost:12150
```

## Service-to-Service Communication

Internal service communication (within Docker network) still uses service hostnames:

```yaml
# These remain unchanged (internal Docker network)
DB_HOST=db
DB_PORT=5432
REDIS_HOST=redis
REDIS_PORT=6379
DAYTONA_API_URL=http://api:3500/api
OIDC_ISSUER_BASE_URL=http://dex:5556/dex
```

**External** access (from your machine) uses `localhost:PORT`:
- API: `http://localhost:12000`
- Database: `localhost:12200`
- Dex: `http://localhost:12650/dex`

## Database Credentials

- **Host:** localhost:12200
- **Database:** daytona
- **Username:** user
- **Password:** pass
- **PgAdmin URL:** http://localhost:12250
- **PgAdmin User:** dev@daytona.io
- **PgAdmin Password:** pgadmin

## S3/MinIO Credentials

- **Endpoint:** http://localhost:12500
- **Console:** http://localhost:12550
- **Access Key:** minioadmin
- **Secret Key:** minioadmin
- **Default Bucket:** daytona

## Email (MailDev)

- **SMTP Host:** localhost (internal) / localhost:12450 (external)
- **SMTP Port:** 1025
- **Web UI:** http://localhost:12450

## Quick Start

### Run with custom configuration:

```powershell
# PowerShell (Windows)
.\build-and-run.ps1

# Bash (Linux/Mac/WSL)
./build-and-run.sh
```

### Verify services are running:

```bash
docker ps --filter "label=com.docker.compose.project=daytona-learner77-fork"
```

### Check logs for a specific service:

```bash
docker compose -f docker/docker-compose.yaml -f docker/docker-compose.local.yaml logs -f api
```

### Stop all services:

```bash
docker compose -f docker/docker-compose.yaml -f docker/docker-compose.local.yaml down
```

### Restart a single service (after code changes):

```bash
# Rebuild API and restart
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
docker compose -f docker/docker-compose.yaml -f docker/docker-compose.local.yaml restart api
```

## Customizing Ports Further

To change any port:

1. Edit `docker/docker-compose.local.yaml`
2. Update the port mapping (e.g., `12000:3500` → `13000:3500`)
3. Update any environment variables that reference that port
4. Restart: `docker compose up -d`

Example - Change API port from 12000 to 13000:

```yaml
  api:
    image: daytona-api:local-latest
    ports:
      - 13000:3500  # Changed from 12000:3500
    environment:
      - DASHBOARD_URL=http://localhost:13000/dashboard
      - DASHBOARD_BASE_API_URL=http://localhost:13000
```

## Container Names

Container names follow the pattern: `daytona-learner77-fork-{service}-1`

Examples:
- `daytona-learner77-fork-api-1`
- `daytona-learner77-fork-runner-1`
- `daytona-learner77-fork-db-1`

View all containers:

```bash
docker ps -a | grep daytona-learner77-fork
```

## Troubleshooting

### Port already in use

If port 12XXX is already in use:

```bash
# Find what's using the port (Linux/Mac)
lsof -i :12000

# Windows
netstat -ano | findstr :12000
```

Then edit `docker/docker-compose.local.yaml` to use a different port.

### Services can't communicate

If services can't reach each other, check:
1. They're on the same Docker network (`daytona-network`)
2. Internal DNS names are correct (e.g., `db`, `redis`, `api`)
3. Internal ports match (not external ports)

### Reset everything

```bash
# Stop and remove all containers
docker compose -f docker/docker-compose.yaml -f docker/docker-compose.local.yaml down -v

# Remove images
docker rmi daytona-api:local-latest daytona-proxy:local-latest daytona-runner:local-latest daytona-ssh-gateway:local-latest

# Start fresh
.\build-and-run.ps1
```
