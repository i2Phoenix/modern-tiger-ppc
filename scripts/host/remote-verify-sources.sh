#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/host-common.sh"

require_command ssh
require_target

REMOTE_PROJECT=${TIGER_REMOTE_PROJECT:-modern-tiger-ppc}
case "$REMOTE_PROJECT" in
    ''|/*|*..*|*[!A-Za-z0-9._/-]*) die "unsafe TIGER_REMOTE_PROJECT: $REMOTE_PROJECT" ;;
esac

TARGET=$(target_spec)
log "verifying locked sources on $TARGET"
ssh "$TARGET" "cd \"\$HOME/$REMOTE_PROJECT\" && /bin/bash scripts/tiger/verify-sources.sh"
