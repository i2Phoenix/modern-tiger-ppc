#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

stage_require_dir "$GIT_PREFIX"
stage_copy "$GIT_PREFIX" /usr/local
