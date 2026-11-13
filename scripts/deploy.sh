#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=5"

DRY_RUN=0
if [[ $# -gt 1 ]]; then
  echo "Использование: scripts/deploy.sh [--dry-run]" >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=1
  else
    echo "Неизвестный аргумент: $1" >&2
    exit 1
  fi
fi

ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${ROOT}/site/"

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
  echo "Файл site/index.html отсутствует, доставка не выполняется" >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "Есть незафиксированные изменения, доставка не выполняется" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  rsync -avz --delete --chmod=D755,F644 --dry-run -e "$SSH_CMD" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
  exit 0
fi

rsync -avz --delete --chmod=D755,F644 -e "$SSH_CMD" \
  "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

if ! curl -fsS --max-time 15 --cacert "$CA_CERT" -o /dev/null "$SITE_URL"; then
  echo "Ресурс недоступен: ${SITE_URL}" >&2
  exit 1
fi

git -C "$ROOT" rev-parse --short HEAD
