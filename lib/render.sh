# shellcheck shell=bash
# Post-processing: WebP derivatives, palette image, index.json.

# render_scene_outputs DIR SCENE  -- <scene>.png -> <scene>.webp + <scene>.thumb.webp
render_scene_outputs() {
  local dir="$1" scene="$2" png
  png="$dir/$scene.png"
  [[ -f $png ]] || return 1
  magick "$png" -strip -resize "${OTP_FULL_WIDTH}>" -quality "$OTP_WEBP_QUALITY" "$dir/$scene.webp"
  magick "$png" -strip -resize "${OTP_CARD_WIDTH}>" -quality 82 "$dir/$scene.card.webp"
  magick "$png" -strip -resize "${OTP_THUMB_WIDTH}>" -quality 80 "$dir/$scene.thumb.webp"
  [[ $OTP_KEEP_PNG == 1 ]] || rm -f "$png"
}

# render_scene_json DIR SCENE  -- JSON describing the files of one scene
render_scene_json() {
  local dir="$1" scene="$2" w h cw png=null
  read -r w h < <(magick identify -format '%w %h' "$dir/$scene.webp" 2>/dev/null || echo "0 0")
  cw=$(magick identify -format '%w' "$dir/$scene.card.webp" 2>/dev/null || echo 0)
  [[ -f $dir/$scene.png ]] && png="\"$scene.png\""
  jq -n --arg full "$scene.webp" --arg card "$scene.card.webp" --arg thumb "$scene.thumb.webp" \
    --argjson png "$png" --argjson w "$w" --argjson h "$h" --argjson cw "$cw" \
    '{ full: $full, card: $card, thumb: $thumb, png: $png, width: $w, height: $h, card_width: $cw }'
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

# "1-city-view" -> "city view"; a name that is only a number stays as it is.
render_wallpaper_title() {
  local t; t=$(printf '%s' "$1" | sed -E 's/^[0-9]+[-_ ]+//; s/[-_]+/ /g; s/^ +| +$//g')
  printf '%s' "${t:-$1}"
}

# render_wallpapers SLUG  -- previews and metadata for the wallpapers that
# ship with the theme (its backgrounds/ folder). Writes wallpapers/*.webp
# under OTP_THEME_OUT, copies the originals too with OTP_KEEP_WALLPAPERS=1,
# and leaves the list in OTP_WALLPAPERS_JSON and the repo in OTP_SOURCE_JSON.
render_wallpapers() {
  local slug="$1" dir out f base ext name w h fmt bytes sha orig rel url page cur n=0
  local -A seen=()
  OTP_WALLPAPERS_JSON='[]'
  OTP_SOURCE_JSON=$(theme_source_json "$slug")
  dir="$(theme_dir "$slug")/backgrounds"
  [[ -d $dir ]] || { info "no backgrounds folder"; return 0; }
  out="$OTP_THEME_OUT/wallpapers"
  rm -rf "$out"; mkdir -p "$out"
  local repo ref path current
  repo=$(jq -r '.repo // empty' <<<"$OTP_SOURCE_JSON")
  ref=$(jq -r '.ref // empty' <<<"$OTP_SOURCE_JSON")
  path=$(jq -r '.path // empty' <<<"$OTP_SOURCE_JSON")
  current=$(theme_background)

  while IFS= read -r f; do
    base=$(basename "$f"); name=${base%.*}
    [[ -n ${seen[$name]:-} ]] && name="$base"
    seen[$name]=1
    read -r w h fmt < <(magick identify -ping -format '%w %h %m' "${f}[0]" 2>/dev/null || echo "0 0 ?")
    if (( w == 0 )); then warn "cannot read wallpaper $base"; continue; fi
    bytes=$(stat -c %s "$f")
    sha=$(sha256sum "$f" | cut -c1-64)
    magick "${f}[0]" -strip -resize "${OTP_CARD_WIDTH}>" -quality 82 "$out/$name.card.webp"
    magick "${f}[0]" -strip -resize "${OTP_THUMB_WIDTH}>" -quality 80 "$out/$name.thumb.webp"
    orig=null
    if [[ $OTP_KEEP_WALLPAPERS == 1 ]]; then
      cp -p "$f" "$out/$base"
      orig=$(jq -n --arg o "wallpapers/$base" '$o')
    fi
    url=""; page=""
    if [[ -n $repo && -n $ref ]]; then
      rel="${path:+$path/}backgrounds/$(jq -rn --arg s "$base" '$s | @uri')"
      url=$(theme_file_url "$repo" "$ref" "$rel" raw)
      page=$(theme_file_url "$repo" "$ref" "$rel" page)
    fi
    cur=false; [[ $base == "$current" ]] && cur=true
    OTP_WALLPAPERS_JSON=$(jq \
      --arg file "$base" --arg title "$(render_wallpaper_title "$name")" --arg fmt "${fmt,,}" \
      --argjson w "$w" --argjson h "$h" --argjson bytes "$bytes" --arg sha "$sha" \
      --arg thumb "wallpapers/$name.thumb.webp" --arg card "wallpapers/$name.card.webp" --argjson orig "$orig" \
      --arg url "$url" --arg page "$page" --argjson cur "$cur" \
      '. + [{
        file: $file, title: $title, format: $fmt, width: $w, height: $h, bytes: $bytes, sha256: $sha,
        thumb: $thumb, card: $card, original: $orig,
        url: (if $url == "" then null else $url end), page: (if $page == "" then null else $page end),
        current: $cur
      }]' <<<"$OTP_WALLPAPERS_JSON")
    n=$((n + 1))
  done < <(find "$dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' \) | sort -V)
  info "$n wallpapers"
}

# render_qa OUT_DIR  -- find themes whose shell scenes are not to be trusted.
# A menu, launcher or lock picture that is (nearly) identical to the desktop
# picture means the popup never appeared; a picture that is one flat colour
# means nothing was painted at all. Prints one line per suspect theme and
# returns 1 when there are any.
render_qa() {
  local out="$1" dir slug scene r bad found=0 line
  for dir in "$out"/*/; do
    slug=$(basename "$dir")
    [[ -f $dir/meta.json && -f $dir/desktop.thumb.webp ]] || continue
    bad=""
    for scene in menu apps lock notification; do
      [[ -f $dir/$scene.thumb.webp ]] || continue
      # compare exits 1 whenever the pictures differ, which is the normal case
      r=$({ magick compare -metric RMSE "$dir/desktop.thumb.webp" "$dir/$scene.thumb.webp" null: 2>&1 || true; } | sed -nE 's/.*\(([0-9.e-]+)\).*/\1/p')
      [[ -n $r ]] || continue
      if [[ $scene == notification ]]; then line=0.004; else line=0.01; fi
      awk -v r="$r" -v l="$line" 'BEGIN { exit !(r < l) }' && bad="$bad $scene=same-as-desktop"
    done
    for scene in desktop hero terminal editor btop about menu apps notification lock; do
      [[ -f $dir/$scene.thumb.webp ]] || continue
      r=$(magick "$dir/$scene.thumb.webp" -format '%[fx:standard_deviation]' info: 2>/dev/null || echo 1)
      awk -v r="$r" 'BEGIN { exit !(r < 0.003) }' && bad="$bad $scene=flat"
    done
    if [[ -n $bad ]]; then echo "$slug:$bad"; found=1; fi
  done
  (( found == 0 )) && info "no suspect pictures under $out"
  return $found
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
