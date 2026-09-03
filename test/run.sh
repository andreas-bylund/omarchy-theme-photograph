#!/usr/bin/env bash
# Tests for the parts that do not need a running Hyprland: naming, quoting,
# parsing the theme list, reading colors.toml and rendering the palette sheet.
# Runs anywhere with bash, jq and python3; the palette test needs ImageMagick
# and is skipped without it.
set -uo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export OTP_ROOT="$ROOT"
export HOME="${HOME:-/tmp}"
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=../lib/hypr.sh
source "$ROOT/lib/hypr.sh"
# shellcheck source=../lib/theme.sh
source "$ROOT/lib/theme.sh"
# shellcheck source=../lib/render.sh
source "$ROOT/lib/render.sh"

FIXTURES="$ROOT/test/fixtures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok    $1"; }
bad() { fail=$((fail + 1)); echo "FAIL  $1"; }
skip() { echo "skip  $1"; }
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ $got == "$want" ]]; then ok "$name"; else bad "$name: expected '$want', got '$got'"; fi
}

# --- Naming a theme after its repository, the way omarchy-theme-install does ---
assert_eq "name: omarchy-X-theme" "$(theme_name_from_repo https://github.com/x/omarchy-rustleaf-theme)" rustleaf
assert_eq "name: .git suffix" "$(theme_name_from_repo https://github.com/x/omarchy-rustleaf-theme.git)" rustleaf
assert_eq "name: scp-style url" "$(theme_name_from_repo git@github.com:x/omarchy-Foo-theme.git)" foo
assert_eq "name: bare name" "$(theme_name_from_repo https://github.com/x/aetheria)" aetheria
assert_eq "name: only prefix" "$(theme_name_from_repo https://github.com/x/omarchy-theme-bar)" theme-bar
assert_eq "normalize: spaces and case" "$(theme_normalize 'Tokyo Night')" tokyo-night
assert_eq "title case" "$(otp_title_case rose-pine)" "Rose Pine"

# --- Quoting ---
assert_eq "shell quote" "$(otp_shell_quote a 'b c' "it's")" "'a' 'b c' 'it'\\''s'"
assert_eq "lua string" "$(hypr_lua_str 'plain')" '[=[plain]=]'
assert_eq "lua string escalates brackets" "$(hypr_lua_str 'x]=]y')" '[==[x]=]y]==]'

# --- colors.toml ---
colors=$(theme_colors_json "$FIXTURES/colors.toml")
assert_eq "colors: accent" "$(jq -r .accent <<<"$colors")" '#7aa2f7'
assert_eq "colors: count" "$(jq 'length' <<<"$colors")" 9
assert_eq "colors: mode is not a colour" "$(jq -r '.mode // "absent"' <<<"$colors")" absent

# --- Python list parser agrees with the bash naming rule ---
py_name() {
  python3 - "$1" <<'EOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("ftl", os.environ["FTL"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(m.theme_name_from_repo(sys.argv[1]))
EOF
}
export FTL="$ROOT/scripts/fetch-theme-list.py"
assert_eq "python name: omarchy-X-theme" "$(py_name https://github.com/x/omarchy-rustleaf-theme)" rustleaf
assert_eq "python name: scp-style" "$(py_name git@github.com:x/omarchy-Foo-theme.git)" foo

python3 "$ROOT/scripts/fetch-theme-list.py" --from "$FIXTURES/themes-page.html" --no-stock --out "$TMP/themes.json" >/dev/null
assert_eq "list: count" "$(jq '.count' "$TMP/themes.json")" 2
assert_eq "list: install name" "$(jq -r '.themes[0].install_name' "$TMP/themes.json")" aetheria
assert_eq "list: html entities" "$(jq -r '.themes[0].name' "$TMP/themes.json")" 'Aetheria & Co'
assert_eq "list: sorted by name" "$(jq -r '[.themes[].name] | join(",")' "$TMP/themes.json")" 'Aetheria & Co,Rustleaf'

# --- Palette sheet ---
if otp_have magick; then
  if render_palette "$FIXTURES/colors.toml" "$TMP/palette.png" && [[ -f $TMP/palette.png ]]; then
    width=$(magick identify -format '%w' "$TMP/palette.png")
    # The widest row in the fixture has four colours (red, yellow, green, blue), 240 px each.
    assert_eq "palette: width" "$width" 960
  else
    bad "palette: render_palette failed"
  fi
else
  skip "palette: ImageMagick not installed"
fi

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
