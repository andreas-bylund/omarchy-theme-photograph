# shellcheck shell=bash
# Scenes: each scene_<name> function arranges something on the virtual screen
# and calls otp_capture. Scenes run inside an active session (see otp_session_begin).

OTP_SHOWCASE_DIR="$OTP_ROOT/assets/showcase"
OTP_TERMINAL_SHOWCASE="$OTP_ROOT/assets/terminal-showcase.sh"
OTP_EDITOR_FILE="$OTP_SHOWCASE_DIR/showcase.rb"

# --- Session lifecycle ---
otp_session_begin() {
  OTP_ORIG_MON=$(hypr_focused_monitor)
  OTP_ORIG_WS=$(hypr_active_workspace)
  OTP_ORIG_ANIM=$(hypr_opt animations:enabled)
  OTP_ORIG_CURSOR_TIMEOUT=$(hypr_opt cursor:inactive_timeout)
  OTP_ORIG_HW_CURSORS=$(hypr_opt cursor:no_hardware_cursors)
  OTP_SESSION_ACTIVE=1
  trap otp_session_end EXIT

  # No animations (windows land instantly), hide the cursor after 1s of rest,
  # and keep the cursor off the captured frames the same way Omarchy's own
  # screenshot tool does.
  hypr_config "animations = { enabled = false }, cursor = { inactive_timeout = 1, no_hardware_cursors = 0 }" || true

  OTP_WS=$(hypr_free_workspace) || die "no free workspace id"
  hypr_create_output "$OTP_OUTPUT" "$OTP_WIDTH" "$OTP_HEIGHT" "$OTP_SCALE"
  hypr_focus_monitor "$OTP_OUTPUT"
  hypr_focus_workspace "$OTP_WS"
  sleep 0.5
  local ws_mon; ws_mon=$(hypr_json activeworkspace | jq -r '.monitor')
  [[ $ws_mon == "$OTP_OUTPUT" ]] || die "workspace $OTP_WS ended up on $ws_mon instead of $OTP_OUTPUT"
  info "virtual screen $OTP_OUTPUT (${OTP_WIDTH}x${OTP_HEIGHT} @ ${OTP_SCALE}x), workspace $OTP_WS"
}

otp_session_end() {
  [[ ${OTP_SESSION_ACTIVE:-0} == 1 ]] || return 0
  OTP_SESSION_ACTIVE=0
  trap - EXIT
  otp_scene_cleanup
  [[ -n ${OTP_ORIG_MON:-} ]] && hypr_focus_monitor "$OTP_ORIG_MON" >/dev/null 2>&1
  [[ -n ${OTP_ORIG_WS:-} ]] && hypr_focus_workspace "$OTP_ORIG_WS" >/dev/null 2>&1
  hypr_remove_output "$OTP_OUTPUT"
  local restore=()
  [[ -n ${OTP_ORIG_ANIM:-} ]] && restore+=("animations = { enabled = $OTP_ORIG_ANIM }")
  restore+=("cursor = { inactive_timeout = ${OTP_ORIG_CURSOR_TIMEOUT:-0}, no_hardware_cursors = ${OTP_ORIG_HW_CURSORS:-2} }")
  hypr_config "$(IFS=,; echo "${restore[*]}")" >/dev/null 2>&1 || true
  return 0
}

# Close whatever a scene left behind: windows on our workspace and shell overlays.
otp_scene_cleanup() {
  omarchy-menu close >/dev/null 2>&1 || true
  omarchy-shell -q lock hidePreview >/dev/null 2>&1 || true
  hypr_close_workspace_windows
  hypr_focus_monitor "$OTP_OUTPUT" >/dev/null 2>&1 || true
  hypr_focus_workspace "$OTP_WS" >/dev/null 2>&1 || true
}

# --- Launch helpers ---
otp_terminal_exec_cmd() {
  # Prints a shell command that opens the default terminal with CLASS running the given command.
  local class="$1"; shift
  if otp_have xdg-terminal-exec; then
    printf 'xdg-terminal-exec --app-id=%s -e %s' "$class" "$(otp_shell_quote "$@")"
  elif otp_have alacritty; then
    printf 'alacritty --class %s -e %s' "$class" "$(otp_shell_quote "$@")"
  elif otp_have ghostty; then
    printf 'ghostty --class=%s -e %s' "$class" "$(otp_shell_quote "$@")"
  else
    printf 'foot --app-id=%s %s' "$class" "$(otp_shell_quote "$@")"
  fi
}

# otp_launch_tui CLASS CMD [ARGS...]  -- terminal window with a TUI, prints the address
otp_launch_tui() {
  local class="$1"; shift
  hypr_exec "$(otp_terminal_exec_cmd "$class" "$@")" || return 1
  hypr_wait_window "$class"
}

# otp_launch CLASS CMD [ARGS...]  -- GUI app, prints the address
otp_launch() {
  local class="$1"; shift
  hypr_exec "$(otp_shell_quote "$@")" || return 1
  hypr_wait_window "$class" 25
}

# otp_capture SCENE [MONITOR]
otp_capture() {
  local scene="$1" mon="${2:-$OTP_OUTPUT}" png
  png="$OTP_THEME_OUT/$scene.png"
  grim -o "$mon" "$png" || { warn "grim failed for $scene"; return 1; }
  render_scene_outputs "$OTP_THEME_OUT" "$scene"
  OTP_SCENES_JSON=$(jq --arg s "$scene" --argjson v "$(render_scene_json "$OTP_THEME_OUT" "$scene")" '.[$s] = $v' <<<"$OTP_SCENES_JSON")
  info "captured $scene"
}

otp_note() { OTP_NOTES_JSON=$(jq --arg k "$1" --arg v "$2" '.[$k] = $v' <<<"$OTP_NOTES_JSON"); }

# --- Scenes ---
scene_desktop() {
  otp_settle 1
  otp_capture desktop
}

scene_terminal() {
  otp_launch_tui TUI.photo-terminal "$OTP_TERMINAL_SHOWCASE" >/dev/null || return 1
  otp_settle
  otp_capture terminal
}

scene_colors() {
  otp_have omarchy-dev-theme-preview || { warn "omarchy-dev-theme-preview not available"; return 1; }
  otp_launch_tui TUI.photo-colors bash -c 'printf "\e[?25l"; omarchy-dev-theme-preview --no-osc; sleep 3600' >/dev/null || return 1
  otp_settle
  otp_capture colors
}

scene_editor() {
  otp_have nvim || { warn "nvim not installed"; return 1; }
  otp_launch_tui TUI.photo-editor nvim "$OTP_EDITOR_FILE" >/dev/null || return 1
  otp_settle 3
  otp_capture editor
}

scene_btop() {
  otp_have btop || { warn "btop not installed"; return 1; }
  otp_launch_tui TUI.photo-btop btop >/dev/null || return 1
  otp_settle 3
  otp_capture btop
}

scene_about() {
  otp_have omarchy-launch-about || { warn "omarchy-launch-about not available"; return 1; }
  hypr_exec "omarchy-launch-about" || return 1
  hypr_wait_window org.omarchy.about >/dev/null || return 1
  otp_settle
  otp_capture about
}

scene_files() {
  otp_have nautilus || { warn "nautilus not installed"; return 1; }
  otp_launch org.gnome.Nautilus nautilus --new-window "$OTP_FILES_DIR" >/dev/null || return 1
  otp_settle 3
  otp_capture files
}

# The classic Omarchy preview: editor top-left, terminal bottom-left,
# system monitor top-right, file manager bottom-right (dwindle layout).
scene_hero() {
  local editor btop
  otp_have nvim && otp_have btop || { warn "hero needs nvim and btop"; return 1; }
  editor=$(otp_launch_tui TUI.photo-editor nvim "$OTP_EDITOR_FILE") || return 1
  btop=$(otp_launch_tui TUI.photo-btop btop) || return 1
  hypr_focus_window "$editor"
  otp_launch_tui TUI.photo-terminal "$OTP_TERMINAL_SHOWCASE" >/dev/null || return 1
  if otp_have nautilus; then
    hypr_focus_window "$btop"
    otp_launch org.gnome.Nautilus nautilus --new-window "$OTP_FILES_DIR" >/dev/null || warn "file manager did not open, continuing without it"
  fi
  # Give the top row about 62% of the height, like Omarchy's own preview.
  local dy=$(( OTP_HEIGHT * 12 / 100 ))
  hypr_focus_window "$editor"
  hypr_dispatch "hl.dsp.window.resize({ x = 0, y = $dy, relative = true })" || true
  hypr_focus_window "$btop"
  hypr_dispatch "hl.dsp.window.resize({ x = 0, y = $dy, relative = true })" || true
  hypr_focus_window "$editor"
  otp_settle 4
  otp_capture hero
}

scene_menu() {
  omarchy-menu summon root >/dev/null 2>&1 || { warn "could not open the Omarchy menu"; return 1; }
  hypr_wait_layer omarchy-menu "$OTP_OUTPUT" 8 || { warn "menu did not appear on $OTP_OUTPUT"; return 1; }
  otp_settle 1.5
  otp_capture menu
  omarchy-menu close >/dev/null 2>&1 || true
}

scene_apps() {
  omarchy-menu summon apps >/dev/null 2>&1 || { warn "could not open the app launcher"; return 1; }
  hypr_wait_layer omarchy-menu "$OTP_OUTPUT" 8 || { warn "launcher did not appear on $OTP_OUTPUT"; return 1; }
  otp_settle 2
  otp_capture apps
  omarchy-menu close >/dev/null 2>&1 || true
}

scene_notification() {
  omarchy-notification-send -u normal -t 10000 "Omarchy Theme Photograph" "This is what a notification looks like" >/dev/null 2>&1 \
    || { warn "could not send a notification"; return 1; }
  otp_settle 1.5
  otp_capture notification
  omarchy-notification-dismiss >/dev/null 2>&1 || true
}

# The lock preview is a single layer the shell puts on the first screen, so it
# is captured from whichever monitor shows it. In a single-screen VM that is
# the only screen; on a multi-monitor desktop it is your real screen.
scene_lock() {
  local mon
  omarchy-shell lock preview >/dev/null 2>&1 || { warn "lock preview is not available"; return 1; }
  mon=$(hypr_wait_layer_any omarchy-lock-preview 6) || { warn "lock preview did not appear"; omarchy-shell -q lock hidePreview; return 1; }
  otp_settle 2
  otp_capture lock "$mon"
  [[ $mon == "$OTP_OUTPUT" ]] || { otp_note lock_monitor "$mon"; info "lock preview captured from $mon (a real screen)"; }
  omarchy-shell -q lock hidePreview >/dev/null 2>&1 || true
}

scene_palette() {
  local png="$OTP_THEME_OUT/palette.png"
  render_palette "$OTP_STATE/theme/colors.toml" "$png" || { warn "no colors.toml to render"; return 1; }
  theme_colors_json >"$OTP_THEME_OUT/palette.json"
  render_scene_outputs "$OTP_THEME_OUT" palette
  OTP_SCENES_JSON=$(jq --argjson v "$(render_scene_json "$OTP_THEME_OUT" palette)" '.palette = $v' <<<"$OTP_SCENES_JSON")
  info "rendered palette"
}

# --- Driver ---
# otp_shoot_current [DISPLAY_NAME]  -- photograph whatever theme is active right now
otp_shoot_current() {
  local slug name scene
  slug=$(theme_current)
  [[ -n $slug ]] || die "Omarchy reports no current theme"
  name="${1:-$(otp_title_case "$slug")}"
  OTP_THEME_OUT="$OTP_OUT/$slug"
  mkdir -p "$OTP_THEME_OUT"
  OTP_SCENES_JSON='{}'
  OTP_NOTES_JSON='{}'
  log "Photographing '$name' ($slug) -> $OTP_THEME_OUT"

  otp_session_begin
  for scene in $OTP_SCENES; do
    if ! declare -F "scene_$scene" >/dev/null; then
      warn "unknown scene '$scene'"
      continue
    fi
    log "Scene: $scene"
    "scene_$scene" || warn "scene '$scene' failed"
    otp_scene_cleanup
  done
  otp_session_end
  theme_write_meta "$OTP_THEME_OUT" "$slug" "$name" "$OTP_SCENES_JSON" "$OTP_NOTES_JSON"
  info "wrote $OTP_THEME_OUT/meta.json"
}
