#!/usr/bin/env bash
# Deterministic terminal content for the "terminal" and "hero" scenes.
# Prints a fake shell session that exercises the 16 ANSI colours, bold/dim
# text and a diff, then keeps the window open for the camera. The content is
# re-rendered whenever the window is resized and shrinks to a compact version
# in short windows, so nothing scrolls out of view.

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/showcase" && pwd)"
E=$'\e'

prompt() { printf '%s[1;32m❯%s[0m %s[1m%s%s[0m\n' "$E" "$E" "$E" "$1" "$E"; }

listing() {
  if command -v eza >/dev/null 2>&1; then
    (cd "$DIR" && eza -la --icons --group-directories-first --no-user --no-time 2>/dev/null || eza -la --icons)
  else
    (cd "$DIR" && ls -la --color=always)
  fi
}

git_log() {
  printf '* %s[33mf3a9c21%s[0m %s[1;36m(HEAD -> main, origin/main)%s[0m Add palette scene\n' "$E" "$E" "$E" "$E"
  printf '* %s[33m8b71e04%s[0m Photograph the lock screen from the right monitor\n' "$E" "$E"
  printf '* %s[33m2c0d9aa%s[0m %s[1;35m(tag: v0.1.0)%s[0m Capture the Omarchy menu and app launcher\n' "$E" "$E" "$E" "$E"
  (( ${1:-5} > 3 )) || return 0
  printf '* %s[33m91be7d3%s[0m Render WebP thumbnails for the website\n' "$E" "$E"
  printf '* %s[33m0e4f5c8%s[0m Initial commit\n' "$E" "$E"
}

git_diff() {
  printf '%s[1mlib/scenes.sh%s[0m | 24 %s[32m+++++++++++++++++++%s[0m%s[31m-----%s[0m\n' "$E" "$E" "$E" "$E" "$E" "$E"
  printf '%s[36m@@ -41,7 +41,9 @@%s[0m scene_palette() {\n' "$E" "$E"
  printf '%s[31m-  render_palette "$toml" "$png"%s[0m\n' "$E" "$E"
  printf '%s[32m+  render_palette "$toml" "$png" || return 1%s[0m\n' "$E" "$E"
  printf '%s[32m+  theme_colors_json >"$OTP_THEME_OUT/palette.json"%s[0m\n' "$E" "$E"
}

palette() {
  local c
  printf '%s[2mnormal %s[0m' "$E" "$E"
  for c in 0 1 2 3 4 5 6 7; do printf '%s[4%dm    %s[0m' "$E" "$c" "$E"; done
  printf '\n%s[2mbright %s[0m' "$E" "$E"
  for c in 0 1 2 3 4 5 6 7; do printf '%s[10%dm    %s[0m' "$E" "$c" "$E"; done
  printf '\n'
  printf '%s[31mred%s[0m %s[32mgreen%s[0m %s[33myellow%s[0m %s[34mblue%s[0m %s[35mmagenta%s[0m %s[36mcyan%s[0m %s[1mbold%s[0m %s[2mdim%s[0m %s[3mitalic%s[0m %s[4munderline%s[0m\n' \
    "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E" "$E"
}

render() {
  local rows
  rows=$(tput lines 2>/dev/null || echo 40)
  printf '%s[?25l' "$E"   # hide the cursor
  clear
  if (( rows < 26 )); then
    # Compact: fits in about 14 rows.
    prompt "ls"
    listing
    prompt "git log --oneline --graph -n 3"
    git_log 3
    palette
    prompt ""
  else
    prompt "cd ~/Projects/omarchy-theme-photograph && ls"
    listing
    echo
    prompt "git log --oneline --graph -n 5"
    git_log 5
    echo
    prompt "git diff --stat HEAD~1"
    git_diff
    echo
    prompt "omarchy theme current"
    cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo "unknown"
    echo
    palette
    echo
    prompt ""
  fi
}

size=$(stty size 2>/dev/null)
render
while :; do
  sleep 0.3
  s=$(stty size 2>/dev/null)
  if [[ $s != "$size" ]]; then
    size=$s
    render
  fi
done
