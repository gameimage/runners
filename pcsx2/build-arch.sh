#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : build
# @created     : Friday Nov 24, 2023 19:06:13 -03
#
# @description : 
######################################################################

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
}


function fetch_flatimage()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  # Fetch container
  if ! [ -f "$BUILD_DIR/arch.tar.xz" ]; then
    wget "$(wget -qO - "https://api.github.com/repos/ruanformigoni/flatimage/releases/latest" \
      | jq -r '.assets.[].browser_download_url | match(".*arch.tar.xz$").string')"
  fi

  # Extract container
  rm -f "$IMAGE"

  tar xf arch.tar.xz

  # FIM_COMPRESSION_LEVEL
  export FIM_COMPRESSION_LEVEL=6

  # Resize
  "$IMAGE" fim-resize 3G

  # Update
  "$IMAGE" fim-root fakechroot pacman -Syu --noconfirm

  # Install dependencies
  "$IMAGE" fim-root fakechroot pacman -S libxkbcommon libxkbcommon-x11 \
    lib32-libxkbcommon lib32-libxkbcommon-x11 libsm lib32-libsm fontconfig \
    lib32-fontconfig noto-fonts --noconfirm

  # Install video packages
  "$IMAGE" fim-root fakechroot pacman -S xorg-server mesa lib32-mesa \
    glxinfo pcre xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon \
    xf86-video-intel vulkan-intel lib32-vulkan-intel vulkan-tools --noconfirm

  # Gameimage dependencies
  "$IMAGE" fim-root fakechroot pacman -S libappindicator-gtk3 \
    lib32-libappindicator-gtk3 --noconfirm

  # Compress self
  "$IMAGE" fim-compress
}


function compress_pcsx2()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  # Copy pcsx2 runner
  cp "$SCRIPT_DIR"/boot.sh "$BUILD_DIR"/squashfs-root/usr/boot

  # Compress pcsx2
  "$IMAGE" fim-exec mkdwarfs -i "$BUILD_DIR"/squashfs-root/usr -o "$BUILD_DIR/pcsx2.dwarfs"
}

function hooks_add()
{
  msg "${IMAGE:?IMAGE is undefined}"
  msg "${SCRIPT_DIR:?SCRIPT_DIR is undefined}"

  "$IMAGE" fim-hook-add-pre "$SCRIPT_DIR"/hook-pcsx2.sh
}

function configure_flatimage()
{
  msg "${IMAGE:?IMAGE is undefined}"

  # Set default command
  # shellcheck disable=2016
  "$IMAGE" fim-cmd '"$FIM_BINARY_PCSX2"'

  # Set perms
  "$IMAGE" fim-perms-set wayland,x11,pulseaudio,gpu,session_bus,input,usb

  # Set up HOME
  #shellcheck disable=2016
  "$IMAGE" fim-config-set home '"${FIM_DIR_BINARY}"'
}

function package()
{
  msg "${SCRIPT_DIR:?SCRIPT_DIR is undefined}"
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  local dir_dist="$SCRIPT_DIR"/dist

  mkdir -p "$dir_dist" && cd "$dir_dist"

  # Move binaries to dist dir
  mv "$BUILD_DIR"/arch.flatimage pcsx2.flatimage
  mv "$BUILD_DIR"/pcsx2.dwarfs .

  # Compress
  tar -cf pcsx2.tar pcsx2.flatimage
  xz -3zv pcsx2.tar

  # Create sha256sum
  sha256sum pcsx2.flatimage > pcsx2.flatimage.sha256sum
  sha256sum pcsx2.tar.xz > pcsx2.tar.xz.sha256sum
  sha256sum pcsx2.dwarfs > pcsx2.dwarfs.sha256sum

  # Only distribute tarball
  rm pcsx2.flatimage
}

function main()
{
  # shellcheck disable=2155
  export SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  export BUILD_DIR="$SCRIPT_DIR/build"

  # Re-create build dir
  rm -rf "$BUILD_DIR"; mkdir "$BUILD_DIR"; cd "$BUILD_DIR"

  # Container file path
  export IMAGE="$BUILD_DIR/arch.flatimage"

  fetch_pcsx2
  fetch_flatimage
  compress_pcsx2
  hooks_add
  configure_flatimage
  package
}

main "$@"

# // cmd: !./%

#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
