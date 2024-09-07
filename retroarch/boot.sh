#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Retroarch home
export HOME=/home/retroarch

# Assets
export XDG_CONFIG_HOME=$HOME/.config

# Libraries
export DIR_RETROARCH="$SCRIPT_DIR/data"
export LD_LIBRARY_PATH="$DIR_RETROARCH/lib:$LD_LIBRARY_PATH"

"$DIR_RETROARCH"/bin/retroarch "$@"
