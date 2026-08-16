#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
ensure_layout

network_host=${1:-example.com}
security=/System/Library/Frameworks/Security.framework/Versions/A/Security
test_work="$WORK_DIR/installed-runtime-tests"
reset_work_dir "$test_work"
require_file "$security"

cc=/usr/bin/gcc
common_flags='-std=gnu99 -Wall -Wextra'

"$cc" $common_flags "$PROJECT_ROOT/tests/test_all_symbols.c" \
    -o "$test_work/test_all_symbols"
"$cc" $common_flags "$PROJECT_ROOT/tests/test_wrapper.c" \
    -o "$test_work/test_wrapper"
"$cc" $common_flags "$PROJECT_ROOT/tests/test_full.c" \
    -framework CoreFoundation -framework CoreServices \
    -o "$test_work/test_full"
"$cc" $common_flags "$PROJECT_ROOT/tests/test_handshake.c" \
    -o "$test_work/test_handshake"
"$cc" $common_flags "$PROJECT_ROOT/tests/test_fw_path.c" \
    -framework Security -o "$test_work/test_fw_path"
"$cc" $common_flags "$PROJECT_ROOT/tests/test_sys.c" \
    -framework Security -o "$test_work/test_sys"

log "checking active Security export surfaces"
"$test_work/test_all_symbols" "$security" "$PROJECT_ROOT/shim/shim_exports.txt"
"$test_work/test_all_symbols" "$security" \
    "$PROJECT_ROOT/shim/security_non_ssl_symbols.txt"

log "checking wrapper and forwarded APIs"
"$test_work/test_wrapper" "$security"
"$test_work/test_full" "$security"
"$test_work/test_fw_path"

log "checking TLS through dlopen and the linked system framework"
"$test_work/test_handshake" "$security" "$network_host" 443
"$test_work/test_sys" "$network_host"

log "installed Security runtime tests passed against $network_host"
