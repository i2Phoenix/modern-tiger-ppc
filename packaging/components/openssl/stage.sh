#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_dir "$SSL_PREFIX"
stage_copy "$SSL_PREFIX" /usr/local

# DER roots are isolated in the ca-roots component; the PEM bundle remains in
# OpenSSL so command-line TLS works even when system trust import is deselected.
/bin/rm -rf "$STAGE/usr/local/ssl/certs/modern-roots"
