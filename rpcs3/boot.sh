#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Main directory
export DIR_RPCS3="$SCRIPT_DIR"

# Use included libs
export LD_LIBRARY_PATH="$DIR_RPCS3/lib:$LD_LIBRARY_PATH"

# Start
"$DIR_RPCS3"/bin/rpcs3 "$@"
