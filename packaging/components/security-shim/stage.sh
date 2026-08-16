#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_file "$OUTPUT_DIR/Security.new"
stage_copy_as "$OUTPUT_DIR/Security.new" \
    /usr/local/libexec/modern-tiger-ppc/Security.staged
stage_asset rollback-security-shim.sh \
    /usr/local/sbin/modern-tiger-ppc-rollback-security-shim
/bin/chmod 755 "$STAGE/usr/local/sbin/modern-tiger-ppc-rollback-security-shim"
