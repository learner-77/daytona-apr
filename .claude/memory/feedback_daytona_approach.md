---
name: Daytona session feedback and approach preferences
description: User preferences and feedback from the Daytona local dev setup session — what worked, what to avoid
type: feedback
originSessionId: dd76bd2e-80e1-4860-a8eb-afa92f791e7a
---
# Daytona Session — Approach Preferences

## Shared-Infra Pattern
User explicitly designed and approved the shared-infra pattern: reusable Docker services (postgres, redis, minio, dex, etc.) on their own Docker network, separate from app-specific services. Always maintain this separation — Daytona-specific setup (DB creation, MinIO bucket) belongs in Daytona's own build script, not in shared-infra init scripts.

**Why:** Shared-infra services must be reusable across multiple projects (e.g., langfuse could also use postgres-shared). App-specific initialization would pollute shared state.

**How to apply:** When adding new services, decide: "is this reusable across projects?" → shared-infra. "is this Daytona-only?" → docker/docker-compose.local.yaml + build-and-run.sh.

## Port Ranges
User approved fixed port ranges: 13000–13900 for shared-infra (50-port intervals), 12000–12650 for Daytona. Never overlap these.

**Why:** Easy to identify which project owns which port at a glance.

## Scripts: Bash only, well-documented
User confirmed bash-only scripts with inline documentation. No Python, no PowerShell.

## Daytona-specific DB/bucket creation in build script
User explicitly said: the daytona postgres DB creation should be in Daytona's build-and-run.sh (after connecting to postgres-shared), NOT in shared-infra/postgres/init-databases.sql.

**Why:** Keeps each app's initialization self-contained.

## Subagent parallelization
User requested parallel subagents for independent tasks (verify files + create docs + create KB). Use Agent tool with run_in_background=false for parallel independent work.

## Verbose but concise responses
User said "continue investigating" multiple times when blocked — prefers persistent investigation over asking questions. Keep digging into logs, DB, source code before declaring a dead end.

## docker compose up with --force-recreate for config changes
Volume mounts and env var changes require --force-recreate, not just restart. Always use force-recreate when compose file changes.
