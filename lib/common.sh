# shellcheck shell=bash
# Shared helpers: configuration defaults, logging, small utilities.
# Sourced by bin/omarchy-theme-photograph; OTP_ROOT is set there.

# --- Configuration (every value can be overridden from the environment) ---
: "${OTP_WIDTH:=1920}"          # logical width of the virtual screen
: "${OTP_HEIGHT:=1080}"         # logical height of the virtual screen
: "${OTP_SCALE:=2}"             # HiDPI scale; physical pixels = logical * scale
: "${OTP_OUTPUT:=OTP}"          # name of the headless Hyprland output we create
: "${OTP_SETTLE:=2}"            # seconds to wait after windows appear before shooting
: "${OTP_OUT:=$PWD/out}"        # output directory
: "${OTP_KEEP_PNG:=0}"          # keep the lossless PNG next to the WebP files
: "${OTP_FULL_WIDTH:=1920}"     # width of the full-size WebP
: "${OTP_CARD_WIDTH:=1280}"     # width of the medium WebP (gallery cards on HiDPI screens)
: "${OTP_THUMB_WIDTH:=640}"     # width of the thumbnail WebP
: "${OTP_WEBP_QUALITY:=85}"
: "${OTP_THEME_SETTLE:=4}"      # seconds to let Omarchy re-tint apps after a theme switch
: "${OTP_SHELL_RESTART_EVERY:=1}"   # in a batch, restart the Omarchy shell before every Nth theme (0 = never)
: "${OTP_FILES_DIR:=$HOME}"     # folder shown in the file manager scenes
: "${OTP_WALLPAPERS:=1}"        # list the theme's wallpapers and make previews of them
: "${OTP_KEEP_WALLPAPERS:=0}"   # also copy the original wallpaper files into the output
: "${OTP_OMARCHY_REPO:=https://github.com/basecamp/omarchy}"  # where stock themes come from
: "${OTP_THEMES_FILE:=$OTP_ROOT/themes.json}"

OTP_DEFAULT_SCENES="desktop hero terminal editor btop about menu apps notification lock palette"
# shellcheck disable=SC2034  # used by bin/omarchy-theme-photograph
OTP_ALL_SCENES="$OTP_DEFAULT_SCENES colors files"
: "${OTP_SCENES:=$OTP_DEFAULT_SCENES}"

# --- Logging ---
if [[ -t 2 ]]; then
  C_INFO=$'\e[1;34m' C_WARN=$'\e[1;33m' C_ERR=$'\e[1;31m' C_OFF=$'\e[0m'
else
  C_INFO="" C_WARN="" C_ERR="" C_OFF=""
fi
log()  { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*" >&2; }
info() { printf '    %s\n' "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

# --- Utilities ---
otp_have() { command -v "$1" >/dev/null 2>&1; }

# Quote arguments for /bin/sh (used when handing commands to Hyprland's exec).
otp_shell_quote() {
  local out="" a
  for a in "$@"; do out+="'${a//\'/\'\\\'\'}' "; done
  printf '%s' "${out% }"
}

otp_settle() { sleep "${1:-$OTP_SETTLE}"; }
otp_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

otp_require() {
  local missing=() c
  for c in "$@"; do otp_have "$c" || missing+=("$c"); done
  (( ${#missing[@]} == 0 )) || die "missing required commands: ${missing[*]}"
}

# Title-case a slug: "tokyo-night" -> "Tokyo Night"
otp_title_case() {
  printf '%s' "$1" | sed 's/-/ /g' | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2) } 1'
}
