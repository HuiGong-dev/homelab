#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${1:-homelab}"
STATE_DIR="$(pwd)"
BACKUP_DIR="$HOME/homelab/backups/opentofu-state/${ENV_NAME}"
TIMESTAMP="$(date +%Y-%m-%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

if [[ -f "${STATE_DIR}/terraform.tfstate" ]]; then
  cp "${STATE_DIR}/terraform.tfstate" \
     "${BACKUP_DIR}/${TIMESTAMP}-terraform.tfstate"
  echo "Backed up terraform.tfstate"
else
  echo "No terraform.tfstate found"
fi

if [[ -f "${STATE_DIR}/terraform.tfstate.backup" ]]; then
  cp "${STATE_DIR}/terraform.tfstate.backup" \
     "${BACKUP_DIR}/${TIMESTAMP}-terraform.tfstate.backup"
  echo "Backed up terraform.tfstate.backup"
fi

echo "Backup directory: ${BACKUP_DIR}"