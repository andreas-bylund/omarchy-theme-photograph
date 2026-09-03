# shellcheck shell=bash
# Hyprland helpers. Targets Hyprland with the Lua config API (Omarchy 4 ships
# Hyprland >= 0.55), where `hyprctl dispatch` and `hyprctl eval` take Lua.

hypr_json() { hyprctl -j "$@"; }

hypr_eval() {
  local out
  if ! out=$(hyprctl eval "$1" 2>&1); then
    warn "hyprctl eval failed: $out"
    return 1
  fi
  if [[ $out == error* || $out == *$'\n'error* ]]; then
    warn "hyprctl eval: $out"
    return 1
  fi
}

hypr_dispatch() {
  local out
  if ! out=$(hyprctl dispatch "$1" 2>&1); then
    warn "hyprctl dispatch failed: $out"
    return 1
  fi
  if [[ $out == error* ]]; then
    warn "hyprctl dispatch: $out"
    return 1
  fi
}

# Quote a string as a Lua long-bracket literal so no escaping is needed.
hypr_lua_str() {
  local s="$1" eq="="
  while [[ $s == *"]${eq}]"* ]]; do eq+="="; done
  printf '[%s[%s]%s]' "$eq" "$s" "$eq"
}

hypr_has_lua_api() { hyprctl eval 'return 0' 2>/dev/null | grep -q '^ok'; }

# --- Monitors and outputs ---
hypr_focused_monitor() { hypr_json monitors | jq -r '.[] | select(.focused) | .name'; }
hypr_active_workspace() { hypr_json activeworkspace | jq -r '.id'; }
hypr_output_exists() { hypr_json monitors all | jq -e --arg n "$1" '.[] | select(.name == $n)' >/dev/null 2>&1; }

# hypr_create_output NAME LOGICAL_W LOGICAL_H SCALE
hypr_create_output() {
  local name="$1" w="$2" h="$3" scale="$4" pw ph i
  pw=$(awk -v w="$w" -v s="$scale" 'BEGIN { printf "%d", w * s }')
  ph=$(awk -v h="$h" -v s="$scale" 'BEGIN { printf "%d", h * s }')

  if hypr_output_exists "$name"; then
    warn "output $name already exists, reusing it"
  else
    hyprctl output create headless "$name" >/dev/null || die "could not create headless output $name"
  fi
  hypr_eval "hl.monitor({ output = \"$name\", mode = \"${pw}x${ph}@60\", position = \"auto\", scale = $scale })" || true

  for i in $(seq 1 50); do
    if hypr_json monitors | jq -e --arg n "$name" --argjson pw "$pw" '.[] | select(.name == $n and .width == $pw)' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  die "headless output $name did not come up at ${pw}x${ph}"
}

hypr_remove_output() {
  hypr_output_exists "$1" && hyprctl output remove "$1" >/dev/null 2>&1
  return 0
}

# --- Focus ---
hypr_focus_monitor()   { hypr_dispatch "hl.dsp.focus({ monitor = \"$1\" })"; }
hypr_focus_workspace() { hypr_dispatch "hl.dsp.focus({ workspace = \"$1\" })"; }
hypr_focus_window()    { hypr_dispatch "hl.dsp.focus({ window = \"address:$1\" })"; }

# First unused workspace id from 90 upwards.
hypr_free_workspace() {
  local used i
  used=$(hypr_json workspaces | jq -r '.[].id')
  for i in $(seq 90 130); do
    grep -qx "$i" <<<"$used" || { echo "$i"; return 0; }
  done
  return 1
}

# --- Launching and waiting ---
# hypr_exec CMD_STRING  -- run through Hyprland's exec with a workspace rule.
hypr_exec() {
  hypr_eval "hl.exec_cmd($(hypr_lua_str "$1"), { workspace = \"$OTP_WS\" })"
}

# hypr_wait_window CLASS [TIMEOUT]  -- prints the address once the window is mapped
# on our workspace. A window that mapped elsewhere is moved over.
hypr_wait_window() {
  local class="$1" timeout="${2:-20}" deadline now addr other
  deadline=$(( $(date +%s%N) / 1000000 + timeout * 1000 ))
  while :; do
    addr=$(hypr_json clients | jq -r --arg c "$class" --argjson ws "$OTP_WS" \
      '[.[] | select(.class == $c and .workspace.id == $ws and .mapped)] | first | .address // empty')
    if [[ -n $addr ]]; then
      echo "$addr"
      return 0
    fi
    other=$(hypr_json clients | jq -r --arg c "$class" --argjson ws "$OTP_WS" \
      '[.[] | select(.class == $c and .mapped and .workspace.id != $ws and (.workspace.id | . > 0))] | first | .address // empty')
    if [[ -n $other ]]; then
      hypr_dispatch "hl.dsp.window.move({ window = \"address:$other\", workspace = \"$OTP_WS\" })" || true
    fi
    now=$(( $(date +%s%N) / 1000000 ))
    (( now > deadline )) && { warn "timed out waiting for window with class '$class'"; return 1; }
    sleep 0.15
  done
}

hypr_workspace_windows() {
  hypr_json clients | jq -r --argjson ws "$OTP_WS" '.[] | select(.workspace.id == $ws) | .address'
}

hypr_close_workspace_windows() {
  local a p i
  for a in $(hypr_workspace_windows); do
    hypr_dispatch "hl.dsp.window.close({ window = \"address:$a\" })" || true
  done
  for i in $(seq 1 40); do
    [[ -z $(hypr_workspace_windows) ]] && return 0
    sleep 0.1
  done
  for p in $(hypr_json clients | jq -r --argjson ws "$OTP_WS" '.[] | select(.workspace.id == $ws) | .pid'); do
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 0.5
  return 0
}

# --- Layers (shell surfaces such as the menu or the lock preview) ---
# hypr_wait_layer NAMESPACE MONITOR [TIMEOUT]
hypr_wait_layer() {
  local ns="$1" mon="$2" timeout="${3:-8}" i
  for i in $(seq 1 $(( timeout * 10 ))); do
    if hypr_json layers | jq -e --arg m "$mon" --arg ns "$ns" '.[$m].levels[][] | select(.namespace == $ns)' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# hypr_wait_layer_any NAMESPACE [TIMEOUT]  -- prints the monitor that shows the layer
hypr_wait_layer_any() {
  local ns="$1" timeout="${2:-8}" i mon
  for i in $(seq 1 $(( timeout * 10 ))); do
    mon=$(hypr_json layers | jq -r --arg ns "$ns" 'to_entries[] | select(any(.value.levels[][]; .namespace == $ns)) | .key' | head -1)
    if [[ -n $mon ]]; then
      echo "$mon"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# --- Config options we temporarily change while photographing ---
hypr_opt() {
  hyprctl getoption "$1" -j 2>/dev/null | jq -r 'if has("bool") then .bool elif has("int") then .int elif has("float") then .float else empty end'
}

hypr_config() { hypr_eval "hl.config({ $1 })"; }
