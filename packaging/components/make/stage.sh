#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_file "$PREFIX/bin/make"
stage_copy "$PREFIX/bin/make" /usr/local/bin
stage_copy_optional_matches "$PREFIX/share/man/man1/make*" /usr/local/share/man/man1
stage_copy_optional_matches "$PREFIX/share/info/make.info*" /usr/local/share/info
