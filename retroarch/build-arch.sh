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

# Fetch & configure flatimage
function fetch_flatimage()
{
  msg "${IMAGE:?IMAGE is undefined}"

  if [[ -n "$1" ]]; then
    cp "$1" "$IMAGE"
  else
    wget "$(wget -qO - "https://api.github.com/repos/ruanformigoni/flatimage/releases/latest" \
      | jq -r '.assets.[].browser_download_url | match(".*arch.flatimage$").string')"
    chmod +x "$IMAGE"
  fi

  # Enable network
  "$IMAGE" fim-perms set network

  # Update
  "$IMAGE" fim-root pacman -Syu --noconfirm

  # Install dependencies
  "$IMAGE" fim-root pacman -S libxkbcommon libxkbcommon-x11 \
    lib32-libxkbcommon lib32-libxkbcommon-x11 libsm lib32-libsm fontconfig \
    libxinerama lib32-libxinerama \
    lib32-fontconfig noto-fonts sdl2 lib32-sdl2 --noconfirm

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
  # shellcheck disable=2155
  export SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  export BUILD_DIR="$SCRIPT_DIR/build"

  rm -rf "$BUILD_DIR"; mkdir "$BUILD_DIR"; cd "$BUILD_DIR"

  # Container file path
  IMAGE="$BUILD_DIR/arch.flatimage"

  # Retroarch
  fetch_retroarch

  # FlatImage
  if [[ "$1" = "--flatimage" ]] && [[ -n "$2" ]]; then
    fetch_flatimage "$2"
  else
    fetch_flatimage
  fi

  # Include retroarch in flatimage
  compress_retroarch

  # Create directories
  "$IMAGE" fim-exec sh -c 'mkdir -p /home/gameimage/.config'
  "$IMAGE" fim-exec sh -c 'mkdir -p /home/gameimage/.local/share'

  # Set environment variables
  "$IMAGE" fim-env set 'PATH="/opt/retroarch/data/bin:$PATH"' \
    'FIM_BINARY_RETROARCH="/opt/retroarch/boot"' \
    'HOME=/home/gameimage' \
    'XDG_CONFIG_HOME=/home/gameimage/.config' \
    'XDG_DATA_HOME=/home/gameimage/.local/share'

  # Set default command
  "$IMAGE" fim-boot '/opt/retroarch/boot'

  # Set perms
  "$IMAGE" fim-perms set home,media,audio,wayland,xorg,dbus_user,dbus_system,udev,usb,input,gpu,network

  # Save changes
  "$IMAGE" fim-commit

  # Rename
  mv "$IMAGE" retroarch.flatimage

  # Create dist
  mkdir -p ../dist

  # Move to-be-released files
  mv retroarch.flatimage ../dist
  mv retroarch.layer ../dist

  # Enter dist dir
  cd ../dist

  # Create checksum for everything
  for i in *; do
    sha256sum "$i" > "${i}.sha256sum"
  done
}

main "$@"

# // cmd: !./%
