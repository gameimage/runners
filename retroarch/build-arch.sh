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

  # Fetch container
  if ! [ -f "$BUILD_DIR/arch.tar.xz" ]; then
    wget "$(wget -qO - "https://api.github.com/repos/ruanformigoni/flatimage/releases/latest" \
      | jq -r '.assets.[].browser_download_url | match(".*arch.tar.xz$").string')"
  fi

  # Extract container
  rm -f "$BUILD_DIR/arch.flatimage"
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
    lib32-fontconfig noto-fonts sdl2 lib32-sdl2 --noconfirm

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

# Create dwarfs filesystems for retroarch and its assets
function compress_retroarch()
{
  msg "${BUILD_DIR:?BUILD_DIR is undefined}"
  msg "${IMAGE:?IMAGE is undefined}"
  msg "${RETROARCH_DIR:?RETROARCH_DIR is undefined}"

  # Include startup hook
  cp "$SCRIPT_DIR/boot.sh" "$RETROARCH_DIR"/boot

  # Compress retroarch
  "$IMAGE" fim-exec mkdwarfs \
    -i "$RETROARCH_DIR" \
    -o "$BUILD_DIR/retroarch.dwarfs"
}

function hooks_add()
{
  msg "${IMAGE:?Image is undefined}"
  msg "${SCRIPT_DIR:?SCRIPT_DIR is undefined}"

  "$IMAGE" fim-hook-add-pre "$SCRIPT_DIR"/hook-retroarch.sh
}

function configure_flatimage()
{
  msg "${IMAGE:?IMAGE is undefined}"

  # Set default command
  # shellcheck disable=2016
  "$IMAGE" fim-cmd '"$FIM_BINARY_RETROARCH"'

  # Set perms
  "$IMAGE" fim-perms-set wayland,x11,pulseaudio,gpu,session_bus,input,usb

  # Set up /usr overlay
  #shellcheck disable=2016
  "$IMAGE" fim-dwarfs-overlayfs usr '"${FIM_DIR_BINARY}"/."${FIM_BASENAME_BINARY}".config/overlays/usr'

  # Set up retroarch overlay
  #shellcheck disable=2016
  "$IMAGE" fim-config-set dwarfs.overlay.retroarch '"${FIM_DIR_BINARY}"/."${FIM_BASENAME_BINARY}".config/overlays/retroarch'

  # Set up HOME
  #shellcheck disable=2016
  "$IMAGE" fim-config-set home '"${FIM_DIR_BINARY}"'
}

function main()
{
  # shellcheck disable=2155
  export SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  export BUILD_DIR="$SCRIPT_DIR/build"

  rm -rf "$BUILD_DIR"; mkdir "$BUILD_DIR"; cd "$BUILD_DIR"

  # Container file path
  IMAGE="$BUILD_DIR/arch.flatimage"

  fetch_retroarch
  fetch_flatimage
  compress_retroarch
  hooks_add
  configure_flatimage

  # Rename
  mv "$IMAGE" retroarch.flatimage

  # Create dist
  mkdir -p ../dist

  # Move to-be-released files
  mv retroarch.flatimage ../dist
  mv retroarch.dwarfs ../dist

  # Enter dist dir
  cd ../dist

  # Create compressed archive
  tar -cf retroarch.tar retroarch.flatimage
  xz -0zv retroarch.tar

  # Create checksum for everything
  for i in *; do
    sha256sum "$i" > "${i}.sha256sum"
  done

  # Only release tarball
  rm retroarch.flatimage
}

main "$@"

# // cmd: !./%
