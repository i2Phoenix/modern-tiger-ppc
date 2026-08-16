#!/bin/bash

set -e

if [ -z "${PROJECT_ROOT:-}" ]; then
    PROJECT_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
fi
MODERN_TIGER_PROJECT_ROOT=$PROJECT_ROOT
export MODERN_TIGER_PROJECT_ROOT
. "$PROJECT_ROOT/scripts/tiger/common.sh"

[ -n "${STAGE:-}" ] || die "STAGE is not set"
[ -n "${COMPONENT_DIR:-}" ] || die "COMPONENT_DIR is not set"

stage_target() {
    local target_path=$1
    case "$target_path" in
        /*) ;;
        *) die "staging destination must be absolute: $target_path" ;;
    esac
    case "/$target_path/" in
        */../*|*/./*) die "unsafe staging destination: $target_path" ;;
    esac
    printf '%s%s\n' "$STAGE" "$target_path"
}

stage_mkdir() {
    local destination
    destination=$(stage_target "$1")
    /bin/mkdir -p "$destination"
}

stage_require_file() {
    [ -f "$1" ] || die "required package input missing: $1"
}

stage_require_dir() {
    [ -d "$1" ] || die "required package input directory missing: $1"
}

stage_copy() {
    local source_path=$1
    local destination_dir
    destination_dir=$(stage_target "$2")
    [ -e "$source_path" ] || [ -L "$source_path" ] || \
        die "package input missing: $source_path"
    /bin/mkdir -p "$destination_dir"
    /bin/cp -p -P -R "$source_path" "$destination_dir/"
}

stage_copy_as() {
    local source_path=$1
    local destination
    destination=$(stage_target "$2")
    [ -e "$source_path" ] || [ -L "$source_path" ] || \
        die "package input missing: $source_path"
    /bin/mkdir -p "$(/usr/bin/dirname "$destination")"
    /bin/cp -p -P -R "$source_path" "$destination"
}

stage_copy_root() {
    local source_path=$1
    local destination_dir
    destination_dir=$(stage_target "$2")
    [ -e "$source_path" ] || [ -L "$source_path" ] || \
        die "package input missing: $source_path"
    run_root /bin/mkdir -p "$destination_dir"
    run_root /bin/cp -p -P -R "$source_path" "$destination_dir/"
}

stage_copy_as_root() {
    local source_path=$1
    local destination
    destination=$(stage_target "$2")
    [ -e "$source_path" ] || [ -L "$source_path" ] || \
        die "package input missing: $source_path"
    run_root /bin/mkdir -p "$(/usr/bin/dirname "$destination")"
    run_root /bin/cp -p -P -R "$source_path" "$destination"
}

stage_copy_matches() {
    local source_pattern=$1
    local destination_dir=$2
    local match_count=0
    local source_path
    for source_path in $source_pattern; do
        [ -e "$source_path" ] || [ -L "$source_path" ] || continue
        stage_copy "$source_path" "$destination_dir"
        match_count=$((match_count + 1))
    done
    [ "$match_count" -gt 0 ] || die "package input pattern had no matches: $source_pattern"
}

stage_copy_optional_matches() {
    local source_pattern=$1
    local destination_dir=$2
    local source_path
    for source_path in $source_pattern; do
        [ -e "$source_path" ] || [ -L "$source_path" ] || continue
        stage_copy "$source_path" "$destination_dir"
    done
}

stage_symlink() {
    local link_target=$1
    local destination
    destination=$(stage_target "$2")
    /bin/mkdir -p "$(/usr/bin/dirname "$destination")"
    /bin/rm -f "$destination"
    /bin/ln -s "$link_target" "$destination"
}

# Copy only the canonical dylib symlink chain and optional development archive,
# avoiding stale versions left by older builds in /usr/local/lib.
stage_copy_library_family() {
    local library_name=$1
    local current="$PREFIX/lib/$library_name.dylib"
    local link_target
    local install_name
    local current_name
    local install_name_file
    local seen=
    local depth=0

    stage_require_file "$current"
    while :; do
        case "$seen" in
            # A Mach-O install name commonly points back to a versioned
            # symlink whose target was already copied. The filesystem link is
            # validated by stage_require_file before reaching this branch.
            *"|$current|"*) break ;;
        esac
        seen="$seen|$current|"
        stage_copy "$current" /usr/local/lib
        if [ -L "$current" ]; then
            link_target=$(/usr/bin/readlink "$current")
            case "$link_target" in
                ''|*/*) die "unsafe dylib link for $library_name: $link_target" ;;
            esac
            current="$PREFIX/lib/$link_target"
        else
            install_name=$(/usr/bin/otool -D "$current" 2>/dev/null | \
                /usr/bin/sed -n '2p')
            case "$install_name" in
                /usr/local/lib/*.dylib) ;;
                *) break ;;
            esac
            current_name=$(/usr/bin/basename "$current")
            install_name_file=$(/usr/bin/basename "$install_name")
            [ "$current_name" != "$install_name_file" ] || break
            current="$PREFIX/lib/$install_name_file"
        fi
        depth=$((depth + 1))
        [ "$depth" -le 8 ] || die "dylib link loop for $library_name"
        stage_require_file "$current"
    done

    [ ! -f "$PREFIX/lib/$library_name.a" ] || \
        stage_copy "$PREFIX/lib/$library_name.a" /usr/local/lib
    [ ! -f "$PREFIX/lib/$library_name.la" ] || \
        stage_copy "$PREFIX/lib/$library_name.la" /usr/local/lib
}

stage_asset() {
    local asset_name=$1
    local destination=$2
    stage_copy_as "$COMPONENT_DIR/assets/$asset_name" "$destination"
}
