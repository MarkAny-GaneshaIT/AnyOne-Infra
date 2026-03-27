#!/usr/bin/env bash
# deploy.sh — Main deploy orchestrator for AnyOne Infrastructure.
#
# Usage:
#   deploy.sh [--dry-run] <staging|prod> [edr|uba|llm|all]
#
# Examples:
#   deploy.sh staging all          # Deploy all stacks to staging
#   deploy.sh prod edr             # Deploy only EDR stack to production
#   deploy.sh --dry-run staging    # Show what would be executed

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Resolve repo root (works regardless of where the script is invoked from)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

ENV="${1:-}"
STACK="${2:-all}"

if [[ -z "$ENV" ]]; then
  echo -e "${RED}Error: Environment is required.${NC}"
  echo "Usage: deploy.sh [--dry-run] <staging|prod> [edr|uba|llm|all]"
  exit 1
fi

if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  echo -e "${RED}Error: Environment must be 'staging' or 'prod'. Got: '$ENV'${NC}"
  exit 1
fi

VALID_STACKS=("edr" "uba" "llm" "all")
if [[ ! " ${VALID_STACKS[*]} " =~ " ${STACK} " ]]; then
  echo -e "${RED}Error: Stack must be one of: edr, uba, llm, all. Got: '$STACK'${NC}"
  exit 1
fi

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  AnyOne Infrastructure Deploy${NC}"
echo -e "${CYAN}  Environment: ${YELLOW}${ENV}${NC}"
echo -e "${CYAN}  Stack:       ${YELLOW}${STACK}${NC}"
if $DRY_RUN; then
  echo -e "${CYAN}  Mode:        ${YELLOW}DRY RUN${NC}"
fi
echo -e "${CYAN}========================================${NC}"
echo ""

# ---------------------------------------------------------------------------
# Initialize shared network
# ---------------------------------------------------------------------------
echo -e "${YELLOW}Initializing shared network...${NC}"
if $DRY_RUN; then
  echo -e "  ${CYAN}[dry-run] Would run: bash $REPO_ROOT/shared/network-init.sh${NC}"
else
  bash "$REPO_ROOT/shared/network-init.sh"
fi
echo ""

# ---------------------------------------------------------------------------
# Deploy function for a single stack
# ---------------------------------------------------------------------------
deploy_stack() {
  local stack_name="$1"
  local stack_dir="$REPO_ROOT/$stack_name"

  echo -e "${YELLOW}Deploying ${GREEN}${stack_name}${YELLOW} stack (${ENV})...${NC}"

  # Validate that required files exist
  if [[ ! -f "$stack_dir/docker-compose.yml" ]]; then
    echo -e "${RED}Error: $stack_dir/docker-compose.yml not found.${NC}"
    return 1
  fi

  if [[ ! -f "$stack_dir/docker-compose.${ENV}.yml" ]]; then
    echo -e "${RED}Error: $stack_dir/docker-compose.${ENV}.yml not found.${NC}"
    return 1
  fi

  # Build the compose command
  local cmd="docker compose"
  cmd+=" -f $stack_dir/docker-compose.yml"
  cmd+=" -f $stack_dir/docker-compose.${ENV}.yml"

  # Add env files if they exist
  if [[ -f "$stack_dir/.env" ]]; then
    cmd+=" --env-file $stack_dir/.env"
  fi
  if [[ -f "$stack_dir/.env.${ENV}" ]]; then
    cmd+=" --env-file $stack_dir/.env.${ENV}"
  fi

  cmd+=" up -d --pull always --remove-orphans"

  if $DRY_RUN; then
    echo -e "  ${CYAN}[dry-run] Would run:${NC}"
    echo -e "  ${CYAN}$cmd${NC}"
  else
    echo -e "  ${CYAN}Running: $cmd${NC}"
    eval "$cmd"
  fi

  echo -e "${GREEN}${stack_name} stack deployed successfully.${NC}"
  echo ""
}

# ---------------------------------------------------------------------------
# Deploy target stack(s)
# ---------------------------------------------------------------------------
if [[ "$STACK" == "all" ]]; then
  STACKS=("edr" "uba" "llm")
else
  STACKS=("$STACK")
fi

FAILED=0

for s in "${STACKS[@]}"; do
  if ! deploy_stack "$s"; then
    echo -e "${RED}Failed to deploy $s stack.${NC}"
    FAILED=1
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ "$FAILED" -eq 0 ]]; then
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}  All deployments completed successfully.${NC}"
  echo -e "${GREEN}========================================${NC}"
else
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}  Some deployments failed. Check output above.${NC}"
  echo -e "${RED}========================================${NC}"
  exit 1
fi
