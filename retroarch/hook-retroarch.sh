#shellcheck disable=2148
export PATH="/fim/mount/retroarch/data/bin:$PATH"
export FIM_BINARY_RETROARCH="/fim/mount/retroarch/boot"

# Configure XDG
export XDG_DATA_HOME="${FIM_DIR_HOST_CONFIG}"/xdg/data
export XDG_CONFIG_HOME="${FIM_DIR_HOST_OVERLAYS}"/retroarch/mount/config

mkdir -p "$XDG_DATA_HOME"
