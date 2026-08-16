#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "openssl-$OPENSSL_VERSION.tar.gz"
require_file "$PERL_PREFIX/bin/perl"
compiler_environment
start_log 50-build-openssl

extract_source "openssl-$OPENSSL_VERSION.tar.gz" "openssl-$OPENSSL_VERSION"
cd "$EXTRACTED_SOURCE"
"$PERL_PREFIX/bin/perl" ./Configure darwin-ppc-cc \
    --prefix="$SSL_PREFIX" \
    --openssldir="$SSL_PREFIX" \
    shared no-tests no-async \
    CC="$GCC" \
    CPPFLAGS="-DOPENSSL_NO_APPLE_CRYPTO_RANDOM" \
    CFLAGS="-O2 -mcpu=970"

/usr/bin/sed -i '' 's|^EX_LIBS=.*|& -latomic|' Makefile
/usr/bin/sed -i '' 's|^LDFLAGS=.*|& -L'"$GCC_LIB"'|' Makefile

make -j"$JOBS" build_sw CC="$GCC"
run_root make install_sw

export DYLD_LIBRARY_PATH="$SSL_PREFIX/lib:$GCC_LIB:$PREFIX/lib"
"$SSL_PREFIX/bin/openssl" version -a
log "OpenSSL $OPENSSL_VERSION installed"

