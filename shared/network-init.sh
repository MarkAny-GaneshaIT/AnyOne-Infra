#!/usr/bin/env bash
# Creates the shared anyone_network Docker network if it does not already exist.
# All stacks (edr, uba, llm) communicate over this external network.

set -euo pipefail

NETWORK_NAME="anyone_network"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Network '$NETWORK_NAME' already exists."
else
  docker network create "$NETWORK_NAME"
  echo "Network '$NETWORK_NAME' created."
fi
