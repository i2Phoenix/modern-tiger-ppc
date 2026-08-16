#!/bin/bash

set -e

HOST_LIB_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$HOST_LIB_DIR/../.." && pwd)

if [ -f "$PROJECT_ROOT/config/target.env" ]; then
    # Local-only configuration. This file is excluded from Git and deployment.
    . "$PROJECT_ROOT/config/target.env"
fi

log() {
    printf '[modern-tiger-ppc] %s\n' "$*"
}

die() {
    printf '[modern-tiger-ppc] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_target() {
    [ -n "${TIGER_HOST:-}" ] || die "set TIGER_HOST in config/target.env"
    [ -n "${TIGER_USER:-}" ] || die "set TIGER_USER in config/target.env"
}

target_spec() {
    printf '%s@%s' "$TIGER_USER" "$TIGER_HOST"
}

sha256_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        die "neither shasum nor sha256sum is available"
    fi
}

