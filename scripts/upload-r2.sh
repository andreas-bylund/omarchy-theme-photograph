#!/usr/bin/env bash
# Sync the output directory to a Cloudflare R2 bucket with rclone.
#
# Usage: scripts/upload-r2.sh <out-dir> <remote:bucket[/prefix]>
#
# One-time rclone setup (https://developers.cloudflare.com/r2/api/tokens/):
#   rclone config create r2 s3 provider=Cloudflare \
#     access_key_id=... secret_access_key=... \
#     endpoint=https://<account-id>.r2.cloudflarestorage.com acl=private
#
# Images are immutable per capture, so they get a long cache lifetime; the
# index is refreshed often, so it gets a short one. PNG files are left out.
set -euo pipefail

OUT="${1:?usage: upload-r2.sh <out-dir> <remote:bucket[/prefix]>}"
DEST="${2:?usage: upload-r2.sh <out-dir> <remote:bucket[/prefix]>}"

command -v rclone >/dev/null || { echo "rclone is not installed (pacman -S rclone)" >&2; exit 1; }
[[ -f $OUT/index.json ]] || { echo "no index.json in $OUT - run 'omarchy-theme-photograph index' first" >&2; exit 1; }

rclone sync "$OUT" "$DEST" \
  --exclude '*.png' --exclude 'index.json' \
  --checksum --transfers 16 --fast-list \
  --header-upload 'Cache-Control: public, max-age=31536000' -v

rclone copyto "$OUT/index.json" "$DEST/index.json" \
  --header-upload 'Cache-Control: public, max-age=300' -v

echo "Uploaded to $DEST"
