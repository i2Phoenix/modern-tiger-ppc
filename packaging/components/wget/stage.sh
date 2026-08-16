#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_file "$PREFIX/bin/wget"
stage_copy "$PREFIX/bin/wget" /usr/local/bin
[ ! -f "$PREFIX/etc/wgetrc" ] || stage_copy "$PREFIX/etc/wgetrc" /usr/local/etc
stage_copy_optional_matches "$PREFIX/share/man/man1/wget*" /usr/local/share/man/man1
stage_copy_optional_matches "$PREFIX/share/info/wget.info*" /usr/local/share/info
