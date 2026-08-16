#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
ensure_layout
start_log 15-install-ld-wrapper

source_file="$PROJECT_ROOT/tools/tiger-ld/ld-wrapper.c"
require_file "$source_file"
output="$WORK_DIR/tiger-ld"
/usr/bin/gcc -Wall -Wextra -O2 "$source_file" -o "$output"

run_root mkdir -p "$PREFIX/libexec/tiger-ld"
run_root /usr/bin/install -o root -g wheel -m 755 "$output" "$PREFIX/libexec/tiger-ld/ld"
"$PREFIX/libexec/tiger-ld/ld" -v
log "Tiger linker option translator installed"

