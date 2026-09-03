# shellcheck shell=bash
# Omarchy theme helpers: switching, installing and reading theme metadata.

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
OTP_STATE="$HOME/.local/state/omarchy/current"
OTP_USER_THEMES="$HOME/.config/omarchy/themes"

theme_current()  { cat "$OTP_STATE/theme.name" 2>/dev/null; }
theme_exists()   { [[ -d $OTP_USER_THEMES/$1 || -d $OMARCHY_PATH/themes/$1 ]]; }
theme_is_stock() { [[ -d $OMARCHY_PATH/themes/$1 ]]; }

theme_dir() {
  if [[ -d $OTP_USER_THEMES/$1 ]]; then echo "$OTP_USER_THEMES/$1"; else echo "$OMARCHY_PATH/themes/$1"; fi
}

# Same normalisation omarchy-theme-set applies to a name.
theme_normalize() { printf '%s' "$1" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-'; }

# Same rule omarchy-theme-install uses to name a theme after its repo URL.
theme_name_from_repo() {
  local path="$1"
  [[ $path != *"://"* && $path == *:* && ${path%%:*} != */* ]] && path="${path#*:}"
  basename -- "$path" .git | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]'
}

theme_repo_url() {
  local d; d=$(theme_dir "$1")
  [[ -d $d/.git ]] && git -C "$d" remote get-url origin 2>/dev/null
  return 0
}

# Wait until Omarchy reports NAME as current, then give the re-tint hooks a moment.
theme_wait() {
  local name="$1" i
  for i in $(seq 1 150); do
    [[ $(theme_current) == "$name" ]] && break
    sleep 0.1
  done
  [[ $(theme_current) == "$name" ]] || return 1
  sleep "$OTP_THEME_SETTLE"
}

theme_set() {
  local name; name=$(theme_normalize "$1")
  theme_exists "$name" || { warn "theme '$name' is not installed"; return 1; }
  log "Applying theme $name"
  omarchy-theme-set "$name" >/dev/null 2>&1 || { warn "omarchy-theme-set $name failed"; return 1; }
  theme_wait "$name"
}

theme_install() {
  local repo="$1" name; name=$(theme_name_from_repo "$repo")
  log "Installing $repo as '$name'"
  omarchy-theme-install "$repo" >/dev/null 2>&1 || { warn "omarchy-theme-install $repo failed"; return 1; }
  theme_wait "$name"
}

theme_remove() { omarchy-theme-remove "$1" >/dev/null 2>&1 || true; }

theme_mode() {
  local d="$OTP_STATE/theme"
  if [[ -f $d/light.mode ]]; then
    echo light
  else
    awk -F'"' '/^mode[ \t]*=/ { print $2; found = 1 } END { if (!found) print "dark" }' "$d/colors.toml" 2>/dev/null
  fi
}

theme_colors_json() {
  local toml="${1:-$OTP_STATE/theme/colors.toml}"
  [[ -f $toml ]] || { echo '{}'; return; }
  awk -F'=' '$1 ~ /^[a-z_]+[ \t]*$/ && $2 ~ /"#/ { k = $1; v = $2; gsub(/[ \t]/, "", k); gsub(/[ \t"]/, "", v); print k, v }' "$toml" \
    | jq -Rn '[inputs | split(" ") | select(length == 2) | { (.[0]): .[1] }] | add // {}'
}

theme_background() { basename "$(readlink -f "$OTP_STATE/background" 2>/dev/null)" 2>/dev/null; }

# Normalise a git remote to a plain https URL: git@github.com:o/r.git -> https://github.com/o/r
theme_repo_https() {
  local u="$1"
  u=${u%/}; u=${u%.git}
  case $u in
    git@*:*) u=${u#git@}; u="https://${u/://}" ;;
    ssh://git@*) u="https://${u#ssh://git@}" ;;
    http://*) u="https://${u#http://}" ;;
  esac
  printf '%s' "$u"
}

# Where a theme's files can be fetched from, as JSON {repo, ref, path}: the
# repository, a ref that will not move (the checked-out commit, or Omarchy's
# release tag for a stock theme) and the path of the theme inside the repo.
theme_source_json() {
  local slug="$1" d repo ref
  if theme_is_stock "$slug"; then
    ref="v$(theme_omarchy_version | sed -E 's/-[0-9]+$//')"
    jq -n --arg repo "$OTP_OMARCHY_REPO" --arg ref "$ref" --arg path "themes/$slug" '{ repo: $repo, ref: $ref, path: $path }'
    return
  fi
  d=$(theme_dir "$slug")
  repo=$(theme_repo_url "$slug")
  ref=$(git -C "$d" rev-parse HEAD 2>/dev/null || true)
  if [[ -z $repo || -z $ref ]]; then echo null; return; fi
  jq -n --arg repo "$(theme_repo_https "$repo")" --arg ref "$ref" '{ repo: $repo, ref: $ref, path: "" }'
}

# theme_file_url REPO REF PATH raw|page  -- link to one file in a hosted repo.
# Prints nothing for hosts it does not know.
theme_file_url() {
  local repo="$1" ref="$2" path="$3" kind="$4" host proj
  host=${repo#https://}; host=${host%%/*}
  proj=${repo#https://"$host"/}
  case $host in
    github.com)
      if [[ $kind == raw ]]; then echo "https://raw.githubusercontent.com/$proj/$ref/$path"; else echo "$repo/blob/$ref/$path"; fi ;;
    gitlab.com | *gitlab*)
      if [[ $kind == raw ]]; then echo "$repo/-/raw/$ref/$path"; else echo "$repo/-/blob/$ref/$path"; fi ;;
    codeberg.org | *gitea* | *forgejo*)
      if [[ $kind == raw ]]; then echo "$repo/raw/commit/$ref/$path"; else echo "$repo/src/commit/$ref/$path"; fi ;;
  esac
}

theme_omarchy_version() { omarchy version 2>/dev/null || cat "$OMARCHY_PATH/version" 2>/dev/null || echo unknown; }
theme_hyprland_version() { hyprctl version -j 2>/dev/null | jq -r '.tag // .version // "unknown"'; }

# theme_write_meta OUT_DIR SLUG NAME SCENES_JSON NOTES_JSON [WALLPAPERS_JSON] [SOURCE_JSON]
theme_write_meta() {
  local out="$1" slug="$2" name="$3" scenes="$4" notes="$5" wallpapers="${6:-[]}" source="${7:-null}" stock=false
  theme_is_stock "$slug" && stock=true
  jq -n \
    --arg name "$name" --arg slug "$slug" --arg repo "$(theme_repo_url "$slug")" --argjson stock "$stock" \
    --arg mode "$(theme_mode)" --argjson colors "$(theme_colors_json)" --arg background "$(theme_background)" \
    --arg omarchy "$(theme_omarchy_version)" --arg hypr "$(theme_hyprland_version)" --arg captured "$(otp_now_iso)" \
    --argjson w "$OTP_WIDTH" --argjson h "$OTP_HEIGHT" --argjson s "$OTP_SCALE" \
    --argjson scenes "$scenes" --argjson notes "$notes" --argjson wallpapers "$wallpapers" --argjson source "$source" \
    '{
      name: $name, slug: $slug, repo: (if $repo == "" then null else $repo end), stock: $stock, mode: $mode,
      colors: $colors, background: $background, source: $source,
      omarchy_version: $omarchy, hyprland_version: $hypr, captured_at: $captured,
      resolution: { width: $w, height: $h, scale: $s },
      scenes: $scenes, wallpapers: $wallpapers, notes: $notes
    }' >"$out/meta.json"
}
