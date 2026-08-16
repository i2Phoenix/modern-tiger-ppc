#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_dir "$OPENSSH_PREFIX"
stage_copy_root "$OPENSSH_PREFIX" /usr/local
stage_copy_as_root "$COMPONENT_DIR/assets/sshd_config.modern-tiger-ppc" \
    /usr/local/openssh/etc/sshd_config.modern-tiger-ppc
stage_copy_as_root "$COMPONENT_DIR/assets/ssh.plist.modern-tiger-ppc" \
    /usr/local/openssh/share/launchd/ssh.plist.modern-tiger-ppc
stage_copy_as_root "$COMPONENT_DIR/assets/rollback-openssh.sh" \
    /usr/local/sbin/modern-tiger-ppc-rollback-openssh
run_root /bin/chmod 755 \
    "$STAGE/usr/local/sbin/modern-tiger-ppc-rollback-openssh"
