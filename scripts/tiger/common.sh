#!/bin/bash

set -e

if [ -n "${MODERN_TIGER_PROJECT_ROOT:-}" ]; then
    PROJECT_ROOT=$MODERN_TIGER_PROJECT_ROOT
else
    TIGER_SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    PROJECT_ROOT=$(cd "$TIGER_SCRIPT_DIR/../.." && pwd)
    MODERN_TIGER_PROJECT_ROOT=$PROJECT_ROOT
fi
. "$PROJECT_ROOT/config/versions.conf"

PREFIX=${PREFIX:-/usr/local}
GCC_PREFIX="$PREFIX/gcc7/$GCC_VERSION"
GCC="$GCC_PREFIX/bin/gcc-7"
GXX="$GCC_PREFIX/bin/g++-7"
GCC_LIB="$GCC_PREFIX/lib/gcc/7"
SSL_PREFIX="$PREFIX/ssl"
PERL_PREFIX="$PREFIX/perl-5.42"
OPENSSH_PREFIX="$PREFIX/openssh"
GIT_PREFIX="$PREFIX/git"

BUILD_ROOT=${MODERN_TIGER_BUILD_ROOT:-$HOME/modern-tiger-ppc-build}
SOURCES_DIR="$BUILD_ROOT/sources"
WORK_DIR="$BUILD_ROOT/work"
LOG_DIR="$BUILD_ROOT/logs"
OUTPUT_DIR="$BUILD_ROOT/output"
PACKAGE_STAGE_DIR="$BUILD_ROOT/package-stages"
SECURITY_BUILD_DIR="$BUILD_ROOT/security"
JOBS=${JOBS:-2}

export PREFIX GCC_PREFIX GCC GXX GCC_LIB SSL_PREFIX PERL_PREFIX
export OPENSSH_PREFIX GIT_PREFIX BUILD_ROOT SOURCES_DIR WORK_DIR LOG_DIR
export OUTPUT_DIR PACKAGE_STAGE_DIR SECURITY_BUILD_DIR JOBS PROJECT_ROOT
export MODERN_TIGER_PROJECT_ROOT

log() {
    printf '[modern-tiger-ppc] %s\n' "$*"
}

die() {
    printf '[modern-tiger-ppc] ERROR: %s\n' "$*" >&2
    exit 1
}

ensure_layout() {
    mkdir -p "$SOURCES_DIR" "$WORK_DIR" "$LOG_DIR" "$OUTPUT_DIR" \
        "$PACKAGE_STAGE_DIR" "$SECURITY_BUILD_DIR"
}

require_tiger() {
    local machine version build
    machine=$(/usr/bin/uname -p)
    version=$(/usr/bin/sw_vers -productVersion)
    build=$(/usr/bin/sw_vers -buildVersion)

    [ "$machine" = powerpc ] || die "PowerPC is required; detected $machine"
    [ "$version" = "$TARGET_PRODUCT_VERSION" ] || \
        die "Mac OS X $TARGET_PRODUCT_VERSION is required; detected $version"
    [ "$build" = "$TARGET_BUILD_VERSION" ] || \
        die "Tiger build $TARGET_BUILD_VERSION is required; detected $build"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_file() {
    [ -f "$1" ] || die "required file not found: $1"
}

require_source() {
    require_file "$SOURCES_DIR/$1"
}

run_root() {
    if [ "$(/usr/bin/id -u)" -eq 0 ]; then
        "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

reset_work_dir() {
    local target=$1
    case "$target" in
        "$WORK_DIR"/*|"$PACKAGE_STAGE_DIR"/*|"$SECURITY_BUILD_DIR"/*) ;;
        *) die "refusing to reset path outside managed build roots: $target" ;;
    esac
    rm -rf "$target"
    mkdir -p "$target"
}

extract_source() {
    local archive_name=$1
    local work_name=$2
    local archive="$SOURCES_DIR/$archive_name"
    local temp="$WORK_DIR/.extract-$work_name"
    local destination="$WORK_DIR/$work_name"
    local count top entry

    require_file "$archive"
    reset_work_dir "$temp"
    case "$archive_name" in
        *.tar.gz|*.tgz) (cd "$temp" && /usr/bin/gzip -dc "$archive" | /usr/bin/tar xf -) ;;
        *.tar.bz2) (cd "$temp" && /usr/bin/bzip2 -dc "$archive" | /usr/bin/tar xf -) ;;
        *.tar.xz)
            require_command xz
            (cd "$temp" && xz -dc "$archive" | /usr/bin/tar xf -)
            ;;
        *) die "unsupported source archive: $archive_name" ;;
    esac

    count=0
    top=
    for entry in "$temp"/* "$temp"/.[!.]* "$temp"/..?*; do
        [ -d "$entry" ] || continue
        [ -L "$entry" ] && continue
        count=$((count + 1))
        top=$entry
    done
    [ "$count" -eq 1 ] || die "$archive_name must contain exactly one top-level directory"

    case "$destination" in "$WORK_DIR"/*) rm -rf "$destination" ;; *) die "unsafe extraction destination" ;; esac
    mv "$top" "$destination"
    rmdir "$temp"
    EXTRACTED_SOURCE="$destination"
}

start_log() {
    ensure_layout
    LOG_FILE="$LOG_DIR/$1.log"
    : > "$LOG_FILE"
    log "logging to $LOG_FILE"
    exec >> "$LOG_FILE" 2>&1
}

compiler_environment() {
    require_file "$GCC"
    export PATH="$PREFIX/bin:$GCC_PREFIX/bin:$PERL_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export CC="$GCC"
    export CXX="$GXX"
    export CFLAGS="-O2 -mcpu=970 -mtune=970 -I$PREFIX/include -B $PREFIX/libexec/tiger-ld/"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-L$PREFIX/lib -L$GCC_LIB -B $PREFIX/libexec/tiger-ld/"
    export DYLD_LIBRARY_PATH="$GCC_LIB:$PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
}
