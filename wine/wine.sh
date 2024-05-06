#!/usr/bin/env bash

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : wrapper
# @created     : Saturday Jan 21, 2023 19:00:53 -03
######################################################################

shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"

exec 1> >(sed "s/^/[$SCRIPT_NAME] /")
exec 2> >(sed "s/^/[$SCRIPT_NAME] /" >&2)

# PATH
export PATH="/fim/mount/wine/bin:/usr/bin:/opt/wine/bin:$PATH"

# WINE env
export USER="${WINEUSER:-gameimage}"
export HOME=${WINEHOME:-"$FIM_DIR_HOST_CONFIG"/home}
export WINEPREFIX="${WINEPREFIX:-"$HOME/Wine"}"
export WINEDEBUG=${WINEDEBUG:-"-all"}

# DXVK env
export DXVK_HUD=${DXVK_HUD:-"0"}
export DXVK_LOG_LEVEL=${DXVK_LOG_LEVEL:-"none"}
export DXVK_STATE_CACHE=${DXVK_STATE_CACHE:-"0"}

# General info
echo "Container   : $FIM_DIST"
echo "Session Type: $XDG_SESSION_TYPE"
echo '$*          :' "$*"
echo "USER        : $USER"
echo "WINEDEBUG   : $WINEDEBUG"
echo "HOME        : $HOME"
echo "WINEPREFIX  : $WINEPREFIX"

# Create WINEPREFIX
mkdir -p "$WINEPREFIX"

# Create wine HOME
mkdir -p "$HOME"

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

# # Avoid symlinks
# winetricks sandbox &>"$WINEPREFIX/winetricks-sandbox.log" || true
# # Leave the root drive binding
# ln -sfT / "$WINEPREFIX/dosdevices/z:" || true

# Replace symlinks with directories
for i in "$WINEPREFIX/drive_c/users/$USER"/*; do
  if [[ -h "$i" ]]; then rm -fv "$i" && mkdir -v "$i"; fi
done

# If the last argument is an executable path, enter the parent directory
if [[ -f "${BASH_ARGV[0]}" ]]; then
  DIR_NEW="$(dirname -- "$(readlink -f "${BASH_ARGV[0]}")")"
  cd -- "$DIR_NEW" || { echo "Failed to switch directory to $DIR_NEW"; exit 1; }
  echo "Switched directory to: $DIR_NEW"
fi
  
# Start application
if [[ "$1" = "winetricks" ]]; then
  shift
  2>&1 winetricks -f "$@" | tee "$WINEPREFIX/winetricks.log"
  echo "Winetricks log  : $WINEPREFIX/winetricks.log"
else
  2>&1 wine "$@" | tee "$WINEPREFIX/wine.log"
  echo "Wine log  : $WINEPREFIX/wine.log"
fi
