#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_command /usr/bin/install_name_tool
ensure_layout
start_log 90-prepare-security-backup

system_security=/System/Library/Frameworks/Security.framework/Versions/A/Security
pristine_security=$system_security.pristine
backup_framework="$SECURITY_BUILD_DIR/SecurityBackup.framework"
backup_binary="$backup_framework/Versions/A/SecurityBackup"

require_file "$system_security"
if [ -f "$pristine_security" ]; then
    source_security="$pristine_security"
else
    if /usr/bin/otool -L "$system_security" | grep -q SecurityBackup.framework; then
        die "active Security is already a shim and Security.pristine is missing"
    fi
    source_security="$system_security"
fi

reset_work_dir "$backup_framework"
mkdir -p "$backup_framework/Versions/A"
/bin/cp -p "$source_security" "$backup_binary"
/usr/bin/install_name_tool -id \
    /System/Library/PrivateFrameworks/SecurityBackup.framework/Versions/A/SecurityBackup \
    "$backup_binary"

(cd "$backup_framework" && /bin/ln -s Versions/Current/SecurityBackup SecurityBackup)
(cd "$backup_framework/Versions" && /bin/ln -s A Current)

mkdir -p "$SECURITY_BUILD_DIR/manifests"
{
    printf 'product_version=%s\n' "$(/usr/bin/sw_vers -productVersion)"
    printf 'build_version=%s\n' "$(/usr/bin/sw_vers -buildVersion)"
    printf 'source_path=%s\n' "$source_security"
    printf 'source_md5=%s\n' "$(/sbin/md5 -q "$source_security")"
    printf 'backup_md5=%s\n' "$(/sbin/md5 -q "$backup_binary")"
} > "$SECURITY_BUILD_DIR/manifests/security-input.txt"

/usr/bin/otool -D "$backup_binary"
log "private SecurityBackup framework prepared outside the repository"

