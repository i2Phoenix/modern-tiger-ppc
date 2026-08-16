#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_file "$PREFIX/bin/curl"
stage_copy "$PREFIX/bin/curl" /usr/local/bin
stage_copy_library_family libcurl
stage_require_dir "$PREFIX/include/curl"
stage_copy "$PREFIX/include/curl" /usr/local/include
[ ! -f "$PREFIX/lib/pkgconfig/libcurl.pc" ] || \
    stage_copy "$PREFIX/lib/pkgconfig/libcurl.pc" /usr/local/lib/pkgconfig
stage_copy_optional_matches "$PREFIX/share/man/man1/curl*" /usr/local/share/man/man1
