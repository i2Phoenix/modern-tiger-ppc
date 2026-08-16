#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "perl-$PERL_VERSION.tar.gz"
compiler_environment
start_log 30-build-perl

extract_source "perl-$PERL_VERSION.tar.gz" "perl-$PERL_VERSION"
cd "$EXTRACTED_SOURCE"
./Configure -des \
    -Dprefix="$PERL_PREFIX" \
    -Dcc="$GCC" \
    -Doptimize="-O2 -mcpu=970" \
    -Dldflags="-B $PREFIX/libexec/tiger-ld/" \
    -Duseshrplib \
    -Dusethreads
make -j"$JOBS"
run_root make install
"$PERL_PREFIX/bin/perl" --version | head -2
log "Perl $PERL_VERSION installed"

