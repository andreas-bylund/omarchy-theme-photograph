# shellcheck shell=bash
# Post-processing: WebP derivatives, palette image, index.json.

# render_scene_outputs DIR SCENE  -- <scene>.png -> <scene>.webp + <scene>.thumb.webp
render_scene_outputs() {
  local dir="$1" scene="$2" png
  png="$dir/$scene.png"
  [[ -f $png ]] || return 1
  magick "$png" -strip -resize "${OTP_FULL_WIDTH}>" -quality "$OTP_WEBP_QUALITY" "$dir/$scene.webp"
  magick "$png" -strip -resize "${OTP_THUMB_WIDTH}>" -quality 80 "$dir/$scene.thumb.webp"
  [[ $OTP_KEEP_PNG == 1 ]] || rm -f "$png"
}

# render_scene_json DIR SCENE  -- JSON describing the files of one scene
render_scene_json() {
  local dir="$1" scene="$2" w h png=null
  read -r w h < <(magick identify -format '%w %h' "$dir/$scene.webp" 2>/dev/null || echo "0 0")
  [[ -f $dir/$scene.png ]] && png="\"$scene.png\""
  jq -n --arg full "$scene.webp" --arg thumb "$scene.thumb.webp" --argjson png "$png" --argjson w "$w" --argjson h "$h" \
    '{ full: $full, thumb: $thumb, png: $png, width: $w, height: $h }'
}

render_hex_is_light() {
  local hex="${1#\#}" r g b
  [[ ${#hex} -eq 6 ]] || return 1
  r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))
  (( (299 * r + 587 * g + 114 * b) / 1000 > 140 ))
}

# render_palette COLORS_TOML OUT_PNG  -- swatch sheet of the theme palette
render_palette() {
  local toml="$1" out="$2" tmp rowfiles=() tiles=() row key hex fg i=0
  local rows=(
    "background darker_background dark_background lighter_background selection muted"
    "dark_foreground foreground light_foreground bright_foreground accent"
    "red orange yellow green cyan blue magenta brown"
    "bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta"
  )
  local colors; colors=$(theme_colors_json "$toml")
  local fontargs=() fontfile=""
  if otp_have fc-match; then
    fontfile=$(fc-match -f '%{file}' 'sans-serif:bold' 2>/dev/null || true)
    [[ -f $fontfile ]] && fontargs=(-font "$fontfile")
  fi
  tmp=$(mktemp -d)
  for row in "${rows[@]}"; do
    tiles=()
    for key in $row; do
      hex=$(jq -r --arg k "$key" '.[$k] // empty' <<<"$colors")
      [[ -n $hex ]] || continue
      if render_hex_is_light "$hex"; then fg="#000000"; else fg="#ffffff"; fi
      magick -size 240x160 "xc:$hex" "${fontargs[@]}" -gravity south -fill "$fg" \
        -pointsize 22 -annotate +0+44 "$key" -pointsize 18 -annotate +0+16 "$hex" "$tmp/$key.png"
      tiles+=("$tmp/$key.png")
    done
    (( ${#tiles[@]} > 0 )) || continue
    magick "${tiles[@]}" +append "$tmp/row$i.png"
    rowfiles+=("$tmp/row$i.png")
    i=$((i + 1))
  done
  if (( ${#rowfiles[@]} == 0 )); then rm -rf "$tmp"; return 1; fi
  magick -background none -gravity west "${rowfiles[@]}" -append "$out"
  rm -rf "$tmp"
}

# render_index OUT_DIR  -- aggregate every <theme>/meta.json into index.json
render_index() {
  local out="$1" f files=()
  for f in "$out"/*/meta.json; do [[ -f $f ]] && files+=("$f"); done
  if (( ${#files[@]} == 0 )); then
    warn "no meta.json files found under $out"
    return 1
  fi
  jq -s --arg at "$(otp_now_iso)" '{ generated_at: $at, count: length, themes: sort_by(.name) }' "${files[@]}" >"$out/index.json"
  info "wrote $out/index.json (${#files[@]} themes)"
}
