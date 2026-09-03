#!/usr/bin/env bash
# Install omarchy-theme-photograph for the current user.
#
# Puts a symlink in ~/.local/bin that points at this checkout, so updating is
# a `git pull` and nothing is copied. Pass --uninstall to remove the link.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BIN_DIR="${OTP_BIN_DIR:-$HOME/.local/bin}"
LINK="$BIN_DIR/omarchy-theme-photograph"

if [[ ${1:-} == --uninstall ]]; then
  if [[ -L $LINK ]]; then
    rm -f "$LINK"
    echo "Removed $LINK"
  else
    echo "Nothing to remove at $LINK"
  fi
  exit 0
fi

mkdir -p "$BIN_DIR"
ln -sfn "$ROOT/bin/omarchy-theme-photograph" "$LINK"
echo "Installed $LINK -> $ROOT/bin/omarchy-theme-photograph"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not on your PATH. Omarchy adds it at login; open a new terminal or add it yourself." ;;
esac

echo
"$LINK" doctor || true
