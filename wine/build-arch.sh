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
  wget -Oumu.zip "$2"
  # Extract deb from zip file
  unzip umu.zip
  # Cleanup
  rm umu.zip umu-launcher*.deb
  mv python3*.deb umu.deb
  # Extract binaries from deb
  ar x "umu.deb" data.tar.xz
  # Remove deb
  rm umu.deb
  # Extract binaries from data tarball
  # This extracts the /usr dir
  tar xf data.tar.xz -C ./root
  # Remove data tarball
  rm data.tar.xz
  # Create novel layer
  "$image" fim-layer create ./root wine.umu.ge.layer
}

# Create compressed files for wine distributions
function _package_wine_dists()
{
  local image="$1"

  local link_wine

  declare -a wine_dists=(
    "caffe"
    "vaniglia"
    "soda"
    # "umu"
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
      "umu")
        link_umu="$(curl -H "Accept: application/vnd.github+json" \
          https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest 2>/dev/null \
          | jq -e -r '.assets.[].browser_download_url | match(".*Debian.*.zip").string')"
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

}

function main()
{
  local image="$1"
  if ! [ -f "$image" ]; then
    echo "Please specify a regular file as the image path"
    exit 1
  fi
  # Enter script dir
  cd "$SCRIPT_DIR"
  # Create build and dist dirs
  mkdir -p dist
  mkdir -p build && cd build
  # Enable high verbose for flatimage
  # export FIM_DEBUG_SET_ARGS="-xe"
  export FIM_DEBUG="1"
  export FIM_FIFO="0"
  # Create wine dists
  _package_wine_dists "$image"
  # Create ssha
  for i in *.layer; do
    sha256sum "$i" > ../dist/"$i.sha256sum"
  done
  # Move layer to dist
  cp ./*.layer ../dist
}

main "$@"


#  vim: set expandtab fdm=marker ts=2 sw=2 tw=100 et :
