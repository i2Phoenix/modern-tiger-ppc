#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source cacert.pem
require_file "$SSL_PREFIX/bin/openssl"
ensure_layout
start_log 55-install-ca-bundle

stage="$WORK_DIR/ca-bundle"
reset_work_dir "$stage"
cp "$SOURCES_DIR/cacert.pem" "$stage/cacert.pem"

mkdir -p "$stage/pem" "$stage/der"
cd "$stage/pem"
/usr/bin/awk '
    /-----BEGIN CERTIFICATE-----/ { n++; file=sprintf("cert_%03d.pem", n) }
    file != "" { print > file }
    /-----END CERTIFICATE-----/ { close(file); file="" }
' "$stage/cacert.pem"

count=0
for pem in cert_*.pem; do
    count=$((count + 1))
    der=$(printf 'cert_%03d.der' "$count")
    "$SSL_PREFIX/bin/openssl" x509 -in "$pem" -outform DER -out "$stage/der/$der"
done
[ "$count" -gt 0 ] || die "no certificates were extracted from cacert.pem"

run_root mkdir -p "$SSL_PREFIX/certs"
run_root /bin/cp "$stage/cacert.pem" "$SSL_PREFIX/certs/cacert.pem"
run_root /bin/ln -sfn cacert.pem "$SSL_PREFIX/certs/ca-bundle.crt"
run_root /bin/cp "$stage/cacert.pem" "$SSL_PREFIX/cert.pem"

# This directory is owned exclusively by modern-tiger-ppc.
run_root /bin/rm -rf "$SSL_PREFIX/certs/modern-roots"
run_root /bin/mkdir -p "$SSL_PREFIX/certs/modern-roots"
run_root /bin/cp "$stage/der"/*.der "$SSL_PREFIX/certs/modern-roots/"

export DYLD_LIBRARY_PATH="$SSL_PREFIX/lib:$GCC_LIB:$PREFIX/lib"
run_root "$SSL_PREFIX/bin/c_rehash" "$SSL_PREFIX/certs"
log "installed CA bundle with $count roots; X509Anchors was not modified"
