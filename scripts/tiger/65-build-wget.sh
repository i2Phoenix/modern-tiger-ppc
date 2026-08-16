#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "wget-$WGET_VERSION.tar.gz"
require_file "$SSL_PREFIX/certs/cacert.pem"
compiler_environment
start_log 65-build-wget

export CFLAGS="$CFLAGS -I$SSL_PREFIX/include"
export LDFLAGS="$LDFLAGS -L$SSL_PREFIX/lib"
export PKG_CONFIG_PATH="$SSL_PREFIX/lib/pkgconfig:$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
extract_source "wget-$WGET_VERSION.tar.gz" "wget-$WGET_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" \
    --with-ssl=openssl \
    --with-openssl-dir="$SSL_PREFIX" \
    --with-cabundle="$SSL_PREFIX/certs/cacert.pem" \
    --without-libpsl --disable-nls \
    CC="$GCC"
make -j"$JOBS"
run_root make install
"$PREFIX/bin/wget" --version | head -1
log "wget $WGET_VERSION installed"
