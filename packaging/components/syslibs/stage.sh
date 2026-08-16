#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_file "$PREFIX/bin/pkgconf"
stage_require_file "$PREFIX/lib/libpkgconf.5.dylib"

for library in libpkgconf libffi libexpat liblzma libsqlite3 libreadline \
    libhistory libz; do
    stage_copy_library_family "$library"
done

for header in ffi.h ffi_common.h ffitarget.h expat.h expat_external.h \
    lzma.h sqlite3.h sqlite3ext.h zlib.h zconf.h; do
    [ ! -f "$PREFIX/include/$header" ] || \
        stage_copy "$PREFIX/include/$header" /usr/local/include
done
for header_dir in lzma readline pkgconf; do
    [ ! -d "$PREFIX/include/$header_dir" ] || \
        stage_copy "$PREFIX/include/$header_dir" /usr/local/include
done

for binary in pkgconf pkg-config bomtool xz xzcat unxz xzdec lzma unlzma lzcat sqlite3; do
    if [ -e "$PREFIX/bin/$binary" ] || [ -L "$PREFIX/bin/$binary" ]; then
        stage_copy "$PREFIX/bin/$binary" /usr/local/bin
    fi
done

for pc in libpkgconf libffi expat liblzma sqlite3 readline history zlib; do
    [ ! -f "$PREFIX/lib/pkgconfig/$pc.pc" ] || \
        stage_copy "$PREFIX/lib/pkgconfig/$pc.pc" /usr/local/lib/pkgconfig
done

stage_copy_optional_matches "$PREFIX/share/man/man1/xz*" /usr/local/share/man/man1
stage_copy_optional_matches "$PREFIX/share/man/man1/sqlite3*" /usr/local/share/man/man1
stage_copy_optional_matches "$PREFIX/share/man/man1/pkgconf*" /usr/local/share/man/man1
stage_copy_optional_matches "$PREFIX/share/man/man5/pc.5" /usr/local/share/man/man5
stage_copy_optional_matches "$PREFIX/share/man/man5/pkgconf-personality.5" /usr/local/share/man/man5
stage_copy_optional_matches "$PREFIX/share/man/man7/pkg.m4.7" /usr/local/share/man/man7
stage_copy_optional_matches "$PREFIX/share/man/man3/zlib*" /usr/local/share/man/man3
[ ! -d "$PREFIX/share/doc/pkgconf" ] || \
    stage_copy "$PREFIX/share/doc/pkgconf" /usr/local/share/doc
[ ! -f "$PREFIX/share/aclocal/pkg.m4" ] || \
    stage_copy "$PREFIX/share/aclocal/pkg.m4" /usr/local/share/aclocal

stage_require_file "$STAGE/usr/local/lib/libpkgconf.5.dylib"
