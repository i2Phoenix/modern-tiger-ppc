#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../tiger/common.sh"

require_tiger
ensure_layout

component_list="$PROJECT_ROOT/packaging/components.list"
components_output="$OUTPUT_DIR/components"
packages_output="$OUTPUT_DIR/packages"
metapackage="$packages_output/modern-tiger-ppc-$PROJECT_VERSION.mpkg"
meta_work="$WORK_DIR/metapackage-$PROJECT_VERSION"
refs="$meta_work/package-refs.xml"
outline="$meta_work/choices-outline.xml"
choices="$meta_work/choices.xml"

require_file "$component_list"
reset_work_dir "$meta_work"
/bin/mkdir -p "$packages_output"
case "$metapackage" in "$OUTPUT_DIR"/packages/*.mpkg) ;; *) die "unsafe metapackage path" ;; esac
/bin/rm -rf "$metapackage"
/bin/mkdir -p "$metapackage/Contents/Resources" "$metapackage/Packages"
/bin/cp "$PROJECT_ROOT/LICENSE" \
    "$metapackage/Contents/Resources/LICENSE.txt"
/bin/cp "$PROJECT_ROOT/NOTICE" \
    "$metapackage/Contents/Resources/NOTICE.txt"
: > "$refs"
: > "$outline"
: > "$choices"

while IFS= read -r component; do
    case "$component" in ''|'#'*) continue ;; esac
    metadata="$PROJECT_ROOT/packaging/components/$component/component.conf"
    require_file "$metadata"
    . "$metadata"
    package_name=$PACKAGE_NAME-$PACKAGE_VERSION.pkg
    package_path=$components_output/$package_name
    require_file "$package_path/Contents/Info.plist"
    /bin/cp -R "$package_path" "$metapackage/Packages/"

    package_kb=$(/usr/bin/sed -n \
        's|.*<key>IFPkgFlagInstalledSize</key><integer>\([0-9][0-9]*\)</integer>.*|\1|p' \
        "$package_path/Contents/Info.plist" | /usr/bin/head -1)
    [ -n "$package_kb" ] || die "cannot read installed size from $package_name"

    cat >> "$refs" <<XML
    <pkg-ref id="$BUNDLE_ID" auth="Root" installKBytes="$package_kb" version="$PACKAGE_VERSION">Packages/$package_name</pkg-ref>
XML
    printf '        <line choice="%s-choice"/>\n' "$component" >> "$outline"
    cat >> "$choices" <<XML
    <choice id="$component-choice"
            title="$TITLE"
            description="$DESCRIPTION"
            start_selected="$CHOICE_SELECTED"
            start_enabled="$CHOICE_ENABLED"
            start_visible="$CHOICE_VISIBLE">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>

XML
done < "$component_list"

printf 'pmkrmpkg' > "$metapackage/Contents/PkgInfo"
cat > "$metapackage/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.modern-ppc.tiger</string>
<key>CFBundleShortVersionString</key><string>$PROJECT_VERSION</string>
<key>CFBundleGetInfoString</key><string>modern-tiger-ppc $PROJECT_VERSION</string>
<key>IFMajorVersion</key><integer>1</integer>
<key>IFMinorVersion</key><integer>0</integer>
<key>IFPkgFlagAllowBackRev</key><false/>
<key>IFPkgFlagAuthorizationAction</key><string>RootAuthorization</string>
<key>IFPkgFlagComponentDirectory</key><string>Packages</string>
<key>IFPkgFlagDefaultLocation</key><string>/</string>
<key>IFPkgFlagFollowLinks</key><true/>
<key>IFPkgFlagIsRequired</key><false/>
<key>IFPkgFlagRestartAction</key><string>RequiredRestart</string>
<key>IFPkgFlagRootVolumeOnly</key><true/>
<key>IFPkgFormatVersion</key><real>0.10000000149011612</real>
</dict></plist>
PLIST

cat > "$metapackage/Contents/Resources/Welcome.rtf" <<'RTF'
{\rtf1\ansi\ansicpg1252\cocoartf500
{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
\paperw12240\paperh15840\margl1440\margr1440
\f0\fs26 \b modern-tiger-ppc\b0\
\
Modern TLS, networking tools, and a source-build toolchain for Mac OS X Tiger on PowerPC.\
\
The SecureTransport compatibility shim and root certificate import change system security components. Read the project documentation and keep the rollback tools available.
}
RTF

cat > "$metapackage/Contents/Resources/Conclusion.rtf" <<'RTF'
{\rtf1\ansi\ansicpg1252\cocoartf500
{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
\paperw12240\paperh15840\margl1440\margr1440
\f0\fs26 Installation complete. Restart the Mac before testing system applications.
}
RTF

distribution="$metapackage/Contents/distribution.dist"
cat > "$distribution" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="1">
    <title>modern-tiger-ppc</title>
    <welcome file="Welcome.rtf" mime-type="text/rtf"/>
    <conclusion file="Conclusion.rtf" mime-type="text/rtf"/>
    <options customize="always" require-scripts="false" rootVolumeOnly="true" restart="RequiredRestart"/>
    <installation-check script="modern_tiger_install_check();"/>
    <script><![CDATA[
        function modern_tiger_install_check() {
            if (system.sysctl('hw.machine') != 'Power Macintosh') {
                my.result.type = 'Fatal';
                my.result.title = 'Unsupported architecture';
                my.result.message = 'modern-tiger-ppc requires a PowerPC Mac.';
                return false;
            }
            if (system.compareVersions(system.version.ProductVersion, '10.4.11') != 0) {
                my.result.type = 'Fatal';
                my.result.title = 'Unsupported system';
                my.result.message = 'modern-tiger-ppc requires Mac OS X 10.4.11.';
                return false;
            }
            return true;
        }
        function is_tiger_10411() {
            return system.compareVersions(system.version.ProductVersion, '10.4.11') == 0;
        }
    ]]></script>
XML
/bin/cat "$refs" >> "$distribution"
cat >> "$distribution" <<'XML'
    <choices-outline>
XML
/bin/cat "$outline" >> "$distribution"
cat >> "$distribution" <<'XML'
    </choices-outline>
XML
/bin/cat "$choices" >> "$distribution"
cat >> "$distribution" <<'XML'
</installer-gui-script>
XML

if [ -x /usr/bin/plutil ]; then
    /usr/bin/plutil -lint "$metapackage/Contents/Info.plist"
fi
if [ -x /usr/bin/xmllint ]; then
    /usr/bin/xmllint --noout "$distribution"
fi

log "built $metapackage"
