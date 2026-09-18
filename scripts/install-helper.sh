#!/bin/zsh
set -euo pipefail

if [[ "$EUID" != 0 || -z "${SUDO_UID:-}" || "$#" != 1 ]]; then
  echo 'Usage: sudo scripts/install-helper.sh /Applications/Muzzle.app' >&2
  exit 1
fi
app_bundle="${1:A}"
exec "$app_bundle/Contents/Library/HelperTools/MuzzleHelper" --install "$app_bundle" "$SUDO_UID"
