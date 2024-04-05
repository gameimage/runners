#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : wine-arch
# @created     : Friday Sep 01, 2023 20:05:30 -03
#
# @description : 
######################################################################

set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

exec 1> >(while IFS= read -r line; do echo "-- [$SCRIPT_NAME $(date +%H:%M:%S)] $line"; done)
exec 2> >(while IFS= read -r line; do echo "-- [$SCRIPT_NAME $(date +%H:%M:%S)] $line" >&2; done)

# Set global vars
# export FIM_DEBUG=1

# Create a base image
# $1 image file
function _create_base()
{
  local image="$1"

  # Resize
  "$image" fim-resize 4G

  # Update
  "$image" fim-root fakechroot pacman -Syu --noconfirm

  # Install wine dependencies
  "$image" fim-root fakechroot pacman -S wine xorg-server mesa lib32-mesa glxinfo lib32-gcc-libs \
    gcc-libs pcre freetype2 lib32-freetype2 --noconfirm
  "$image" fim-root fakechroot pacman -R wine --noconfirm

  # Gameimage dependencies
  "$image" fim-root fakechroot pacman -S libappindicator-gtk3 lib32-libappindicator-gtk3 --noconfirm
}

# Include winetricks
# $1 image file
function _include_winetricks()
{
  local image="$1"

  "$image" fim-root fakechroot pacman -S cabextract --noconfirm

  wget -q --show-progress --progress=dot \
    "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" \
    -O winetricks

  # Wait for wineserver to finish before script exit
  # shellcheck disable=2016
  { sed -E 's/^\s+://' | tee -a winetricks &>/dev/null; } <<-"END"
  :while pgrep -f "/tmp/fim/dwarfs/$DWARFS_SHA/.*/wineserver" &>/dev/null; do
  :  echo "Waiting for wineserver to finish..."
  :  sleep .5
  :done
	END

  "$image" fim-root cp ./winetricks /usr/bin/winetricks
  "$image" fim-root chmod +x /usr/bin/winetricks
}

# Include amd video drivers in image
# $1 image file
function _include_amd()
{
  local image="$1"

  "$image" fim-root fakechroot pacman -S xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon vulkan-tools --noconfirm
}

# Include intel video drivers in image
# $1 image file
function _include_intel()
{
  local image="$1"

  "$image" fim-root fakechroot pacman -S xf86-video-intel vulkan-intel lib32-vulkan-intel vulkan-tools --noconfirm
}

# Create dwarfs files for wine distributions
function _package_wine_dists()
{
  local image="$1"

  local link_wine

  declare -a wine_dists=(
    "caffe"
    "vaniglia"
    "soda"
    "ge"
    "staging"
    "tkg"
    "osu-tkg"
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
      "ge")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/GloriousEggroll/wine-ge-custom/releases/latest 2>/dev/null \
          | jq -e -r '.assets.[].browser_download_url | match(".*.tar.xz").string')"
      ;;
      "staging")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/Kron4ek/Wine-Builds/releases/latest 2>/dev/null \
          | jq -e -r '.assets.[].browser_download_url | match(".*staging-amd64.*").string')"
      ;;
      "tkg")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/Kron4ek/Wine-Builds/releases/latest 2>/dev/null \
          | jq -e -r '.assets.[].browser_download_url | match(".*tkg-amd64.*").string')"
      ;;
      "osu-tkg")
        link_wine="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/NelloKudo/WineBuilder/releases 2>/dev/null \
          | jq -e -r '.[].assets.[].browser_download_url | match(".*wine-osu-tkg.*").string' \
          | sort -V | tail -n1)"
      ;;
    esac
    echo "link_wine: ${link_wine}"

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

    # Extract wine
    mkdir wine
    tar -xf "$file_name" -C wine --strip-components=1

    # Remove tarball
    rm "$file_name"

    # Copy wine boot script
    cp "$SCRIPT_DIR"/wine.sh ./wine/bin/wine.sh

    # Compress files
    "$image" fim-root mkdwarfs -i ./wine -o "${dist_wine}.dwarfs"

    # Remove temporary directory
    rm -rf ./wine
  done

  # Create ssha
  for i in *.dwarfs; do
    sha256sum "$i" > "$i.sha256sum"
  done

}

# Constructs a wine image
# $1 source image file
# $2 vendor name
# $3 wine distribution
# $4 build script
function _build()
{
  local image="$1"
  local vendor="$2"
  local dist="$3"
  local script="$4"
  # Set out image name
  local out="./wine-$vendor-$dist"
  # Copy base image
  cp "$image" "$out"
  # Set include packages
  eval "$script \"$out\""
  # Clear cache
  "$out" fim-root pacman -Scc --noconfirm
  # Make executable
  "$out" fim-root chmod +x /fim/scripts/wine.sh
  # # Compress
  "$out" fim-compress
  # Release
  mkdir -p dist && mv "$out" "dist/$out"
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

  # shellcheck disable=2155
  local basename_image=base.flatimage
  local image="$SCRIPT_DIR/build/$basename_image"

  # Fetch
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

  # Disable permissions to avoid issues with some things not found
  "$image" fim-perms-set ""

  if [[ -v BASE_CREATE ]]; then
    # Create base image
    _create_base "$image"

    # Create AMD/Intel base
    _include_amd        "$image"
    _include_intel      "$image"
    _include_winetricks "$image"

    # Remove /opt
    "$image" fim-root rm -rf /opt

    # Include wine hook
    # shellcheck disable=2016
    "$image" fim-cmd '"$FIM_BINARY_WINE"'
    "$image" fim-hook-add-pre "$SCRIPT_DIR"/hook-wine.sh

    # Set permissions
    "$image" fim-perms-set wayland,x11,pulseaudio,gpu,session_bus,input,usb

    # Compress image
    FIM_COMPRESSION_DIRS="/usr" "$image" fim-compress

    # Set up /usr overlay
    #shellcheck disable=2016
    "$image" fim-dwarfs-overlayfs usr '"${FIM_DIR_BINARY}"/."${FIM_BASENAME_BINARY}".config/overlays/usr'

    # Set up HOME
    #shellcheck disable=2016
    "$image" fim-config-set home '"${FIM_DIR_BINARY}"'

    # Create SHA for image
    sha256sum "${basename_image}" > ../dist/"${basename_image}".sha256sum

    # Include image in tarball
    tar -cf "${basename_image}.tar" "$basename_image"
    xz -z3v "${basename_image}.tar" 

    # Create SHA for tarball
    sha256sum "${basename_image}.tar.xz" > ../dist/"${basename_image}.tar.xz.sha256sum"

    # Release tarball
    mv "${basename_image}.tar.xz" ../dist

  else
    # Check for image
    if [ ! -f "$image" ]; then
      echo "Could not find image '$image'"
      exit 1
    fi

    # Create wine dists
    _package_wine_dists "$image"

    ## Move dwarfs to dist
    mv ./*.dwarfs ../dist
    ## Move sha to dist
    mv ./*.sha256sum ../dist
  fi
}

main "$@"


#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
