#!/usr/bin/env bash
# Run a command with the environment of the user's running Hyprland session.
# Handy over SSH into a VM, where the login shell has no Wayland/Hyprland
# variables:  ssh vm ~/omarchy-theme-photograph/scripts/run-in-session.sh \
#                    ~/omarchy-theme-photograph/bin/omarchy-theme-photograph batch
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

while IFS= read -r line; do
  case $line in
    HYPRLAND_INSTANCE_SIGNATURE=* | WAYLAND_DISPLAY=* | DBUS_SESSION_BUS_ADDRESS=* | \
    OMARCHY_PATH=* | XDG_CURRENT_DESKTOP=* | XDG_SESSION_TYPE=*)
      export "${line?}" ;;
  esac
done < <(systemctl --user show-environment 2>/dev/null || true)

if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  sig=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1 || true)
  [[ -n $sig ]] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
fi
: "${WAYLAND_DISPLAY:=wayland-1}"
: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${DBUS_SESSION_BUS_ADDRESS:=unix:path=$XDG_RUNTIME_DIR/bus}"
export WAYLAND_DISPLAY OMARCHY_PATH DBUS_SESSION_BUS_ADDRESS
export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"

[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || { echo "no running Hyprland session found" >&2; exit 1; }
exec "$@"
