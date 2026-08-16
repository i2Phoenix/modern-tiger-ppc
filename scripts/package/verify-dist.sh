#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../tiger/common.sh"

require_tiger
require_command /bin/pax
require_command /usr/bin/otool
require_command /usr/bin/file
ensure_layout

component_list="$PROJECT_ROOT/packaging/components.list"
components_output="$OUTPUT_DIR/components"
verify_work="$WORK_DIR/verify-dist"
missing_dependencies="$verify_work/missing-dylib-dependencies.txt"
component_count=0

require_file "$component_list"
reset_work_dir "$verify_work"
: > "$missing_dependencies"

while IFS= read -r component; do
    case "$component" in ''|'#'*) continue ;; esac
    metadata="$PROJECT_ROOT/packaging/components/$component/component.conf"
    require_file "$metadata"
    . "$metadata"
    package="$components_output/$PACKAGE_NAME-$PACKAGE_VERSION.pkg"
    require_file "$package/Contents/Archive.pax.gz"
    require_file "$package/Contents/Archive.bom"
    require_file "$package/Contents/Info.plist"
    require_file "$package/Contents/PkgInfo"
    require_file "$package/Contents/Resources/preflight"
    require_file "$package/Contents/Resources/LICENSE.txt"
    require_file "$package/Contents/Resources/NOTICE.txt"
    /usr/bin/grep -Fxq 'Copyright (c) 2026 Modern Tiger Project' \
        "$package/Contents/Resources/LICENSE.txt" || \
        die "invalid project license in $package"
    /usr/bin/grep -Fq 'modern-tiger-ppc' \
        "$package/Contents/Resources/NOTICE.txt" || \
        die "invalid project notice in $package"
    /bin/bash -n "$package/Contents/Resources/preflight"
    [ ! -f "$package/Contents/Resources/postflight" ] || \
        /bin/bash -n "$package/Contents/Resources/postflight"
    [ "$(/bin/cat "$package/Contents/PkgInfo")" = pmkrpkg1 ] || \
        die "invalid PkgInfo in $package"

    manifest="$verify_work/$component.manifest"
    /bin/pax -zf "$package/Contents/Archive.pax.gz" > "$manifest"
    if /usr/bin/grep -E '(\.\._|SecurityBackup\.framework|Security\.pristine|ssh_host_(rsa|ed25519)_key$)' \
        "$manifest" >/dev/null 2>&1; then
        /usr/bin/grep -E '(\.\._|SecurityBackup\.framework|Security\.pristine|ssh_host_(rsa|ed25519)_key$)' \
            "$manifest" >&2
        die "forbidden payload content in $package"
    fi
    component_count=$((component_count + 1))
done < "$component_list"

[ "$component_count" -eq 11 ] || die "expected 11 components, found $component_count"
require_file "$PACKAGE_STAGE_DIR/modern-tiger-ppc-syslibs/usr/local/lib/libpkgconf.5.dylib"

aggregate_has_path() {
    local wanted_path=$1
    local search_component
    local search_metadata
    local search_stage
    local PACKAGE_NAME PACKAGE_VERSION BUNDLE_ID TITLE DESCRIPTION
    local REQUIRED CHOICE_SELECTED CHOICE_ENABLED CHOICE_VISIBLE RESTART_ACTION
    while IFS= read -r search_component; do
        case "$search_component" in ''|'#'*) continue ;; esac
        search_metadata="$PROJECT_ROOT/packaging/components/$search_component/component.conf"
        . "$search_metadata"
        search_stage=$PACKAGE_STAGE_DIR/$PACKAGE_NAME
        if [ -e "$search_stage$wanted_path" ] || [ -L "$search_stage$wanted_path" ]; then
            return 0
        fi
    done < "$component_list"
    return 1
}

# Check every packaged Mach-O against the aggregate payload. This catches a
# binary that works on the build host only because an unshipped dylib is still
# present under /usr/local.
while IFS= read -r binary_component; do
    case "$binary_component" in ''|'#'*) continue ;; esac
    . "$PROJECT_ROOT/packaging/components/$binary_component/component.conf"
    binary_stage=$PACKAGE_STAGE_DIR/$PACKAGE_NAME
    /usr/bin/find "$binary_stage" -type f -print | while IFS= read -r binary; do
        if ! /usr/bin/file "$binary" | /usr/bin/grep -q 'Mach-O'; then
            continue
        fi
        if ! /usr/bin/file "$binary" | /usr/bin/grep -q 'ppc'; then
            printf '%s: not a PowerPC Mach-O\n' "$binary" >> "$missing_dependencies"
        fi
        /usr/bin/otool -L "$binary" 2>/dev/null | /usr/bin/awk 'NR > 1 {print $1}' | \
            while IFS= read -r dependency; do
                case "$dependency" in
                    /usr/local/*)
                        if ! aggregate_has_path "$dependency"; then
                            printf '%s: missing %s\n' "$binary" "$dependency" \
                                >> "$missing_dependencies"
                        fi
                        ;;
                    /Users/*|/private/tmp/*|/tmp/*)
                        printf '%s: build-path dependency %s\n' "$binary" "$dependency" \
                            >> "$missing_dependencies"
                        ;;
                esac
            done
    done
done < "$component_list"

# Validate symlinks independently. An archive entry is not sufficient if its
# target was accidentally left behind on the build host.
while IFS= read -r link_component; do
    case "$link_component" in ''|'#'*) continue ;; esac
    . "$PROJECT_ROOT/packaging/components/$link_component/component.conf"
    link_stage=$PACKAGE_STAGE_DIR/$PACKAGE_NAME
    link_stage_real=$(cd "$link_stage" && /bin/pwd -P)
    /usr/bin/find "$link_stage" -type l -print | while IFS= read -r link_path; do
        link_target=$(/usr/bin/readlink "$link_path")
        case "$link_target" in
            /usr/local/*)
                if ! aggregate_has_path "$link_target"; then
                    printf '%s: missing symlink target %s\n' "$link_path" "$link_target" \
                        >> "$missing_dependencies"
                fi
                ;;
            /Users/*|/private/tmp/*|/tmp/*)
                printf '%s: build-path symlink %s\n' "$link_path" "$link_target" \
                    >> "$missing_dependencies"
                ;;
            /*) ;;
            '')
                printf '%s: empty symlink target\n' "$link_path" \
                    >> "$missing_dependencies"
                ;;
            *)
                link_directory=$(/usr/bin/dirname "$link_path")
                target_directory=$(/usr/bin/dirname "$link_target")
                if ! target_directory_real=$(cd "$link_directory/$target_directory" \
                    2>/dev/null && /bin/pwd -P); then
                    printf '%s: missing relative symlink target %s\n' \
                        "$link_path" "$link_target" >> "$missing_dependencies"
                    continue
                fi
                case "$target_directory_real/" in
                    "$link_stage_real"/*) ;;
                    *)
                        printf '%s: relative symlink escapes payload: %s\n' \
                            "$link_path" "$link_target" >> "$missing_dependencies"
                        continue
                        ;;
                esac
                relative_target="$target_directory_real/$(/usr/bin/basename "$link_target")"
                if [ ! -e "$relative_target" ] && [ ! -L "$relative_target" ]; then
                    printf '%s: missing relative symlink target %s\n' \
                        "$link_path" "$link_target" >> "$missing_dependencies"
                fi
                ;;
        esac
    done
done < "$component_list"

if [ -s "$missing_dependencies" ]; then
    /bin/cat "$missing_dependencies" >&2
    die "packaged Mach-O dependency validation failed"
fi

metapackage="$OUTPUT_DIR/packages/modern-tiger-ppc-$PROJECT_VERSION.mpkg"
if [ -d "$metapackage" ]; then
    require_file "$metapackage/Contents/distribution.dist"
    require_file "$metapackage/Contents/Resources/LICENSE.txt"
    require_file "$metapackage/Contents/Resources/NOTICE.txt"
    [ "$(/bin/cat "$metapackage/Contents/PkgInfo")" = pmkrmpkg ] || \
        die "invalid metapackage PkgInfo"
    packaged_count=0
    for child_package in "$metapackage"/Packages/*.pkg; do
        [ -d "$child_package" ] || continue
        packaged_count=$((packaged_count + 1))
    done
    [ "$packaged_count" -eq "$component_count" ] || \
        die "metapackage contains $packaged_count of $component_count components"
fi

log "package verification OK: $component_count components"
