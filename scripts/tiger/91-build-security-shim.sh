#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
compiler_environment
ensure_layout
start_log 91-build-security-shim

source_file="$PROJECT_ROOT/shim/securetransport_shim.c"
unexports="$PROJECT_ROOT/shim/shim_unexports.txt"
expected_exports="$PROJECT_ROOT/shim/shim_exports.txt"
backup_binary="$SECURITY_BUILD_DIR/SecurityBackup.framework/Versions/A/SecurityBackup"
object="$SECURITY_BUILD_DIR/securetransport_shim.o"
output="$OUTPUT_DIR/Security.new"

require_file "$source_file"
require_file "$unexports"
require_file "$expected_exports"
require_file "$backup_binary"
require_file "$SSL_PREFIX/lib/libssl.a"
require_file "$SSL_PREFIX/lib/libcrypto.a"

"$GCC" -O2 -mcpu=970 -fPIC -fno-common \
    -I"$SSL_PREFIX/include" \
    -c "$source_file" -o "$object"

"$GCC" -dynamiclib -o "$output" \
    "$object" \
    -Wl,-all_load "$SSL_PREFIX/lib/libssl.a" "$SSL_PREFIX/lib/libcrypto.a" \
    "$backup_binary" \
    -Wl,-sub_umbrella,SecurityBackup \
    -install_name /System/Library/Frameworks/Security.framework/Versions/A/Security \
    -compatibility_version 1.0.0 \
    -current_version 29774.0.0 \
    -Wl,-unexported_symbols_list,"$unexports" \
    -L"$GCC_LIB" -latomic -lz \
    -framework CoreFoundation

/usr/bin/file "$output"
/usr/bin/otool -D "$output"
/usr/bin/otool -L "$output" | grep SecurityBackup.framework
/usr/bin/otool -l "$output" | grep -A1 LC_SUB_UMBRELLA

actual="$SECURITY_BUILD_DIR/actual-shim-exports.txt"
/usr/bin/nm -gj "$output" | /usr/bin/sed -n '/^_SSL/p' | LC_ALL=C /usr/bin/sort > "$actual"
LC_ALL=C /usr/bin/sort "$expected_exports" > "$SECURITY_BUILD_DIR/expected-shim-exports.txt"
/usr/bin/diff -u "$SECURITY_BUILD_DIR/expected-shim-exports.txt" "$actual"
log "Security shim built with exact declared SSL export surface"

