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
  "rpcs3"
  "retroarch"
)

IMAGE="$DIR_SCRIPT"/container/dist/linux.flatimage

rm -rf dist && mkdir dist

# Create container
(
  cd container
  ./build-arch.sh
  cp dist/linux.flatimage "$DIR_SCRIPT"/dist/linux.flatimage
  cp dist/linux.flatimage.sha256sum "$DIR_SCRIPT"/dist/linux.flatimage.sha256sum
)

# Create layers
for platform in "${PLATFORMS[@]}"; do
  cd "$DIR_SCRIPT"/"$platform"
  ./build-arch.sh "$IMAGE"
  mv dist/* "$DIR_SCRIPT"/dist
done
