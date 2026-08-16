#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../lib/host-common.sh"

failures=0
lint_work="$PROJECT_ROOT/.work/lint"
mkdir -p "$lint_work"

log "checking shell syntax"
find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/packaging" "$PROJECT_ROOT/tools" \
    -type f \( -name '*.sh' -o -name 'ld' -o -name preflight -o -name postflight \) \
    -print | LC_ALL=C sort | while IFS= read -r script; do
        /bin/bash -n "$script" || exit 1
    done || failures=$((failures + 1))

log "checking executable bits"
find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/packaging" "$PROJECT_ROOT/tools" \
    -type f \( -name '*.sh' -o -name 'ld' -o -name preflight -o -name postflight \) \
    ! -perm -u+x -print | while IFS= read -r script; do
        printf 'not executable: %s\n' "$script" >&2
        exit 1
    done || failures=$((failures + 1))

log "checking for forbidden artifacts"
if find "$PROJECT_ROOT" \
    \( -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/.work" -o -path "$PROJECT_ROOT/cache" -o -path "$PROJECT_ROOT/dist" \) -prune -o \
    \( -name '.DS_Store' -o -name '._*' -o -name '*.pkg' -o -name '*.mpkg' \
       -o -name '*.dmg' -o -name 'Security.pristine' -o -name 'Security.new' \
       -o -name 'SecurityBackup.framework' -o -name '*.dylib' -o -name '*.a' \
       -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \
       -o -name '*.tar.bz2' -o -name '*.tar.xz' -o -name '*.zip' \) \
    -print | grep . >/dev/null 2>&1; then
    find "$PROJECT_ROOT" \
        \( -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/.work" -o -path "$PROJECT_ROOT/cache" -o -path "$PROJECT_ROOT/dist" \) -prune -o \
        \( -name '.DS_Store' -o -name '._*' -o -name '*.pkg' -o -name '*.mpkg' \
           -o -name '*.dmg' -o -name 'Security.pristine' -o -name 'Security.new' \
           -o -name 'SecurityBackup.framework' -o -name '*.dylib' -o -name '*.a' \
           -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \
           -o -name '*.tar.bz2' -o -name '*.tar.xz' -o -name '*.zip' \) \
        -print >&2
    failures=$((failures + 1))
fi

log "checking for credential-bearing patterns"
credential_pattern='(ssh''pass|TARGET_''PASS|PASS''=|PW''=|Password'':[[:space:]]*[^<]|BEGIN [A-Z ]*PRIVATE KEY|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|/Users/[A-Za-z0-9._-]+/)'
credential_hits="$lint_work/credential-files.txt"
: > "$credential_hits"
find "$PROJECT_ROOT" \
    \( -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/.work" -o \
       -path "$PROJECT_ROOT/cache" -o -path "$PROJECT_ROOT/dist" \) -prune -o \
    -type f ! -path "$PROJECT_ROOT/.env" \
    ! -path "$PROJECT_ROOT/config/target.env" -print0 | \
    xargs -0 grep -IlE "$credential_pattern" \
    >> "$credential_hits" 2>/dev/null || true
if [ -s "$credential_hits" ]; then
    /usr/bin/sed 's|^|credential-bearing pattern in: |' \
        "$credential_hits" >&2
    failures=$((failures + 1))
fi

log "checking that local configuration is not tracked"
if command -v git >/dev/null 2>&1 && \
    git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    tracked_local=$(git -C "$PROJECT_ROOT" ls-files -- \
        .env config/target.env)
    if [ -n "$tracked_local" ]; then
        printf 'local configuration is tracked:\n%s\n' "$tracked_local" >&2
        failures=$((failures + 1))
    fi
fi

log "checking for committed Mach-O files"
find "$PROJECT_ROOT" \
    \( -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/.work" -o -path "$PROJECT_ROOT/cache" -o -path "$PROJECT_ROOT/dist" \) -prune -o \
    -type f -print | while IFS= read -r candidate; do
        if file "$candidate" 2>/dev/null | grep -q 'Mach-O'; then
            printf 'committed binary: %s\n' "$candidate" >&2
            exit 1
        fi
    done || failures=$((failures + 1))

log "checking component metadata"
if [ -d "$PROJECT_ROOT/packaging/components" ]; then
    component_count=0
    for component in "$PROJECT_ROOT"/packaging/components/*; do
        [ -d "$component" ] || continue
        component_count=$((component_count + 1))
        [ -f "$component/component.conf" ] || { echo "missing component.conf: $component" >&2; failures=$((failures + 1)); }
        [ -x "$component/stage.sh" ] || { echo "missing executable stage.sh: $component" >&2; failures=$((failures + 1)); }
    done
    [ "$component_count" -eq 11 ] || { echo "expected 11 component directories, found $component_count" >&2; failures=$((failures + 1)); }
fi

log "checking package selection safety"
. "$PROJECT_ROOT/config/versions.conf"
while IFS= read -r selected_component; do
    case "$selected_component" in ''|'#'*) continue ;; esac
    . "$PROJECT_ROOT/packaging/components/$selected_component/component.conf"
    if [ "$CHOICE_SELECTED" != true ]; then
        echo "component must be selected by default: $selected_component" >&2
        failures=$((failures + 1))
    fi
done < "$PROJECT_ROOT/packaging/components.list"
for required_component in gcc7 syslibs perl openssl curl; do
    . "$PROJECT_ROOT/packaging/components/$required_component/component.conf"
    if [ "$REQUIRED" != true ] || [ "$CHOICE_SELECTED" != true ] || \
        [ "$CHOICE_ENABLED" != false ]; then
        echo "runtime dependency must be required: $required_component" >&2
        failures=$((failures + 1))
    fi
done
. "$PROJECT_ROOT/packaging/components/security-shim/component.conf"
if [ "$REQUIRED" != false ] || [ "$CHOICE_SELECTED" != true ] || \
    [ "$CHOICE_ENABLED" != true ]; then
    echo "security-shim must be selected by default" >&2
    failures=$((failures + 1))
fi

log "checking project license and attribution"
if [ ! -f "$PROJECT_ROOT/LICENSE" ] || \
    ! /usr/bin/grep -Fxq 'MIT License' "$PROJECT_ROOT/LICENSE" || \
    ! /usr/bin/grep -Fxq 'Copyright (c) 2026 Modern Tiger Project' \
        "$PROJECT_ROOT/LICENSE"; then
    echo "canonical MIT LICENSE is missing or invalid" >&2
    failures=$((failures + 1))
fi
if [ ! -f "$PROJECT_ROOT/NOTICE" ] || \
    ! /usr/bin/grep -Fq 'modern-tiger-ppc' "$PROJECT_ROOT/NOTICE"; then
    echo "NOTICE must identify the original modern-tiger-ppc project" >&2
    failures=$((failures + 1))
fi

log "checking source lock metadata"
if ! awk -F '|' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    NF != 3 { bad=1; print "invalid source row: " $0 > "/dev/stderr"; next }
    $1 ~ /\// || $1 == ".." { bad=1; print "unsafe source name: " $1 > "/dev/stderr" }
    $2 !~ /^https:\/\// { bad=1; print "non-HTTPS source URL: " $2 > "/dev/stderr" }
    $3 != "-" && (length($3) != 64 || $3 !~ /^[0-9a-f]+$/) {
        bad=1; print "invalid SHA-256 for " $1 > "/dev/stderr"
    }
    seen[$1]++ { bad=1; print "duplicate source name: " $1 > "/dev/stderr" }
    END { exit bad }
' "$PROJECT_ROOT/config/sources.conf"; then
    failures=$((failures + 1))
fi

log "checking shim export declaration"
awk '$1 == "OSStatus" && $2 ~ /^SSL/ {
    name=$2; sub(/\(.*/, "", name); print "_" name
}' "$PROJECT_ROOT/shim/securetransport_shim.c" | LC_ALL=C sort \
    > "$lint_work/source-shim-exports.txt"
LC_ALL=C sort "$PROJECT_ROOT/shim/shim_exports.txt" \
    > "$lint_work/declared-shim-exports.txt"
if ! cmp -s "$lint_work/source-shim-exports.txt" \
    "$lint_work/declared-shim-exports.txt"; then
    diff -u "$lint_work/declared-shim-exports.txt" \
        "$lint_work/source-shim-exports.txt" >&2 || true
    failures=$((failures + 1))
fi
if LC_ALL=C sort "$PROJECT_ROOT/shim/shim_exports.txt" | uniq -d | grep .; then
    failures=$((failures + 1))
fi
overlapping_exports="$lint_work/overlapping-shim-exports.txt"
awk 'NR == FNR { declared[$0]=1; next } ($0 in declared) { print }' \
    "$lint_work/declared-shim-exports.txt" \
    "$PROJECT_ROOT/shim/shim_unexports.txt" > "$overlapping_exports"
if [ -s "$overlapping_exports" ]; then
    /bin/cat "$overlapping_exports" >&2
    failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || die "$failures lint check(s) failed"
log "lint OK"
