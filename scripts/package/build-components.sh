#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/../tiger/common.sh"

require_tiger
component_list="$PROJECT_ROOT/packaging/components.list"
require_file "$component_list"

while IFS= read -r component; do
    case "$component" in ''|'#'*) continue ;; esac
    /bin/bash "$SCRIPT_DIR/build-component.sh" "$component"
done < "$component_list"

log "all component packages built under $OUTPUT_DIR/components"
