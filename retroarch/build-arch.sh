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

# Fetches retroarch from nightly
# # Exports RETROARCH_DIR
function fetch_retroarch()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  # Fetch latest release
  url_retroarch="https://buildbot.libretro.com/nightly/linux/x86_64/RetroArch.7z"
  wget "$url_retroarch"
  name_7z_file="$(basename "$url_retroarch")"

  # Extract
  7z x "$name_7z_file"

  # Remove 7z file
  rm "$name_7z_file"

  mkdir -p retroarch
  export RETROARCH_DIR="$BUILD_DIR"/retroarch

  # Move appimage to curr dir
  mv "RetroArch-Linux-x86_64/RetroArch-Linux-x86_64.AppImage" .
  appimage_retroarch="RetroArch-Linux-x86_64.AppImage"

  # Move assets to curr dir
  mv "RetroArch-Linux-x86_64/RetroArch-Linux-x86_64.AppImage.home/.config" "$BUILD_DIR"/retroarch/config

  # Remove extracted folder
  rm -rf "$BUILD_DIR/RetroArch-Linux-x86_64/"

  # Make executable
  chmod +x "$BUILD_DIR/$appimage_retroarch"

  # Extract appimage
  "$BUILD_DIR/$appimage_retroarch" --appimage-extract

  # Erase appimage
  rm "$BUILD_DIR/$appimage_retroarch"

  # Move export extracted directory
  mv "$BUILD_DIR"/squashfs-root/usr "$BUILD_DIR"/retroarch/data
  rm -rf squashfs-root
}

# Create layer filesystems for retroarch and its assets
function compress_retroarch()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"
  msg "${IMAGE:?IMAGE is undefined}"
  msg "${RETROARCH_DIR:?RETROARCH_DIR is undefined}"

  # Include startup hook
  cp "$SCRIPT_DIR/boot.sh" "$RETROARCH_DIR"/boot
  # Create layer dir
  mkdir -p ./root/opt
  # Move retroarch assets to gameimage home
  mkdir -p ./root/home/gameimage
  mv "$RETROARCH_DIR"/config ./root/home/gameimage/.config
  # Move retroarch to layer dir
  mv "$RETROARCH_DIR" ./root/opt
  # Create retroarch layer
  "$IMAGE" fim-layer create ./root ./retroarch.layer
  # Remove uncompressed files
  rm -rf ./root
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

  rm -rf "$BUILD_DIR"; mkdir "$BUILD_DIR"; cd "$BUILD_DIR"

  # Retroarch
  fetch_retroarch

  # Include retroarch in flatimage
  compress_retroarch

  # Create dist
  mkdir -p ../dist && cd ../dist

  # Move to-be-released files
  mv "$BUILD_DIR"/retroarch.layer .

  # Create checksum for everything
  sha256sum retroarch.layer > retroarch.layer.sha256sum
}

main "$@"

# // cmd: !./%
