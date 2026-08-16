#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/host-common.sh"

require_command curl

SOURCE_LIST="$PROJECT_ROOT/config/sources.conf"
DEST="$PROJECT_ROOT/cache/sources"

[ -f "$SOURCE_LIST" ] || die "source list not found: $SOURCE_LIST"
mkdir -p "$DEST"

while IFS='|' read -r filename url expected; do
    case "$filename" in
        ''|'#'*) continue ;;
        */*|'..') die "unsafe source filename: $filename" ;;
    esac

    [ -n "$url" ] || die "missing URL for $filename"
    [ -n "$expected" ] || die "missing checksum field for $filename"

    output="$DEST/$filename"
    if [ ! -f "$output" ]; then
        partial="$output.partial"
        log "downloading $filename"
        curl --fail --location --retry 3 --connect-timeout 20 \
            --output "$partial" "$url"
        mv "$partial" "$output"
    else
        log "using cached $filename"
    fi

    actual=$(sha256_file "$output")
    if [ "$expected" != '-' ] && [ "$actual" != "$expected" ]; then
        die "checksum mismatch for $filename: expected $expected, got $actual"
    fi
    printf '%s  %s\n' "$actual" "$filename"
done < "$SOURCE_LIST"

log "source cache ready: $DEST"

