#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "curl-$CURL_VERSION.tar.gz"
require_file "$SSL_PREFIX/certs/cacert.pem"
compiler_environment
start_log 60-build-curl

export CFLAGS="$CFLAGS -I$SSL_PREFIX/include"
export LDFLAGS="$LDFLAGS -L$SSL_PREFIX/lib"
extract_source "curl-$CURL_VERSION.tar.gz" "curl-$CURL_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" \
    --with-openssl="$SSL_PREFIX" \
    --with-ca-bundle="$SSL_PREFIX/certs/cacert.pem" \
    --disable-ldap --disable-ldaps \
    --without-libpsl --without-librtmp --without-nghttp2 \
    CC="$GCC"
make -j"$JOBS"
run_root make install
"$PREFIX/bin/curl" --version | head -2
"$PREFIX/bin/curl" --connect-timeout 10 --max-time 20 \
    --silent --show-error --output /dev/null https://example.com/
log "curl $CURL_VERSION installed and HTTPS verified"

