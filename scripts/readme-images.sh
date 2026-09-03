#!/usr/bin/env bash
# Build the two pictures in the README from a photograph run:
#
#   docs/readme/four-themes.webp   the hero scene in four very different themes
#   docs/readme/scenes.webp        every scene of one theme
#
# Usage: scripts/readme-images.sh [OUT_DIR]      (default: ./out)
#
# Themes and the featured theme can be changed with OTP_README_THEMES (comma
# separated slugs) and OTP_README_FEATURED. Run it again whenever the scenes
# change, and commit the results.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
OUT="${1:-$ROOT/out}"
DOCS="$ROOT/docs/readme"
THEMES="${OTP_README_THEMES:-tokyo-night,rose-pine,osaka-jade,matte-black}"
FEATURED="${OTP_README_FEATURED:-catppuccin}"
SCENES="hero desktop terminal editor btop about menu apps notification lock palette"

BG='#111214'
FG='#ececee'
FONT=$(fc-match -f '%{file}' 'sans-serif' 2>/dev/null || true)
FONT_ARGS=()
[[ -f $FONT ]] && FONT_ARGS=(-font "$FONT")

command -v magick >/dev/null || { echo "ImageMagick (magick) is required" >&2; exit 1; }
mkdir -p "$DOCS"

title_of() {
  # Display name from meta.json, falling back to the slug.
  jq -r '.name' "$OUT/$1/meta.json" 2>/dev/null || echo "$1"
}

# --- 1. The same scene in four themes ------------------------------------------
tiles=()
IFS=',' read -r -a slugs <<<"$THEMES"
for slug in "${slugs[@]}"; do
  f="$OUT/$slug/hero.webp"
  [[ -f $f ]] || { echo "missing $f" >&2; exit 1; }
  tiles+=(-label "$(title_of "$slug")" "$f")
done
magick montage "${FONT_ARGS[@]}" -background "$BG" -fill "$FG" -pointsize 30 \
  -geometry 800x450+14+14 -tile 2x2 "${tiles[@]}" \
  -strip -quality 82 "$DOCS/four-themes.webp"

# --- 2. Every scene of one theme ------------------------------------------------
declare -A LABEL=(
  [hero]="hero: Neovim, terminal, btop and Files" [desktop]="desktop" [terminal]="terminal"
  [editor]="editor: Neovim" [btop]="btop" [about]="about" [menu]="menu" [apps]="apps"
  [notification]="notification" [lock]="lock" [palette]="palette"
)
tiles=()
for scene in $SCENES; do
  f="$OUT/$FEATURED/$scene.webp"
  [[ -f $f ]] || { echo "skipping $scene: no $f" >&2; continue; }
  tiles+=(-label "${LABEL[$scene]}" "$f")
done
magick montage "${FONT_ARGS[@]}" -background "$BG" -fill "$FG" -pointsize 22 \
  -geometry 520x293+10+10 -tile 3x -gravity center "${tiles[@]}" \
  -strip -quality 82 "$DOCS/scenes.webp"

for f in "$DOCS"/four-themes.webp "$DOCS"/scenes.webp; do
  printf '%s  %s  %s\n' "$f" "$(magick identify -format '%wx%h' "$f")" "$(du -h "$f" | cut -f1)"
done
