#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/host-common.sh"

require_command ssh
require_command tar
require_target

REMOTE_PROJECT=${TIGER_REMOTE_PROJECT:-modern-tiger-ppc}
case "$REMOTE_PROJECT" in
    ''|/*|*..*|*[!A-Za-z0-9._/-]*) die "unsafe TIGER_REMOTE_PROJECT: $REMOTE_PROJECT" ;;
esac

TARGET=$(target_spec)
REMOTE_BUILD=modern-tiger-ppc-build

log "creating project and source-cache directories on $TARGET"
ssh "$TARGET" "mkdir -p \"\$HOME/$REMOTE_PROJECT\" \"\$HOME/$REMOTE_BUILD/sources\""

log "copying public source tree"
COPYFILE_DISABLE=1 tar \
    --exclude .git \
    --exclude .work \
    --exclude cache/sources \
    --exclude config/target.env \
    --exclude dist \
    -C "$PROJECT_ROOT" -cf - . | \
    ssh "$TARGET" "cd \"\$HOME/$REMOTE_PROJECT\" && tar -xf -"

if find "$PROJECT_ROOT/cache/sources" -type f -mindepth 1 -maxdepth 1 | grep . >/dev/null 2>&1; then
    log "copying source cache"
    COPYFILE_DISABLE=1 tar -C "$PROJECT_ROOT/cache/sources" -cf - . | \
        ssh "$TARGET" "cd \"\$HOME/$REMOTE_BUILD/sources\" && tar -xf -"
else
    log "source cache is empty; run make download before building on Tiger"
fi

log "deployment complete: $TARGET:~/$REMOTE_PROJECT"

