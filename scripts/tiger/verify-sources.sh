#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
ensure_layout
require_command /usr/bin/gcc

source_list="$PROJECT_ROOT/config/sources.conf"
hasher_source="$PROJECT_ROOT/tools/tiger-sha256/tiger-sha256.c"
verify_work="$WORK_DIR/source-integrity"
hasher="$verify_work/tiger-sha256"
empty_file="$verify_work/empty"
empty_expected=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

require_file "$source_list"
require_file "$hasher_source"
reset_work_dir "$verify_work"

/usr/bin/gcc -std=c99 -Wall -Wextra -Werror -O2 \
    "$hasher_source" -o "$hasher"
: > "$empty_file"
empty_actual=$("$hasher" "$empty_file" | /usr/bin/awk '{print $1}')
[ "$empty_actual" = "$empty_expected" ] || \
    die "Tiger SHA-256 helper failed its empty-input self-test"

verified=0
unlocked=0
while IFS='|' read -r filename url expected; do
    case "$filename" in ''|'#'*) continue ;; esac
    archive="$SOURCES_DIR/$filename"
    require_file "$archive"
    if [ "$expected" = - ]; then
        log "source checksum is not locked: $filename"
        unlocked=$((unlocked + 1))
        continue
    fi

    actual=$("$hasher" "$archive" | /usr/bin/awk '{print $1}')
    [ "$actual" = "$expected" ] || \
        die "source checksum mismatch for $filename: expected $expected, got $actual"
    verified=$((verified + 1))
done < "$source_list"

[ "$verified" -gt 0 ] || die "no locked source archives were verified"
log "source integrity OK: verified=$verified unlocked=$unlocked"
