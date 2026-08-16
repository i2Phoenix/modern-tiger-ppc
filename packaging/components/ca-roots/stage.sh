#!/bin/bash

set -e
. "$PROJECT_ROOT/scripts/package/stage-common.sh"

roots="$SSL_PREFIX/certs/modern-roots"
stage_require_dir "$roots"
stage_copy "$roots" /usr/local/ssl/certs
