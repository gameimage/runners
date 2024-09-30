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


function fetch_flatimage()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"

  if [[ -n "$1" ]]; then
    cp "$1" "$IMAGE"
  else
    # Fetch container
    if ! [ -f "$BUILD_DIR/arch.tar.xz" ]; then
      wget "$(wget -qO - "https://api.github.com/repos/ruanformigoni/flatimage/releases/latest" \
        | jq -r '.assets.[].browser_download_url | match(".*arch.tar.xz$").string')"
    fi

    # Extract container
    rm -f "$IMAGE"

    tar xf arch.tar.xz
  fi

  # Enable network
  "$IMAGE" fim-perms set network

  # Update
  "$IMAGE" fim-root pacman -Syu --noconfirm

  # Install dependencies
  "$IMAGE" fim-root pacman -S libxkbcommon libxkbcommon-x11 \
    lib32-libxkbcommon lib32-libxkbcommon-x11 libsm lib32-libsm fontconfig \
    libxinerama lib32-libxinerama \
    lib32-fontconfig noto-fonts --noconfirm

  # Install video packages
  "$IMAGE" fim-root pacman -S xorg-server mesa lib32-mesa \
    glxinfo pcre xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon \
    xf86-video-intel vulkan-intel lib32-vulkan-intel vulkan-tools --noconfirm

  # Gameimage dependencies
  "$IMAGE" fim-root pacman -S noto-fonts libappindicator-gtk3 \
    lib32-libappindicator-gtk3 --noconfirm

  # Commit changes
  "$IMAGE" fim-commit
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
  "$IMAGE" fim-layer create ./root pcsx2.dwarfs
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
  # FlatImage
  if [[ "$1" = "--flatimage" ]] && [[ -n "$2" ]]; then
    fetch_flatimage "$2"
  else
    fetch_flatimage
  fi

  # Create directories
  "$IMAGE" fim-exec sh -c 'mkdir -p /home/pcsx2/{.config,.local/share}'

  # Set variables
  "$IMAGE" fim-env set 'HOME=/home/gameimage' \
    'PATH="/opt/pcsx2/bin:$PATH"' \
    'FIM_BINARY_PCSX2="/opt/pcsx2/boot"' \
    'XDG_CONFIG_HOME=/home/gameimage/.config' \
    'XDG_DATA_HOME=/home/gameimage/.local/share'

  # Compress changes
  compress_pcsx2

  # Set default command
  "$IMAGE" fim-boot '/opt/pcsx2/boot'

  # Set perms
  "$IMAGE" fim-perms set home,media,audio,wayland,xorg,dbus_user,dbus_system,udev,usb,input,gpu,network

  package
}

main "$@"

# // cmd: !./%

#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
