#!/bin/bash
# =============================================================================
# Shared Infrastructure Startup Script
# =============================================================================
# Creates the shared-infra Docker network if needed, then starts all shared
# services. Run this once before starting any app that uses shared-infra.
#
# Usage:
#   ./start-shared-infra.sh          — start all services
#   ./start-shared-infra.sh --down   — stop all services
#   ./start-shared-infra.sh --status — show running containers
# =============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

COMPOSE_FILE="$(dirname "$0")/docker-compose.shared-infra.yaml"

# ---------------------------------------------------------------------------
# Handle flags
# ---------------------------------------------------------------------------
if [ "$1" = "--down" ]; then
  echo -e "${YELLOW}Stopping shared infrastructure...${NC}"
  docker compose -f "$COMPOSE_FILE" down
  echo -e "${GREEN}✓ Stopped${NC}"
  exit 0
fi

if [ "$1" = "--status" ]; then
  docker compose -f "$COMPOSE_FILE" ps
  exit 0
fi

echo -e "${BLUE}=== Shared Infrastructure Startup ===${NC}\n"

# ---------------------------------------------------------------------------
# Step 1: Detect WSL2 IP for displaying correct access URLs
# ---------------------------------------------------------------------------
WSL_IP=""
if command -v wsl &> /dev/null; then
  DOCKER_INFO=$(docker info 2>/dev/null)
  if echo "$DOCKER_INFO" | grep -q "OSType.*linux"; then
    WSL_IP=$(wsl hostname -I 2>/dev/null | awk '{print $1}')
    [ -n "$WSL_IP" ] && echo -e "${GREEN}✓ WSL2 detected — IP: ${WSL_IP}${NC}\n"
  fi
elif grep -qi microsoft /proc/version 2>/dev/null; then
  WSL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -n "$WSL_IP" ] && echo -e "${GREEN}✓ Running inside WSL2 — IP: ${WSL_IP}${NC}\n"
fi
BASE_URL=${WSL_IP:-localhost}

# ---------------------------------------------------------------------------
# Step 2: Create shared-infra network if it does not exist
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Step 1: Checking shared-infra network...${NC}"
if docker network inspect shared-infra &>/dev/null; then
  echo -e "  ${GREEN}✓ Network 'shared-infra' already exists${NC}\n"
else
  docker network create shared-infra
  echo -e "  ${GREEN}✓ Created network 'shared-infra'${NC}\n"
fi

# ---------------------------------------------------------------------------
# Step 3: Start all shared services
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Step 2: Starting shared infrastructure services...${NC}"
echo -e "  Compose file: $COMPOSE_FILE\n"
docker compose -f "$COMPOSE_FILE" up -d

# ---------------------------------------------------------------------------
# Step 4: Wait for services to initialise
# ---------------------------------------------------------------------------
echo -e "\n${YELLOW}Step 3: Waiting for services to initialise (20 seconds)...${NC}"
sleep 20
echo -e "  ${GREEN}✓ Initialisation complete${NC}\n"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo -e "${GREEN}=== Shared Infrastructure Running ===${NC}"
echo -e "\n${BLUE}Network:${NC} shared-infra"
echo -e "${BLUE}Access via:${NC} ${BASE_URL}\n"

echo -e "${BLUE}Service URLs:${NC}"
echo "  PostgreSQL       ${BASE_URL}:13000        (admin/admin)"
echo "  Redis            ${BASE_URL}:13050"
echo "  MinIO S3 API     http://${BASE_URL}:13100"
echo "  MinIO Console    http://${BASE_URL}:13150  (minioadmin/minioadmin)"
echo "  MailDev Web      http://${BASE_URL}:13200"
echo "  MailDev SMTP     ${BASE_URL}:13250"
echo "  Dex OIDC         http://${BASE_URL}:13300/dex"
echo "  Jaeger UI        http://${BASE_URL}:13350"
echo "  OTel gRPC        ${BASE_URL}:13400"
echo "  OTel HTTP        http://${BASE_URL}:13450"
echo "  Prometheus       http://${BASE_URL}:13500"
echo "  Grafana          http://${BASE_URL}:13550  (admin/admin)"
echo "  Registry         http://${BASE_URL}:13600"
echo "  Registry UI      http://${BASE_URL}:13650"

echo -e "\n${BLUE}Internal hostnames (use inside Docker apps):${NC}"
echo "  postgres-shared:5432    redis-shared:6379"
echo "  minio-shared:9000       maildev-shared:1025"
echo "  dex-shared:5556         otel-collector-shared:4318"
echo "  jaeger-shared:16686     prometheus-shared:9090"
echo "  registry-shared:5000"

echo -e "\n${YELLOW}Useful commands:${NC}"
echo "  Logs:   docker compose -f $COMPOSE_FILE logs -f"
echo "  Stop:   ./start-shared-infra.sh --down"
echo "  Status: ./start-shared-infra.sh --status"

echo -e "\n${YELLOW}To connect an app to shared-infra, add to its docker-compose:${NC}"
echo "  networks:"
echo "    shared-infra:"
echo "      external: true"

echo -e "\n${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Ready!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}\n"
