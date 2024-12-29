#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : container
######################################################################

set -xe

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Set global vars
# export FIM_DEBUG=1

# Create a base image
# $1 image file
function _create_base()
{
  local image="$1"

  # Update
  "$image" fim-root pacman -Syu --noconfirm

  # Install wine dependencies
  "$image" fim-root pacman -S --noconfirm wine xorg-server libxinerama lib32-libxinerama \
    mesa lib32-mesa glxinfo lib32-gcc-libs gcc-libs pcre freetype2 lib32-freetype2 wget aria2 \
    zenity gstreamer lib32-gstreamer gst-libav gst-plugins-{bad,base,good,ugly} lib32-gst-plugins-{base,good} \
    noto-fonts sdl2 lib32-sdl2 libxkbcommon libxkbcommon-x11 lib32-libxkbcommon lib32-libxkbcommon-x11 \
    libsm lib32-libsm fontconfig lib32-freetype2 freetype2
  "$image" fim-root pacman -R --noconfirm wine

  # Game dependencies
  declare -a GAME_DEPS=(
    # General linux audio
    lib32-pipewire pipewire-alsa wireplumber alsa-plugins
    lib32-libpulse pulseaudio-{alsa,equalizer,jack,lirc,zeroconf}
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

  "$image" fim-root pacman -Rs --noconfirm pipewire-pulse
  "$image" fim-root pacman -S --noconfirm "${GAME_DEPS[@]}"

  # Gameimage dependencies
  "$image" fim-root pacman -S --noconfirm noto-fonts libappindicator-gtk3 lib32-libappindicator-gtk3

  # Wine UMU
  "$image" fim-root pacman -S --noconfirm python python-xlib python-filelock
}

# Include winetricks
# $1 image file
function _include_winetricks()
{
  local image="$1"

  "$image" fim-root pacman -S cabextract --noconfirm

  wget -q --show-progress --progress=dot \
    "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" \
    -O winetricks

  "$image" fim-exec cp ./winetricks /usr/bin/winetricks
  "$image" fim-exec chmod +x /usr/bin/winetricks
}

# Include amd video drivers in image
# $1 image file
function _include_amd()
{
  local image="$1"

  "$image" fim-root pacman -S xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon vulkan-tools --noconfirm
}

# Include intel video drivers in image
# $1 image file
function _include_intel()
{
  local image="$1"

  "$image" fim-root pacman -S xf86-video-intel vulkan-intel lib32-vulkan-intel vulkan-tools --noconfirm
}

function main()
{
  # Enter script dir
  cd "$SCRIPT_DIR"
  mkdir -p dist
  mkdir -p build && cd build

  # Enable high verbose for flatimage
  # export FIM_DEBUG_SET_ARGS="-xe"
  export FIM_DEBUG="1"
  export FIM_FIFO="0"

  # shellcheck disable=2155
  local basename_image=linux.flatimage
  local image="$SCRIPT_DIR/build/$basename_image"

  # Fetch
  if [[ "$1" = --flatimage ]]; then
    [[ -z "$2" ]] && { echo "Please specify image path"; exit 1; }
    cp "$2" "$image"
  else
    wget "https://github.com/ruanformigoni/flatimage/releases/download/v1.0.7/arch.flatimage"
    # Set image name
    cp ./"arch.flatimage" "$image"
    rm ./"arch.flatimage"
    chmod +x "$image"
  fi

  # Enable only home and network
  "$image" fim-perms set home,network

  # Create base image
  _create_base "$image"

  # Create AMD/Intel base
  _include_amd        "$image"
  _include_intel      "$image"
  _include_winetricks "$image"

  # Remove /opt
  # "$image" fim-exec rm -rf /opt

  # Create directories
  "$image" fim-exec sh -c 'mkdir -p /home/gameimage/.config'
  "$image" fim-exec sh -c 'mkdir -p /home/gameimage/.local/share'

  # Set environment
  ## Requires to set LD_LIBRARY_PATH to look for libraries in read-only paths,
  ## there is a bug in fuse-overlayfs that causes undefined symbols
  # shellcheck disable=2016
  "$image" fim-env set 'PATH="/opt/pcsx2/bin:/opt/rpcs3/bin:/opt/retroarch/data/bin:/opt/wine/bin:$PATH"' \
    'FIM_BINARY_WINE="/opt/wine/bin/wine.sh"' \
    'FIM_BINARY_RETROARCH="/opt/retroarch/boot"' \
    'FIM_BINARY_RPCS3="/opt/rpcs3/boot"' \
    'FIM_BINARY_PCSX2="/opt/pcsx2/boot"' \
    'USER=gameimage' \
    'HOME=/home/gameimage' \
    'XDG_CONFIG_HOME=/home/gameimage/.config' \
    'XDG_DATA_HOME=/home/gameimage/.local/share'

  # Set permissions
  "$image" fim-boot sh -c 'echo "FlatImage ($FIM_VERSION) for GameImage"'

  # Set permissions
  "$image" fim-perms set home,media,audio,wayland,xorg,dbus_user,dbus_system,udev,usb,input,gpu,network

  # Remove files in $HOME
  sudo rm -rf ./."${basename_image}".config/overlays/upperdir/home
  
  # Commit packages and configurations
  ## TODO Remove true when issues with file deletion are solved
  # The error:
  # E 15:39:10.353013 cannot access /home/runner/work/runners/runners/container/build/.linux.flatimage.config/overlays/upperdir/usr/lib/dbus-daemon-launch-helper, creating empty file
  # Causes the commit to fail, use manual method instead
  # "$image" fim-commit || true
  "$image" fim-layer create ./."${basename_image}".config/overlays/upperdir ./layer.tmp || true
  "$image" fim-layer add ./layer.tmp || true
  rm layer.tmp 

  # Create SHA
  sha256sum "${basename_image}" > ../dist/"${basename_image}".sha256sum
  # Release image
  cp ./"${basename_image}" ../dist
}

main "$@"


#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
