#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger

printf 'system=%s build=%s machine=%s\n' \
    "$(/usr/bin/sw_vers -productVersion)" \
    "$(/usr/bin/sw_vers -buildVersion)" \
    "$(/usr/bin/uname -p)"

if [ -x /usr/bin/xcodebuild ]; then
    /usr/bin/xcodebuild -version
elif [ -x /Developer/usr/bin/xcodebuild ]; then
    /Developer/usr/bin/xcodebuild -version
else
    die "Xcode 2.5 Developer Tools are required"
fi

for tool in /usr/bin/gcc /usr/bin/make /usr/bin/mkbom /bin/pax \
    /usr/bin/otool /usr/bin/install_name_tool /usr/bin/nm /usr/bin/file; do
    [ -x "$tool" ] || die "required Tiger/Xcode tool missing: $tool"
done

security=/System/Library/Frameworks/Security.framework/Versions/A/Security
require_file "$security"
printf 'security_md5=%s\n' "$(/sbin/md5 -q "$security")"
/usr/bin/file "$security"

if [ -d "$SOURCES_DIR" ]; then
    source_count=0
    for source_archive in "$SOURCES_DIR"/* "$SOURCES_DIR"/.[!.]* "$SOURCES_DIR"/..?*; do
        [ -f "$source_archive" ] || continue
        source_count=$((source_count + 1))
    done
else
    source_count=0
fi
printf 'source_archives=%s\n' "$source_count"

for tool in "$GCC" "$PERL_PREFIX/bin/perl" "$SSL_PREFIX/bin/openssl" \
    /usr/local/bin/make /usr/bin/curl /usr/bin/wget /usr/bin/ssh /usr/bin/git; do
    if [ -x "$tool" ]; then
        printf 'installed=%s\n' "$tool"
    else
        printf 'missing=%s\n' "$tool"
    fi
done

if [ -x /usr/bin/pkgconf ] || [ -x "$PREFIX/bin/pkgconf" ]; then
    pkgconf_bin=/usr/bin/pkgconf
    [ -x "$pkgconf_bin" ] || pkgconf_bin="$PREFIX/bin/pkgconf"
    pkgconf_missing=
    for dependency in $(/usr/bin/otool -L "$pkgconf_bin" 2>/dev/null | \
        /usr/bin/awk 'NR > 1 && $1 ~ /^\/usr\/local\// {print $1}'); do
        if [ ! -e "$dependency" ] && [ ! -L "$dependency" ]; then
            pkgconf_missing=$dependency
            break
        fi
    done
    if [ -n "$pkgconf_missing" ]; then
        printf 'pkgconf=broken missing=%s\n' "$pkgconf_missing"
        /usr/bin/otool -L "$pkgconf_bin" 2>/dev/null || true
    elif "$pkgconf_bin" --version >/dev/null 2>&1; then
        printf 'pkgconf=working\n'
    else
        printf 'pkgconf=broken\n'
        /usr/bin/otool -L "$pkgconf_bin" 2>/dev/null || true
    fi
fi

df -k "$HOME" | tail -1
log "read-only host check complete"
