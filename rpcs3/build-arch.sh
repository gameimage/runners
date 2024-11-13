#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : build
# @created     : Friday Nov 24, 2023 19:06:13 -03
#
# @description : 
######################################################################

#shellcheck disable=2016

set -e

function msg()
{
  echo "${FUNCNAME[1]}" "$@"
}

function fetch_rpcs3()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  # Fetch latest release
  read -r url_rpcs3 < <(wget -qO - "https://api.github.com/repos/RPCS3/rpcs3-binaries-linux/releases/latest" \
    | jq -r '.assets.[0].browser_download_url')
  wget "$url_rpcs3"

  # Fetched file name
  appimage_rpcs3="$(basename "$url_rpcs3")"

  # Make executable
  chmod +x "$BUILD_DIR/$appimage_rpcs3"

  # Extract appimage
  "$BUILD_DIR/$appimage_rpcs3" --appimage-extract

  # Remove image
  rm "$BUILD_DIR/$appimage_rpcs3"

  # Move rpcs3 dir
  mv "$BUILD_DIR"/squashfs-root/usr rpcs3

  # Export rpcs3 dir location
  export RPCS3_DIR="$BUILD_DIR"/rpcs3

  # Remove squashfs-root
  rm -rf ./squashfs-root
}

function compress_rpcs3()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"
  msg "${IMAGE:?IMAGE is undefined}"
  msg "${RPCS3_DIR:?RPCS3_DIR is undefined}"
  # Copy rpcs3 runner
  cp "$SCRIPT_DIR"/boot.sh "$RPCS3_DIR"/boot
  # Create layer dirs
  mkdir -p ./root/opt
  mkdir -p ./root/home/rpcs3/.config
  # Move rpcs3 to layer dir
  mv "$RPCS3_DIR" ./root/opt
  # Compress rpcs3
  "$IMAGE" fim-layer create ./root "$BUILD_DIR/rpcs3.layer"
  # Remove uncompressed files
  rm -rf ./root
}

function package()
{
  msg "${SCRIPT_DIR:?SCRIPT_DIR is undefined}"
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  local dir_dist="$SCRIPT_DIR"/dist

  mkdir -p "$dir_dist" && cd "$dir_dist"

  # Move binaries to dist dir
  mv "$BUILD_DIR"/rpcs3.layer .

  # Create sha256sum
  sha256sum rpcs3.layer > rpcs3.layer.sha256sum
}

function main()
{
  export IMAGE="$1"
  if ! [ -f "$IMAGE" ]; then
    echo "Please specify a regular file as the image path"
    exit 1
  fi

  # shellcheck disable=2155
  export SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  export BUILD_DIR="$SCRIPT_DIR/build"

  # Re-create build dir
  rm -rf "$BUILD_DIR"; mkdir "$BUILD_DIR"; cd "$BUILD_DIR"

  # Fetch rpcs3
  fetch_rpcs3

  # Create novel layer
  compress_rpcs3

  package
}

main "$@"

# // cmd: !./%

#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
