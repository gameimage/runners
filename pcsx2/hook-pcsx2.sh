#shellcheck disable=2148
export PATH="/fim/mount/pcsx2/bin:$PATH"
export FIM_BINARY_PCSX2="/fim/mount/pcsx2/boot"

# Configure XDG
export XDG_DATA_HOME="${FIM_DIR_BINARY}"/."${FIM_BASENAME_BINARY}".config/xdg/data
export XDG_CONFIG_HOME="${FIM_DIR_BINARY}"/."${FIM_BASENAME_BINARY}".config/xdg/config
