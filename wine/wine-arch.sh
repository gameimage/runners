#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : wine-arch
# @created     : Friday Sep 01, 2023 20:05:30 -03
#
# @description : 
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
    mesa lib32-mesa glxinfo lib32-gcc-libs \
    gcc-libs pcre freetype2 lib32-freetype2
  "$image" fim-root pacman -R --noconfirm wine

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

function _build_umu()
{
  # Download proton
  wget -O ./"proton.tar.gz" "$1"
  # Create proton directory
  mkdir -p ./root/opt/wine/bin/
  # Extract proton to proton directory
  tar xf ./"proton.tar.gz" --strip-components=1 -C ./root/opt/wine
  # Copy boot script
  cp "$SCRIPT_DIR"/wine.sh ./root/opt/wine/bin/wine.sh
  # Download UMU
  wget -Oumu.deb "$2"
  # Extract binaries from deb
  ar x "umu.deb" data.tar.zst
  # Remove deb
  rm umu.deb
  # Extract binaries from data tarball
  # This extracts the /usr dir
  tar xf data.tar.zst -C ./root
  # Remove data tarball
  rm data.tar.zst
  # Create novel layer
  "$image" fim-layer create ./root wine.umu.ge.layer
}

# Create compressed files for wine distributions
function _package_wine_dists()
{
  local image="$1"

  local link_wine

  declare -a wine_dists=(
    # "caffe"
    # "vaniglia"
    # "soda"
    "umu"
    # "staging"
    # "tkg"
    # "osu-tkg"
  )

  for dist_wine in "${wine_dists[@]}"; do
    case "$dist_wine" in
      "caffe" | "vaniglia" | "soda")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/bottlesdevs/wine/releases 2>&1 |
          pcregrep -io  "https://.*/download/.*/$dist_wine-.*\.tar(\.xz|\.gz)" |
          sed -e '/cx/d' |
          sort -V |
          tail -n1)"
      ;;
      "umu")
        link_umu="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest 2>/dev/null \
          | jq -e -r '.assets.[].browser_download_url | match(".*python3-umu.*.deb").string')"
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>/dev/null \
          | jq -e -r '.assets.[].browser_download_url | match(".*GE-Proton.*.tar.gz").string')"
      ;;
      "staging")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/Kron4ek/Wine-Builds/releases 2>/dev/null \
          | jq -e -r '.[].assets.[].browser_download_url  | match(".*staging-amd64.*").string' \
          | sort -V \
          | tail -n1)"
      ;;
      "tkg")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/Kron4ek/Wine-Builds/releases 2>/dev/null \
          | jq -e -r '.[].assets.[].browser_download_url  | match(".*tkg-amd64.*").string' \
          | sort -V \
          | tail -n1)"
      ;;
      "osu-tkg")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/NelloKudo/WineBuilder/releases 2>/dev/null \
          | jq -e -r '.[].assets.[].browser_download_url | match(".*wine-osu-tkg.*").string' \
          | sort -V | tail -n1)"
      ;;
    esac

    echo "link_wine: ${link_wine}"

    # Use alternate build process for umu
    if [[ "$dist_wine" = "umu" ]]; then
      _build_umu "$link_wine" "$link_umu"
      continue
    fi

    # Parse filename
    # shellcheck disable=2155
    local file_name="$(basename "$link_wine")"
    echo "file_name: ${file_name}"

    # Log version
    # shellcheck disable=2155
    local version_wine="$(basename -s .tar.xz "$file_name")"
    version_wine="$(basename -s .tar.gz "$version_wine")"
    echo "wine version: ${version_wine}"

    # Fetch wine
    [[ -f "$file_name" ]] || wget --progress=dot:mega "$link_wine"

    # Create layer directory
    mkdir -p ./root/opt/wine

    # Extract wine
    tar -xf "$file_name" -C root/opt/wine --strip-components=1

    # Remove tarball
    rm "$file_name"

    # Copy wine boot script
    cp "$SCRIPT_DIR"/wine.sh ./root/opt/wine/bin/wine.sh

    # Compress files
    "$image" fim-layer create ./root ./wine."${dist_wine}".layer -comp zstd

    # Remove temporary directory
    rm -rf ./wine
  done

  # Create ssha
  for i in *.layer; do
    sha256sum "$i" > "$i.sha256sum"
  done

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
  local basename_image=wine.flatimage
  local image="$SCRIPT_DIR/build/$basename_image"

  # Fetch
  if [[ "$1" = --flatimage ]]; then
    [[ -z "$2" ]] && { echo "Please specify image path"; exit 1; }
    cp "$2" "$image"
  else
    local tarball="arch.tar.xz"
    if [[ ! -f "$tarball" ]]; then
      wget "$(wget -qO - "https://api.github.com/repos/ruanformigoni/flatimage/releases/latest" \
        | jq -r '.assets.[].browser_download_url | match(".*arch.tar.xz$").string')"
    fi

    # Uncompress
    if [[ ! -f "arch.flatimage" ]]; then
      { pv -nf "$tarball" | tar xJ; } 2>&1 | xargs -I{} echo '[decompress %] {}'
      rm "$tarball"
    fi

    # Set image name
    cp ./"arch.flatimage" "$image"
  fi

  # Enable only home and network
  "$image" fim-perms set home,network

  if [[ -v BASE_CREATE ]]; then
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
    # shellcheck disable=2016
    "$image" fim-env set 'PATH="/opt/wine/bin:$PATH"' \
      'FIM_BINARY_WINE="/opt/wine/bin/wine.sh"' \
      'USER=gameimage' \
      'HOME=/home/gameimage' \
      'XDG_CONFIG_HOME=/home/gameimage/.config' \
      'XDG_DATA_HOME=/home/gameimage/.local/share'

    # shellcheck disable=2016
    # There is a problem with wine running on overlayfs with bwrap, it works
    # when the filesystem is bound directly (instead of acessing throught overlayfs)
    "$image" fim-bind add ro '$FIM_DIR_MOUNT/layers/2/opt/wine' /opt/wine

    # Set startup command
    # shellcheck disable=2016
    "$image" fim-boot /opt/wine/bin/wine.sh

    # Set permissions
    "$image" fim-perms set home,media,audio,wayland,xorg,dbus_user,dbus_system,udev,usb,input,gpu,network

    # Commit configurations
    "$image" fim-commit

    # Create SHA for image
    sha256sum "${basename_image}" > ../dist/"${basename_image}".sha256sum

    # Release image
    mv "${basename_image}" ../dist

  else
    # Check for image
    if [ ! -f "$image" ]; then
      echo "Could not find image '$image'"
      exit 1
    fi

    # Create wine dists
    _package_wine_dists "$image"

    ## Move layer to dist
    mv ./*.layer ../dist
    ## Move sha to dist
    mv ./*.sha256sum ../dist
  fi
}

main "$@"


#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
