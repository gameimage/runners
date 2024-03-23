#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Main directory
export DIR_PCSX2="$SCRIPT_DIR"

# Use included libs
export LD_LIBRARY_PATH="$DIR_PCSX2/lib:$LD_LIBRARY_PATH"

# Start pcsx2
"$DIR_PCSX2"/bin/pcsx2-qt "$@"
