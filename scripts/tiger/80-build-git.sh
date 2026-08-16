#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "git-$GIT_VERSION.tar.xz"
require_file "$PROJECT_ROOT/patches/git-2.53.0-tiger.patch"
require_file "$PREFIX/bin/make"
require_file "$PERL_PREFIX/bin/perl"
compiler_environment
start_log 80-build-git

extract_source "git-$GIT_VERSION.tar.xz" "git-$GIT_VERSION"
cd "$EXTRACTED_SOURCE"
/usr/bin/patch -p1 -N -r - < "$PROJECT_ROOT/patches/git-2.53.0-tiger.patch"

cat > config.mak <<CFG
prefix=$GIT_PREFIX
CC=$GCC
CFLAGS=-O2 -mcpu=970 -I$PREFIX/include -I$SSL_PREFIX/include -B $PREFIX/libexec/tiger-ld/
LDFLAGS=-L$PREFIX/lib -L$SSL_PREFIX/lib -L$GCC_LIB -B $PREFIX/libexec/tiger-ld/
OPENSSLDIR=$SSL_PREFIX
CURL_CONFIG=$PREFIX/bin/curl-config
EXPATDIR=$PREFIX
NO_GETTEXT=1
NO_TCLTK=1
NO_INSTALL_HARDLINKS=1
PERL_PATH=$PERL_PREFIX/bin/perl
USE_LIBPCRE=
NO_PERL_CPAN_FALLBACKS=1
NO_SYS_POLL_H=1
CFG

# GNU Make 4.4.1 can miss SIGCHLD wakeups on Tiger PPC. The watchdog only
# nudges this build process and exits as soon as make finishes.
set +e
"$PREFIX/bin/make" -j"$JOBS" all &
make_pid=$!
(
    while /bin/kill -0 "$make_pid" >/dev/null 2>&1; do
        /bin/kill -CHLD "$make_pid" >/dev/null 2>&1 || true
        /bin/sleep 30
    done
) &
watchdog_pid=$!
wait "$make_pid"
make_status=$?
/bin/kill "$watchdog_pid" >/dev/null 2>&1 || true
wait "$watchdog_pid" >/dev/null 2>&1 || true
set -e
[ "$make_status" -eq 0 ] || die "Git build failed with status $make_status"

run_root "$PREFIX/bin/make" install
"$GIT_PREFIX/bin/git" --version
log "Git $GIT_VERSION installed"

