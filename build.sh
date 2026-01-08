#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : build
######################################################################

set -e

DIR_SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PLATFORMS=(
  "wine"
  "pcsx2"
  "retroarch"
  "rpcs3"
)

IMAGE="$DIR_SCRIPT"/dist/arch.flatimage

export FIM_OVERLAY=unionfs

rm -rf dist && mkdir dist

# Create container
( cd container && ./build-arch.sh )

# Create layers
for platform in "${PLATFORMS[@]}"; do
  cd "$DIR_SCRIPT"/"$platform"
  ./build-arch.py "$IMAGE"
done