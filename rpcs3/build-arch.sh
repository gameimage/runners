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
  "$IMAGE" fim-root fakechroot pacman -Syu --noconfirm

  # Install dependencies
  "$IMAGE" fim-root fakechroot pacman -S libxkbcommon libxkbcommon-x11 \
    lib32-libxkbcommon lib32-libxkbcommon-x11 libsm lib32-libsm fontconfig \
    libxinerama lib32-libxinerama \
    lib32-fontconfig noto-fonts --noconfirm

  # Install video packages
  "$IMAGE" fim-root fakechroot pacman -S xorg-server mesa lib32-mesa \
    glxinfo pcre xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon \
    xf86-video-intel vulkan-intel lib32-vulkan-intel vulkan-tools --noconfirm

  # Gameimage dependencies
  "$IMAGE" fim-root fakechroot pacman -S noto-fonts libappindicator-gtk3 \
    lib32-libappindicator-gtk3 --noconfirm

  # Commit changes
  "$IMAGE" fim-commit
}


function compress_rpcs3()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"
  # Copy rpcs3 runner
  cp "$SCRIPT_DIR"/boot.sh "$RPCS3_DIR"/boot
  # Create layer dirs
  mkdir -p ./root/opt
  mkdir -p ./root/home/rpcs3/.config
  # Move rpcs3 to layer dir
  mv "$RPCS3_DIR" ./root/opt
  # Compress rpcs3
  "$IMAGE" fim-layer create ./root "$BUILD_DIR/rpcs3.dwarfs"
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
  mv "$BUILD_DIR"/arch.flatimage rpcs3.flatimage
  mv "$BUILD_DIR"/rpcs3.dwarfs .

  # Compress
  tar -cf rpcs3.tar rpcs3.flatimage
  xz -3zv rpcs3.tar

  # Create sha256sum
  sha256sum rpcs3.flatimage > rpcs3.flatimage.sha256sum
  sha256sum rpcs3.tar.xz > rpcs3.tar.xz.sha256sum
  sha256sum rpcs3.dwarfs > rpcs3.dwarfs.sha256sum

  # Only distribute tarball
  rm rpcs3.flatimage
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

  # Fetch rpcs3
  fetch_rpcs3

  # FlatImage
  if [[ "$1" = "--flatimage" ]] && [[ -n "$2" ]]; then
    fetch_flatimage "$2"
  else
    fetch_flatimage
  fi

  # Create novel layer
  compress_rpcs3

  # Create directories
  "$IMAGE" fim-exec sh -c 'mkdir -p /home/rpcs3/{.config,.local/share}'

  # Set variables
  "$IMAGE" fim-env set 'HOME=/home/rpcs3' \
    'PATH="/opt/rpcs3/bin:$PATH"' \
    'FIM_BINARY_RPCS3="/opt/rpcs3/boot"'
    'XDG_CONFIG_HOME=/home/rpcs3/.config' \
    'XDG_DATA_HOME=/home/rpcs3/.local/share'

  # Set default command
  "$IMAGE" fim-boot '/opt/rpcs3/boot'

  # Set perms
  "$IMAGE" fim-perms set home,media,audio,wayland,xorg,dbus_user,dbus_system,udev,usb,input,gpu,network

  package
}

main "$@"

# // cmd: !./%

#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
