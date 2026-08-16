#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_dir "$PERL_PREFIX"
stage_copy "$PERL_PREFIX" /usr/local
