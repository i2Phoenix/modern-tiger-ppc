#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/common.sh"

require_tiger
ensure_layout
for archive in \
    "zlib-$ZLIB_VERSION.tar.gz" \
    "xz-$XZ_VERSION.tar.gz" \
    "pkgconf-$PKGCONF_VERSION.tar.xz" \
    "libffi-$LIBFFI_VERSION.tar.gz" \
    "expat-$EXPAT_VERSION.tar.xz" \
    "sqlite-autoconf-$SQLITE_AUTOCONF_VERSION.tar.gz" \
    "readline-$READLINE_VERSION.tar.gz"; do
    require_source "$archive"
done
compiler_environment
start_log 20-build-syslibs

extract_source "zlib-$ZLIB_VERSION.tar.gz" "zlib-$ZLIB_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX"
make -j"$JOBS"
run_root make install

extract_source "xz-$XZ_VERSION.tar.gz" "xz-$XZ_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" --disable-nls --disable-doc
make -j"$JOBS"
run_root make install

extract_source "pkgconf-$PKGCONF_VERSION.tar.xz" "pkgconf-$PKGCONF_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" --with-system-libdir="$PREFIX/lib"
make -j"$JOBS"
run_root make install
run_root ln -sfn pkgconf "$PREFIX/bin/pkg-config"

extract_source "libffi-$LIBFFI_VERSION.tar.gz" "libffi-$LIBFFI_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" --disable-docs --disable-multi-os-directory
make -j"$JOBS"
run_root make install

extract_source "expat-$EXPAT_VERSION.tar.xz" "expat-$EXPAT_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" --without-docbook --without-examples --without-tests
make -j"$JOBS"
run_root make install

extract_source "sqlite-autoconf-$SQLITE_AUTOCONF_VERSION.tar.gz" \
    "sqlite-autoconf-$SQLITE_AUTOCONF_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" --disable-readline --enable-threadsafe \
    --enable-fts5 --enable-rtree \
    CFLAGS="$CFLAGS -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_STAT4"
make -j"$JOBS"
run_root make install

extract_source "readline-$READLINE_VERSION.tar.gz" "readline-$READLINE_VERSION"
cd "$EXTRACTED_SOURCE"
./configure --prefix="$PREFIX" --enable-shared --enable-static
make -j"$JOBS"
run_root make install

"$PREFIX/bin/pkgconf" --version
"$PREFIX/bin/pkgconf" --modversion libpkgconf libffi expat liblzma sqlite3 readline zlib
/usr/bin/otool -L "$PREFIX/bin/pkgconf" | grep libpkgconf
test -f "$PREFIX/lib/libpkgconf.5.dylib"
log "foundation libraries installed"
