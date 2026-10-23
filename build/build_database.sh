#!/usr/bin/env bash

# ============================================================
# File: build/build_database.sh
# Project: Document Workflow and E-signing Portal
#
# Purpose:
#   Wrapper for the Python database build automation.
#
# Usage:
#
#   ./build/build_database.sh \
#       OWNER \
#       REPOSITORY \
#       VERSION_TAG \
#       TARGET_DATABASE
#
# Example:
#
#   ./build/build_database.sh \
#       sanikadeshmukh3 \
#       Digital-Document-Signing-Portal \
#       v1.0.0 \
#       document_portal_demo
# ============================================================


# ------------------------------------------------------------
# Fail immediately when:
#
# - a command fails
# - an undefined variable is used
# - a pipeline command fails
# ------------------------------------------------------------

set -Eeuo pipefail

IFS=$'\n\t'


# ============================================================
# Input arguments
# ============================================================

OWNER="${1:?GitHub owner is required}"

REPOSITORY="${2:?GitHub repository name is required}"

VERSION_TAG="${3:?Git tag/version label is required}"

TARGET_DATABASE="${4:?Target database name is required}"


# ============================================================
# Locate project directories
# ============================================================

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

PROJECT_ROOT="$(
    cd "${SCRIPT_DIR}/.."
    pwd
)"

PYTHON_BUILD_SCRIPT="${SCRIPT_DIR}/build_database.py"

ENV_FILE="${SCRIPT_DIR}/.env"


# ============================================================
# Logging helper
# ============================================================

log() {
    printf '%s | %s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$*"
}


fail() {
    log "BUILD FAILED: $*"
    exit 1
}


# ============================================================
# Error handling
# ============================================================

on_error() {
    local exit_code="$?"

    local line_number="$1"

    local command="$2"

    printf '%s | ERROR | exit=%s | line=%s | command=%s\n' \
        "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$exit_code" \
        "$line_number" \
        "$command" >&2

    exit "$exit_code"
}


trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR


# ============================================================
# Required-command validation
# ============================================================

require_command() {
    command -v "$1" >/dev/null 2>&1 \
        || fail "Required command not found: $1"
}


require_command git
require_command python3


# ============================================================
# Validate Python build script
# ============================================================

[[ -f "$PYTHON_BUILD_SCRIPT" ]] \
    || fail "Missing Python build script: $PYTHON_BUILD_SCRIPT"


# ============================================================
# Validate local configuration
# ============================================================

if [[ ! -f "$ENV_FILE" ]]; then
    fail "
Missing build/.env.

Copy the example configuration first:

    cp build/config.example.env build/.env
"
fi


# ============================================================
# Log build request
# ============================================================

log "Starting database build wrapper."

log "Repository: ${OWNER}/${REPOSITORY}"

log "Version tag: ${VERSION_TAG}"

log "Target database: ${TARGET_DATABASE}"


# ============================================================
# Execute Python build
# ============================================================

python3 "$PYTHON_BUILD_SCRIPT" \
    "$OWNER" \
    "$REPOSITORY" \
    "$VERSION_TAG" \
    "$TARGET_DATABASE"


# ============================================================
# Success
# ============================================================

log "Database build wrapper completed successfully."