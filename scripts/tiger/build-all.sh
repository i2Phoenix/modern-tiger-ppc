#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger

if [ "${1:-}" != --yes ]; then
    cat <<EOF
This performs a full source build and installs components under /usr/local.
It does not activate the Security shim or replace the SSH service; those changes
only happen when generated packages are explicitly installed.

Re-run with:
  bash scripts/tiger/build-all.sh --yes
EOF
    exit 2
fi

log "verifying locked source archives"
/bin/bash "$SCRIPT_DIR/verify-sources.sh"

for step in \
    10-install-gcc7.sh \
    15-install-ld-wrapper.sh \
    20-build-syslibs.sh \
    30-build-perl.sh \
    40-build-make.sh \
    50-build-openssl.sh \
    55-install-ca-bundle.sh \
    60-build-curl.sh \
    65-build-wget.sh \
    70-build-openssh.sh \
    80-build-git.sh \
    90-prepare-security-backup.sh \
    91-build-security-shim.sh; do
    log "running $step"
    /bin/bash "$SCRIPT_DIR/$step"
done

log "full source build complete"
