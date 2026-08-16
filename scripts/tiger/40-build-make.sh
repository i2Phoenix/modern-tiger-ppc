#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
require_source "make-$MAKE_VERSION.tar.gz"
compiler_environment
start_log 40-build-make

extract_source "make-$MAKE_VERSION.tar.gz" "make-$MAKE_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" CC="$GCC" CFLAGS="-O2 -mcpu=970"
/usr/bin/make -j"$JOBS"
run_root /usr/bin/make install
"$PREFIX/bin/make" --version | head -1
log "GNU Make $MAKE_VERSION installed"

