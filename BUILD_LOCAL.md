# Local Docker Build & Deploy

This guide explains how to build and run Daytona services locally from your fork instead of pulling pre-built images from Docker Hub.

## Why Use Local Builds?

- **No registry dependency** — avoid Docker Hub network issues
- **Test your changes immediately** — build directly from your code
- **Complete control** — use your fork's latest changes
- **Faster iteration** — build once, run multiple times

## Prerequisites

- Docker Desktop installed and running
- Git configured with upstream remote
- Bash (Linux/Mac) or PowerShell (Windows)

## Quick Start

### Option 1: Using Bash (Linux/Mac/WSL)

```bash
chmod +x build-and-run.sh
./build-and-run.sh
```

### Option 2: Using PowerShell (Windows)

```powershell
# Allow script execution if needed (run once)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run the script
.\build-and-run.ps1
```

## What the Script Does

1. **Syncs with upstream** — fetches and merges latest changes from upstream main
2. **Builds Docker images locally**:
   - `daytona-api:local-latest`
   - `daytona-proxy:local-latest`
   - `daytona-runner:local-latest`
   - `daytona-ssh-gateway:local-latest`
3. **Creates docker-compose override** — uses local images instead of hub images
4. **Starts all services** — runs `docker compose up` with both compose files

## Configuration

The script creates `docker/docker-compose.local.yaml` which overrides the main compose file to use your local images. You can edit this file to customize:

```yaml
services:
  api:
    image: daytona-api:local-latest
    # Add custom environment variables or ports here if needed
```

## Useful Commands

### View logs for a specific service
```bash
docker compose -f docker/docker-compose.yaml -f docker/docker-compose.local.yaml logs -f api
```

### Stop all services
```bash
docker compose -f docker/docker-compose.yaml -f docker/docker-compose.local.yaml down
```

### Rebuild only one image
```bash
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
```

### Rebuild everything and restart
```bash
./build-and-run.sh
```

## Service URLs

After running the script, access services at:

| Service | URL |
|---------|-----|
| API | http://localhost:3500 |
| Dashboard | http://localhost:3500/dashboard |
| Proxy | http://localhost:4000 |
| Runner | http://localhost:3003 |
| SSH Gateway | localhost:2222 |
| PgAdmin | http://localhost:5050 |
| Registry UI | http://localhost:5100 |
| Jaeger | http://localhost:16686 |
| MinIO | http://localhost:9001 |
| MailDev | http://localhost:1080 |

## Troubleshooting

### Script fails to build an image

Check the Dockerfile path and ensure it exists:
```bash
ls -la apps/api/Dockerfile
```

### Services won't start after build

Ensure all images were built successfully:
```bash
docker images | grep daytona
```

### Port already in use

Modify `docker/docker-compose.local.yaml` to use different ports, or stop other services using those ports.

### Git merge conflict

If syncing upstream fails with conflicts, resolve them manually:
```bash
git status
# Edit conflicting files
git add .
git commit -m "Resolve upstream merge conflict"
```

## Manual Setup (if script doesn't work)

If you prefer to set up manually:

```bash
# 1. Build images
docker build -t daytona-api:local-latest -f apps/api/Dockerfile .
docker build -t daytona-proxy:local-latest -f apps/proxy/Dockerfile .
docker build -t daytona-runner:local-latest -f apps/runner/Dockerfile .
docker build -t daytona-ssh-gateway:local-latest -f apps/ssh-gateway/Dockerfile .

# 2. Start with override file
docker compose \
  -f docker/docker-compose.yaml \
  -f docker/docker-compose.local.yaml \
  up -d
```

## Next Steps

- Edit source code in `apps/` directories
- Rebuild the changed image: `docker build -t daytona-{service}:local-latest -f apps/{service}/Dockerfile .`
- Restart the service: `docker compose restart {service}`

Or run the full script again to rebuild everything and restart all services.
