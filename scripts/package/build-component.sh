#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../tiger/common.sh"

require_tiger
require_command /bin/pax
require_command /usr/bin/mkbom
ensure_layout
[ "$PREFIX" = /usr/local ] || die "packages require the canonical PREFIX=/usr/local"

component=${1:-}
case "$component" in
    ''|*/*|*..*|*[!A-Za-z0-9._-]*) die "invalid component name: $component" ;;
esac

COMPONENT_DIR="$PROJECT_ROOT/packaging/components/$component"
metadata="$COMPONENT_DIR/component.conf"
stage_script="$COMPONENT_DIR/stage.sh"
require_file "$metadata"
require_file "$stage_script"
. "$metadata"

for required_value in PACKAGE_NAME PACKAGE_VERSION BUNDLE_ID TITLE DESCRIPTION \
    REQUIRED CHOICE_SELECTED CHOICE_ENABLED CHOICE_VISIBLE; do
    eval value=\${$required_value:-}
    [ -n "$value" ] || die "$metadata does not define $required_value"
done

RESTART_ACTION=${RESTART_ACTION:-NoRestart}
STAGE="$PACKAGE_STAGE_DIR/$PACKAGE_NAME"
components_output="$OUTPUT_DIR/components"
package="$components_output/$PACKAGE_NAME-$PACKAGE_VERSION.pkg"

case "$STAGE" in "$PACKAGE_STAGE_DIR"/*) ;; *) die "unsafe package stage" ;; esac
case "$package" in "$OUTPUT_DIR"/components/*.pkg) ;; *) die "unsafe package output" ;; esac

run_root /bin/rm -rf "$STAGE"
/bin/mkdir -p "$STAGE" "$components_output"

export COMPONENT_DIR STAGE
log "staging $PACKAGE_NAME $PACKAGE_VERSION"
/bin/bash "$stage_script"

payload_found=false
for payload_entry in "$STAGE"/* "$STAGE"/.[!.]* "$STAGE"/..?*; do
    if [ -e "$payload_entry" ] || [ -L "$payload_entry" ]; then
        payload_found=true
        break
    fi
done
[ "$payload_found" = true ] || die "$PACKAGE_NAME produced an empty payload"

for payload_entry in "$STAGE"/*; do
    [ -e "$payload_entry" ] || [ -L "$payload_entry" ] || continue
    [ "$(/usr/bin/basename "$payload_entry")" = usr ] || \
        die "$PACKAGE_NAME staged a top-level path other than /usr: $payload_entry"
done

# Installer must lay down system files as root:wheel. Symlinks are skipped so
# an absolute staged link can never cause chown to escape the staging tree.
run_root /usr/bin/find "$STAGE" \( -type d -o -type f \) \
    -exec /usr/sbin/chown root:wheel '{}' ';'
run_root /usr/bin/find "$STAGE" -type l \
    -exec /usr/sbin/chown -h root:wheel '{}' ';'

/bin/rm -rf "$package"
/bin/mkdir -p "$package/Contents/Resources"
(cd "$STAGE" && run_root /usr/bin/env COPYFILE_DISABLE=true /bin/pax -wz \
    -f "$package/Contents/Archive.pax.gz" .)
run_root /usr/bin/mkbom "$STAGE" "$package/Contents/Archive.bom"

/bin/cp "$PROJECT_ROOT/packaging/common/preflight" \
    "$package/Contents/Resources/preflight"
/bin/cp "$PROJECT_ROOT/LICENSE" "$package/Contents/Resources/LICENSE.txt"
/bin/cp "$PROJECT_ROOT/NOTICE" "$package/Contents/Resources/NOTICE.txt"
if [ -f "$COMPONENT_DIR/postflight" ]; then
    /bin/cp "$COMPONENT_DIR/postflight" "$package/Contents/Resources/postflight"
fi
/bin/chmod 755 "$package/Contents/Resources/preflight"
[ ! -f "$package/Contents/Resources/postflight" ] || \
    /bin/chmod 755 "$package/Contents/Resources/postflight"

payload_kb=$(/usr/bin/du -sk "$STAGE" | /usr/bin/awk '{print $1}')
payload_files=$(/usr/bin/find "$STAGE" -type f | /usr/bin/wc -l | /usr/bin/awk '{print $1}')
printf 'pmkrpkg1' > "$package/Contents/PkgInfo"

cat > "$package/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleShortVersionString</key><string>$PACKAGE_VERSION</string>
<key>CFBundleGetInfoString</key><string>$TITLE $PACKAGE_VERSION</string>
<key>IFMajorVersion</key><integer>1</integer>
<key>IFMinorVersion</key><integer>0</integer>
<key>IFPkgFlagAllowBackRev</key><false/>
<key>IFPkgFlagAuthorizationAction</key><string>RootAuthorization</string>
<key>IFPkgFlagDefaultLocation</key><string>/</string>
<key>IFPkgFlagFollowLinks</key><true/>
<key>IFPkgFlagInstallFat</key><false/>
<key>IFPkgFlagInstalledSize</key><integer>$payload_kb</integer>
<key>IFPkgFlagIsRequired</key><$REQUIRED/>
<key>IFPkgFlagOverwritePermissions</key><false/>
<key>IFPkgFlagRelocatable</key><false/>
<key>IFPkgFlagRestartAction</key><string>$RESTART_ACTION</string>
<key>IFPkgFlagRootVolumeOnly</key><true/>
<key>IFPkgFlagUpdateInstalledLanguages</key><false/>
<key>IFPkgFormatVersion</key><real>0.10000000149011612</real>
</dict></plist>
PLIST

cat > "$package/Contents/Resources/Description.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>IFPkgDescriptionTitle</key><string>$TITLE</string>
<key>IFPkgDescriptionVersion</key><string>$PACKAGE_VERSION</string>
<key>IFPkgDescriptionDescription</key><string>$DESCRIPTION</string>
</dict></plist>
PLIST

if [ -x /usr/bin/plutil ]; then
    /usr/bin/plutil -lint "$package/Contents/Info.plist" \
        "$package/Contents/Resources/Description.plist"
fi

log "built $package ($payload_kb KB, $payload_files files)"
