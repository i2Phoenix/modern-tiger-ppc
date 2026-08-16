#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/host-common.sh"
. "$PROJECT_ROOT/config/versions.conf"

if awk -F '|' 'NF >= 3 && $1 !~ /^#/ && $3 == "-" {print $1}' \
    "$PROJECT_ROOT/config/sources.conf" | grep .; then
    die "all release source checksums must be locked"
fi

license="$PROJECT_ROOT/LICENSE"
notice="$PROJECT_ROOT/NOTICE"
[ -f "$license" ] || die "project LICENSE is missing"
[ -f "$notice" ] || die "project NOTICE is missing"
/usr/bin/grep -Fxq 'MIT License' "$license" || die "LICENSE is not the selected MIT text"
/usr/bin/grep -Fxq 'Copyright (c) 2026 Modern Tiger Project' "$license" || \
    die "LICENSE copyright notice is incorrect"
/usr/bin/grep -Fq 'modern-tiger-ppc' "$notice" || \
    die "NOTICE does not identify the original project"
[ "$PROJECT_STATUS" = release ] || die "PROJECT_STATUS is '$PROJECT_STATUS', not 'release'"
log "release policy checks OK"
