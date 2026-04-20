#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Daytona Local Build & Deploy ===${NC}\n"

# Detect WSL2 and get IP
WSL_IP=""
if command -v wsl &> /dev/null; then
  # Running on Windows with WSL2 available
  DOCKER_INFO=$(docker info 2>/dev/null)
  if echo "$DOCKER_INFO" | grep -q "OSType.*linux"; then
    # Docker is using WSL2 backend
    WSL_IP=$(wsl hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$WSL_IP" ]; then
      echo -e "${GREEN}✓ Docker is using WSL2 backend - IP: ${WSL_IP}${NC}\n"
    fi
  fi
elif grep -qi microsoft /proc/version 2>/dev/null; then
  # Running inside WSL2
  WSL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ -n "$WSL_IP" ]; then
    echo -e "${GREEN}✓ Running inside WSL2 - IP: ${WSL_IP}${NC}\n"
  fi
fi

# Step 1: Sync from upstream
echo -e "${YELLOW}Step 1: Syncing with upstream...${NC}"
if git remote -v | grep -q "daytonaio.*upstream"; then
  git fetch upstream
  git merge upstream/main || echo "Already up to date or no upstream configured"
  echo -e "${GREEN}✓ Synced with upstream${NC}\n"
else
  echo -e "${YELLOW}⚠ No upstream remote found. Skipping upstream sync.${NC}"
  echo "  Add upstream with: git remote add upstream https://github.com/daytonaio/daytona.git\n"
fi

# Step 2: Build local Docker images
echo -e "${YELLOW}Step 2: Building local Docker images...${NC}"

IMAGES=(
  "api:apps/api"
  "proxy:apps/proxy"
  "runner:apps/runner"
  "ssh-gateway:apps/ssh-gateway"
)

for image_info in "${IMAGES[@]}"; do
  IFS=':' read -r image_name dockerfile_path <<< "$image_info"
  image_tag="daytona-${image_name}:local-latest"

  echo -e "  Building ${BLUE}${image_tag}${NC}..."
  if docker build -t "$image_tag" -f "${dockerfile_path}/Dockerfile" .; then
    echo -e "  ${GREEN}✓ Built ${image_tag}${NC}"
  else
    echo -e "  ${RED}✗ Failed to build ${image_tag}${NC}"
    exit 1
  fi
done

echo -e "${GREEN}✓ All images built successfully${NC}\n"

# Step 3: Verify local compose file exists
echo -e "${YELLOW}Step 3: Setting up docker-compose configuration...${NC}"
if [ -f "docker/docker-compose.local.yaml" ]; then
  echo -e "  ${GREEN}✓ Found docker/docker-compose.local.yaml${NC}\n"
  COMPOSE_FILE="docker/docker-compose.local.yaml"
else
  echo -e "  ${RED}✗ docker/docker-compose.local.yaml not found${NC}"
  exit 1
fi

# Step 4: Ensure daytona database exists in shared postgres
echo -e "${YELLOW}Step 4: Ensuring daytona database exists in shared postgres...${NC}"
if docker ps --filter "name=postgres-shared" --filter "status=running" -q | grep -q .; then
  echo -e "  postgres-shared is running, waiting for it to be ready..."
  until docker exec postgres-shared pg_isready -U admin -d postgres -q 2>/dev/null; do
    sleep 2
  done
  DB_EXISTS=$(docker exec postgres-shared psql -U admin -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='daytona';" 2>/dev/null)
  if [ "$DB_EXISTS" = "1" ]; then
    echo -e "  ${GREEN}✓ Database 'daytona' already exists${NC}\n"
  else
    docker exec postgres-shared psql -U admin -d postgres -c "CREATE DATABASE daytona;" > /dev/null 2>&1
    echo -e "  ${GREEN}✓ Database 'daytona' created${NC}\n"
  fi
else
  echo -e "  ${YELLOW}⚠ postgres-shared not running — start shared-infra first:${NC}"
  echo -e "  ${YELLOW}  bash shared-infra/start-shared-infra.sh${NC}\n"
  exit 1
fi

# Step 5: Ensure daytona bucket exists in shared MinIO
echo -e "${YELLOW}Step 5: Ensuring daytona bucket exists in shared MinIO...${NC}"
if docker ps --filter "name=minio-shared" --filter "status=running" -q | grep -q .; then
  BUCKET_EXISTS=$(docker run --rm --network shared-infra --entrypoint sh minio/mc:latest \
    -c 'mc alias set s http://minio-shared:9000 minioadmin minioadmin > /dev/null 2>&1 && mc ls s/daytona > /dev/null 2>&1 && echo yes || echo no' 2>/dev/null)
  if [ "$BUCKET_EXISTS" = "yes" ]; then
    echo -e "  ${GREEN}✓ Bucket 'daytona' already exists${NC}\n"
  else
    docker run --rm --network shared-infra --entrypoint sh minio/mc:latest \
      -c 'mc alias set s http://minio-shared:9000 minioadmin minioadmin > /dev/null 2>&1 && mc mb s/daytona > /dev/null 2>&1'
    echo -e "  ${GREEN}✓ Bucket 'daytona' created${NC}\n"
  fi
else
  echo -e "  ${YELLOW}⚠ minio-shared not running — start shared-infra first${NC}\n"
  exit 1
fi

# Step 6: Start services
echo -e "${YELLOW}Step 6: Starting services with local images...${NC}"
echo -e "  Using compose file: ${COMPOSE_FILE}\n"

docker compose -f "$COMPOSE_FILE" --env-file docker/.env up -d

echo -e "\n${GREEN}=== Services Started Successfully ===${NC}"
echo -e "\n${BLUE}Project: daytona-learner77-fork${NC}"

if [ -n "$WSL_IP" ]; then
  BASE_URL="$WSL_IP"
  echo -e "\n${GREEN}✓ Accessing via WSL2 IP: ${BASE_URL}${NC}"
else
  BASE_URL="localhost"
  echo -e "\n${BLUE}ℹ Accessing via localhost${NC}"
fi

echo -e "\n${BLUE}Service URLs:${NC}"
echo "  API:             http://${BASE_URL}:12000"
echo "  Dashboard:       http://${BASE_URL}:12000/dashboard"
echo "  Proxy:           http://${BASE_URL}:12050"
echo "  Runner:          http://${BASE_URL}:12100"
echo "  SSH Gateway:     ${BASE_URL}:12150"
echo "  Database:        ${BASE_URL}:12200"
echo "  PgAdmin:         http://${BASE_URL}:12250"
echo "  Redis:           ${BASE_URL}:12300"
echo "  Registry:        http://${BASE_URL}:12350"
echo "  Registry UI:     http://${BASE_URL}:12400"
echo "  MailDev:         http://${BASE_URL}:12450"
echo "  MinIO (S3):      http://${BASE_URL}:12500"
echo "  MinIO Console:   http://${BASE_URL}:12550"
echo "  Jaeger:          http://${BASE_URL}:12600"
echo "  OIDC/Dex:        http://${BASE_URL}:12650/dex"

echo -e "\n${YELLOW}Useful commands:${NC}"
echo "  View logs:      docker compose -f docker/docker-compose.local.yaml --env-file docker/.env logs -f api"
echo "  Stop services:  docker compose -f docker/docker-compose.local.yaml --env-file docker/.env down"
echo "  Restart API:    docker compose -f docker/docker-compose.local.yaml --env-file docker/.env restart api"
echo "  Check status:   docker compose -f docker/docker-compose.local.yaml --env-file docker/.env ps"
