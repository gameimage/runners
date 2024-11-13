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

function fetch_pcsx2()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  # Fetch latest release
  read -r url_pcsx2 < <(wget -qO - "https://api.github.com/repos/PCSX2/pcsx2/releases" \
    | jq -r '.[].assets.[].browser_download_url | match(".*AppImage$").string' \
    | sort -V \
    | tail -n1)
  wget "$url_pcsx2"

  # Fetched file name
  appimage_pcsx2="$(basename "$url_pcsx2")"

  # Make executable
  chmod +x "$BUILD_DIR/$appimage_pcsx2"

  # Extract appimage
  "$BUILD_DIR/$appimage_pcsx2" --appimage-extract

  # Remove image
  rm "$BUILD_DIR/$appimage_pcsx2"

  # Move pcsx2 dir
  mv "$BUILD_DIR"/squashfs-root/usr pcsx2

  # Export pcsx2 dir location
  export PCSX2_DIR="$BUILD_DIR"/pcsx2

  # Remove squashfs-root
  rm -rf ./squashfs-root
}


function compress_pcsx2()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"
  msg "${PCSX2_DIR:?PCSX2_DIR is undefined}"
  # Copy pcsx2 runner
  cp "$SCRIPT_DIR"/boot.sh "$PCSX2_DIR"/boot
  # Create layer dirs
  mkdir -p ./root/opt
  mkdir -p ./root/home/pcsx2/.config
  # Move pcsx2 to layer dir
  mv "$PCSX2_DIR" ./root/opt
  # Compress pcsx2
  "$IMAGE" fim-layer create ./root pcsx2.layer
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
  mv "$BUILD_DIR"/pcsx2.layer .

  # Create sha256sum
  sha256sum pcsx2.layer > pcsx2.layer.sha256sum
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

  # Fetch latest
  fetch_pcsx2

  # Compress changes
  compress_pcsx2

  # Move to dist and create SHA
  package
}

main "$@"

# // cmd: !./%

#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
