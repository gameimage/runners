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

# Fetch & configure flatimage
function fetch_flatimage()
{
  msg "${IMAGE:?IMAGE is undefined}"


  if [[ -n "$1" ]]; then
    cp "$1" "$IMAGE"
  else
    # Fetch container
    if ! [ -f "$BUILD_DIR/arch.tar.xz" ]; then
      wget "$(wget -qO - "https://api.github.com/repos/ruanformigoni/flatimage/releases/latest" \
        | jq -r '.assets.[].browser_download_url | match(".*arch.tar.xz$").string')"
    fi

    # Extract container
    rm -f "$BUILD_DIR/arch.flatimage"
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
    lib32-fontconfig noto-fonts sdl2 lib32-sdl2 --noconfirm

  # Install video packages
  "$IMAGE" fim-root fakechroot pacman -S xorg-server mesa lib32-mesa \
    glxinfo pcre xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon \
    xf86-video-intel vulkan-intel lib32-vulkan-intel vulkan-tools --noconfirm

  # Gameimage dependencies
  "$IMAGE" fim-root fakechroot pacman -S noto-fonts libappindicator-gtk3 \
    lib32-libappindicator-gtk3 --noconfirm

  # Game dependencies
  declare -a GAME_DEPS=(
    # General linux audio
    pipewire-pulse lib32-pipewire pipewire-alsa wireplumber alsa-plugins
    # GOG Mojo setup & also Trine enchanted edition
    gtk2 lib32-gtk2
    # Amnesia A Machine For Pigs
    lib32-glu glu
    # Amnesia The Dark Descent
    openal lib32-openal libtheora lib32-libtheora
    # Crypt of the necrodancer
    lib32-libxss libxss
    # Hotline miami (sound)
    speexdsp lib32-speexdsp pipewire-jack lib32-pipewire-jack
    # Jazz jackrabbit
    speex libcaca lib32-libcaca
    # Others
    libpng lib32-libpng libpng12 lib32-libpng12 xorg-xwininfo ffmpeg 
  )

  "$IMAGE" fim-root fakechroot pacman -Rs --noconfirm jack2 lib32-jack2
  "$IMAGE" fim-root fakechroot pacman -S --noconfirm "${GAME_DEPS[@]}"

  # Workarounds
  ## Jazz Jackrabbit
  "$IMAGE" fim-root ln -s /lib/libFLAC.so /lib/libFLAC.so.8

  # Commit changes
  "$IMAGE" fim-commit
}

function main()
{
  # FIM_COMPRESSION_LEVEL
  export FIM_COMPRESSION_LEVEL=6

  # shellcheck disable=2155
  export SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  export BUILD_DIR="$SCRIPT_DIR/build"

  rm -rf "$BUILD_DIR"; mkdir "$BUILD_DIR"; cd "$BUILD_DIR"

  # Container file path
  IMAGE="$BUILD_DIR/arch.flatimage"

  # FlatImage
  if [[ "$1" = "--flatimage" ]] && [[ -n "$2" ]]; then
    fetch_flatimage "$2"
  else
    fetch_flatimage
  fi

  # Set perms
  "$IMAGE" fim-perms set home,media,audio,wayland,xorg,dbus_user,dbus_system,udev,usb,input,gpu,network

  # Create directories
  "$IMAGE" fim-exec sh -c 'mkdir -p /home/linux/{.config,.local/share}'

  # Set variables
  "$IMAGE" fim-env set 'HOME=/home/gameimage' \
    'XDG_CONFIG_HOME=/home/gameimage/.config' \
    'XDG_DATA_HOME=/home/gameimage/.local/share'

  # Rename
  mv "$IMAGE" linux.flatimage

  # Create dist
  mkdir -p ../dist

  # Move to-be-released files
  mv linux.flatimage ../dist

  # Enter dist dir
  cd ../dist

  # Create compressed archive
  tar -cf linux.tar linux.flatimage
  xz -0zv linux.tar

  # Create checksum for everything
  for i in *; do
    sha256sum "$i" > "${i}.sha256sum"
  done

  # Only release tarball
  rm linux.flatimage
}

main "$@"

# // cmd: !./%
