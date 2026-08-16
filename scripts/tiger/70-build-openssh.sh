#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "openssh-$OPENSSH_VERSION.tar.gz"
require_file "$PROJECT_ROOT/patches/openssh-10.3p1-tiger.patch"
compiler_environment
start_log 70-build-openssh

extract_source "openssh-$OPENSSH_VERSION.tar.gz" "openssh-$OPENSSH_VERSION"
cd "$EXTRACTED_SOURCE"
/usr/bin/patch -p1 -N -r - < "$PROJECT_ROOT/patches/openssh-10.3p1-tiger.patch"

./configure \
    --prefix="$OPENSSH_PREFIX" \
    --sysconfdir=/etc/openssh \
    --with-ssl-dir="$SSL_PREFIX" \
    --with-pam \
    --without-selinux \
    --without-kerberos5 \
    --disable-strip \
    --with-privsep-user=nobody \
    --with-privsep-path=/var/empty \
    --with-sandbox=no \
    --with-pid-dir=/var/run \
    CC="$GCC" \
    CPPFLAGS="-I$SSL_PREFIX/include -I/usr/include/pam" \
    CFLAGS="-O2 -mcpu=970 -B $PREFIX/libexec/tiger-ld/" \
    LDFLAGS="-L$SSL_PREFIX/lib -L$GCC_LIB -L$PREFIX/lib -B $PREFIX/libexec/tiger-ld/" \
    LIBS="-latomic -lpam"

/usr/bin/perl -pi -e \
    's|^LIBS=-latomic -lpam$|LIBS=-latomic -lpam -framework CoreFoundation|; s|^SSHDLIBS= -lpam -ldl$|SSHDLIBS= -lpam -ldl -framework CoreFoundation|' \
    Makefile

make -j"$JOBS" CC="$GCC"
run_root make install-nokeys
"$OPENSSH_PREFIX/sbin/sshd" -V 2>&1 | head -1
/usr/bin/otool -L "$OPENSSH_PREFIX/sbin/sshd" | grep -Ei 'pam|CoreFoundation|crypto|ssl'
log "OpenSSH $OPENSSH_VERSION installed under $OPENSSH_PREFIX; service was not changed"

