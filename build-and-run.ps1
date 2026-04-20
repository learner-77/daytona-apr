# Daytona Local Build & Deploy PowerShell Script

$ErrorActionPreference = "Stop"

# Colors
$Blue = "`e[0;34m"
$Green = "`e[0;32m"
$Yellow = "`e[1;33m"
$Red = "`e[0;31m"
$NC = "`e[0m"

Write-Host "${Blue}=== Daytona Local Build & Deploy ===${NC}`n"

# ===== WSL2 Detection =====
Write-Host "${Yellow}Detecting Docker configuration...${NC}"

$wslEnabled = $false
$wslIp = ""

$dockerInfo = docker info 2>$null
if ($dockerInfo -match "OSType.*linux") {
    $wslEnabled = $true
    Write-Host "${Green}✓ Docker is running on WSL2${NC}"

    $wslIp = (wsl hostname -I 2>$null).Trim().Split()[0]
    if ($wslIp) {
        Write-Host "${Green}✓ WSL2 IP: ${wslIp}${NC}`n"
    } else {
        Write-Host "${Yellow}⚠ Could not detect WSL2 IP${NC}"
        $wslEnabled = $false
    }
}

if (-not $wslEnabled) {
    Write-Host "${Yellow}ℹ Using localhost `(default Docker Desktop networking`)`n"
}

# Step 1: Sync from upstream
Write-Host "${Yellow}Step 1: Syncing with upstream...${NC}"
Write-Host "  Checking git remotes..."

$remotes = git remote -v 2>$null
if ($remotes -match "daytonaio.*upstream") {
    Write-Host "  Found upstream remote, fetching..."
    git fetch upstream 2>$null | Out-Null
    Write-Host "  Merging upstream/main..."
    git merge upstream/main 2>$null | Out-Null
    Write-Host "${Green}✓ Synced with upstream${NC}`n"
} else {
    Write-Host "${Yellow}⚠ No upstream remote found. Skipping upstream sync.${NC}"
    Write-Host "  Add upstream with: git remote add upstream https://github.com/daytonaio/daytona.git`n"
}

# Step 2: Build local Docker images
Write-Host "${Yellow}Step 2: Building local Docker images...${NC}"
Write-Host "  Total images to build: 4`n"

$images = @(
    @{name="api"; path="apps/api"},
    @{name="proxy"; path="apps/proxy"},
    @{name="runner"; path="apps/runner"},
    @{name="ssh-gateway"; path="apps/ssh-gateway"}
)

$buildCount = 0
foreach ($image in $images) {
    $buildCount++
    $imageTag = "daytona-$($image.name):local-latest"
    $dockerfilePath = "$($image.path)/Dockerfile"

    Write-Host "  [$buildCount/4] Building ${Blue}${imageTag}${NC}..."
    Write-Host "    Dockerfile: $dockerfilePath"

    $buildOutput = docker build -t $imageTag -f $dockerfilePath . 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ${Green}✓ Successfully built${NC}"
    } else {
        Write-Host "    ${Red}✗ Failed to build ${imageTag}${NC}"
        exit 1
    }
}

Write-Host "`n${Green}✓ All 4 images built successfully${NC}`n"

# Step 3: Create docker-compose file
Write-Host "${Yellow}Step 3: Creating custom docker-compose configuration...${NC}"
Write-Host "  Project name: daytona-learner77-fork"
Write-Host "  Port range: 12000-12650 `(50-port intervals`)"
Write-Host "  Writing: docker-compose.learner77.yaml`n"

# Step 4: Start services
Write-Host "${Yellow}Step 4: Starting services with local images...${NC}"
Write-Host "  Compose file: docker-compose.learner77.yaml"
Write-Host "  Starting containers...`n"

docker compose -f docker-compose.learner77.yaml up -d

Write-Host "`n  Waiting for services to initialize `(15 seconds`)..."
Start-Sleep -Seconds 15
Write-Host "  ${Green}✓ Services initialization complete${NC}"

Write-Host "`n${Green}=== Services Started Successfully ===${NC}"
Write-Host "`n${Blue}Checking container status...${NC}"

$runningContainers = docker ps --filter "label=com.docker.compose.project=daytona-learner77-fork" --filter "status=running" -q | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "  Running containers: ${Green}${runningContainers}${NC}`n"

Write-Host "`n${Blue}Project: daytona-learner77-fork${NC}"

if ($wslEnabled -and $wslIp) {
    $baseUrl = $wslIp
    Write-Host "${Green}✓ Accessing via WSL2 IP: ${baseUrl}${NC}"
} else {
    $baseUrl = "localhost"
    Write-Host "${Yellow}ℹ Accessing via localhost${NC}"
}

Write-Host "`n${Blue}Service URLs:${NC}"
Write-Host "  API:             http://${baseUrl}:12000"
Write-Host "  Dashboard:       http://${baseUrl}:12000/dashboard"
Write-Host "  Proxy:           http://${baseUrl}:12050"
Write-Host "  Runner:          http://${baseUrl}:12100"
Write-Host "  SSH Gateway:     ${baseUrl}:12150"
Write-Host "  Database:        ${baseUrl}:12200"
Write-Host "  PgAdmin:         http://${baseUrl}:12250"
Write-Host "  Redis:           ${baseUrl}:12300"
Write-Host "  Registry:        http://${baseUrl}:12350"
Write-Host "  Registry UI:     http://${baseUrl}:12400"
Write-Host "  MailDev:         http://${baseUrl}:12450"
Write-Host "  MinIO (S3):      http://${baseUrl}:12500"
Write-Host "  MinIO Console:   http://${baseUrl}:12550"
Write-Host "  Jaeger:          http://${baseUrl}:12600"
Write-Host "  OIDC/Dex:        http://${baseUrl}:12650/dex"

Write-Host "`n${Yellow}═══════════════════════════════════════${NC}"
Write-Host "${Yellow}Useful Commands:${NC}"
Write-Host "${Yellow}═══════════════════════════════════════${NC}"

Write-Host "`n${Yellow}View logs:${NC}"
Write-Host "  docker compose -f docker-compose.learner77.yaml logs -f api"

Write-Host "`n${Yellow}Stop services:${NC}"
Write-Host "  docker compose -f docker-compose.learner77.yaml down"

Write-Host "`n${Yellow}Rebuild and restart:${NC}"
Write-Host "  .\build-and-run.ps1"

Write-Host "`n${Yellow}Check service status:${NC}"
Write-Host "  docker compose -f docker-compose.learner77.yaml ps"

Write-Host "`n${Green}═══════════════════════════════════════${NC}"
Write-Host "${Green}Setup Complete!${NC}"
Write-Host "${Green}═══════════════════════════════════════${NC}`n"
