#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : wrapper
# @created     : Saturday Jan 21, 2023 19:00:53 -03
######################################################################

set -e

SCRIPT_NAME="$(basename "$0")"

exec 1> >(sed "s/^/[$SCRIPT_NAME] /")
exec 2> >(sed "s/^/[$SCRIPT_NAME] /" >&2)

# PATH
export PATH="/usr/bin:/opt/wine/bin:$PATH"

# WINE env
export WINEPREFIX="${WINEPREFIX:-"$HOME/Wine"}"
export WINEDEBUG=${WINEDEBUG:-"-all"}
export WINEHOME=${WINEHOME:-"$WINEPREFIX/home.wine"}

# DXVK env
export DXVK_HUD=${DXVK_HUD:-"0"}
export DXVK_LOG_LEVEL=${DXVK_LOG_LEVEL:-"none"}
export DXVK_STATE_CACHE=${DXVK_STATE_CACHE:-"0"}

# General info
echo "Container   : $FIM_DIST"
echo "Session Type: $XDG_SESSION_TYPE"
echo '$*          :' "$*"
echo "HOME        : $HOME"
echo "WINEPREFIX  : $WINEPREFIX"
echo "WINEHOME    : $WINEHOME"

# Create WINEPREFIX
mkdir -p "$WINEPREFIX"

# Create WINEHOME
mkdir -p "$WINEHOME"

# Check gpu vendor and device
if command -v glxinfo &>/dev/null && command -v pcregrep &>/dev/null; then
  glxinfo -B &>"$WINEPREFIX/glxinfo.log"
  echo "glxinfo log : $WINEPREFIX/glxinfo.log"
  INFO_VENDOR="$(glxinfo -B | pcregrep -o1 "OpenGL vendor.*:(.*)" | xargs)"
  INFO_VENDOR="${INFO_VENDOR,,}"
  INFO_DEVICE="$(glxinfo -B | pcregrep -o1 "OpenGL renderer.*:(.*)" | xargs)"
  INFO_OPENGL="$(glxinfo -B | pcregrep -o1 "OpenGL version.*:(.*)" | xargs)"
  echo "GPU Vendor  : $INFO_VENDOR"
  echo "GPU Device  : $INFO_DEVICE"
  echo "OpenGL      : $INFO_OPENGL"
fi

# Log vulkan info
if command -v vulkaninfo &>/dev/null; then
  vulkaninfo &>"$WINEPREFIX/vulkan.log"
  echo "Vulkan log  : $WINEPREFIX/vulkan.log"
fi

# Check for wine binary
if ! command -v wine; then
  echo "Binary 'wine' not found or is not a regular file"
  exit
fi

# Display wine version
echo "Wine version: $(wine --version)"

# Avoid symlinks
winetricks sandbox &>"$WINEPREFIX/winetricks-sandbox.log" || true

# Leave the root drive binding
ln -sfT / "$WINEPREFIX/dosdevices/z:" || true

# Start application
HOME="$WINEHOME" wine "$@"

# Wait for wineserver, since the program can still be executing on a different
# process
while pgrep -f "/tmp/fim/dwarfs/$DWARFS_SHA/.*/wineserver" &>/dev/null; do sleep 1; done
