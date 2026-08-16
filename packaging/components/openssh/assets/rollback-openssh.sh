#!/bin/bash

set -e

plist=/System/Library/LaunchDaemons/ssh.plist
backup=$plist.apple-5.1p1
[ -f "$backup" ] || { echo "missing rollback file: $backup" >&2; exit 1; }

/bin/launchctl unload "$plist" >/dev/null 2>&1 || true
/bin/cp -p "$backup" "$plist"
/usr/sbin/chown root:wheel "$plist"
/bin/chmod 644 "$plist"

for name in ssh scp sftp ssh-add ssh-agent ssh-keygen ssh-keyscan; do
    destination=/usr/bin/$name
    saved=/usr/bin/originals/$name.apple-tiger
    legacy=/usr/bin/originals/$name.apple-5.1p1
    [ -f "$saved" ] || saved=$legacy
    if [ -f "$saved" ]; then
        /bin/rm -f "$destination"
        /bin/cp -p "$saved" "$destination"
    elif [ -L "$destination" ]; then
        /bin/rm -f "$destination"
    fi
done

/bin/launchctl load -w "$plist"
echo '[modern-tiger-ppc] restored the Apple Tiger SSH service and clients'
exit 0
