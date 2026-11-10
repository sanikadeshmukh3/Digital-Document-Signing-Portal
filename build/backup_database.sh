#!/usr/bin/env bash
# ============================================================
# File: build/backup_database.sh
# Project: Document Workflow and E-signing Portal
#
# Purpose:
#   Create a timestamped logical backup (schema + data + routines
#   + triggers + events) of a target database, so a known state
#   can be reproduced/restored later.
#
# Usage (from WSL, repo root):
#   build/backup_database.sh [DATABASE]
#     DATABASE defaults to document_portal_demo
#
# Output:
#   .build-work/backups/<DATABASE>-<UTC-timestamp>.sql
#
# Restore later with:
#   mysql --host=... --user=... --password=... < <backup>.sql
# Connection settings are read from build/.env.
# ============================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

set -a
# shellcheck disable=SC1091
. build/.env
set +a

DB="${1:-document_portal_demo}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$REPO_ROOT/.build-work/backups"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/${DB}-${TS}.sql"

echo "Dumping ${DB} -> ${OUT}"
mysqldump \
  --host="${DB_HOST:-127.0.0.1}" --port="${DB_PORT:-3306}" \
  --user="$DB_ADMIN_USER" --password="$DB_ADMIN_PASSWORD" \
  --routines --triggers --events \
  --single-transaction --set-gtid-purged=OFF \
  --databases "$DB" > "$OUT"

echo "Backup written: ${OUT} ($(stat -c %s "$OUT") bytes)"
