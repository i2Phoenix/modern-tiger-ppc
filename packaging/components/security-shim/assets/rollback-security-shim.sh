#!/bin/bash

set -e

directory=/System/Library/Frameworks/Security.framework/Versions/A
active=$directory/Security
pristine=$directory/Security.pristine
temporary=$directory/.Security.rollback.$$

[ -f "$pristine" ] || { echo "missing rollback file: $pristine" >&2; exit 1; }
/bin/cp -p "$pristine" "$temporary"
/usr/sbin/chown root:wheel "$temporary"
/bin/chmod 755 "$temporary"
/bin/mv -f "$temporary" "$active"
/usr/bin/otool -D "$active"
echo '[modern-tiger-ppc] restored the pristine Tiger Security framework; restart required'
exit 0
