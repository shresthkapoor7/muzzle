#!/bin/zsh
set -euo pipefail

task_root="${0:A:h:h}"
app_path="${1:-$task_root/dist/Muzzle.app}"
version="${MUZZLE_VERSION:-dev}"
version="${version//\//-}"
architecture="${MUZZLE_ARCH:-$(lipo -archs "$app_path/Contents/MacOS/Muzzle" | tr ' ' '-')}"
output_path="${2:-$task_root/dist/Muzzle-${version}-${architecture}.dmg}"
background_path="$task_root/assets/dmg-background.tiff"

if [[ ! -d "$app_path" ]]; then
  print -u2 "App bundle not found: $app_path"
  exit 1
fi

if [[ ! -f "$background_path" ]]; then
  print -u2 "DMG background not found: $background_path"
  exit 1
fi

if [[ -e "$output_path" ]]; then
  print -u2 "Refusing to overwrite existing DMG: $output_path"
  exit 1
fi

if [[ -d /Volumes/Muzzle ]]; then
  print -u2 "Eject the mounted Muzzle disk image before packaging so Finder can save the correct background reference."
  exit 1
fi

if ! python3 -c 'from importlib.metadata import version; assert version("dmgbuild") == "1.6.7"' >/dev/null 2>&1; then
  print -u2 "Install the DMG packaging dependency with: python3 -m pip install -r scripts/requirements-dmg.txt"
  exit 1
fi

mkdir -p "${output_path:h}"
python3 -m dmgbuild \
  -s "$task_root/scripts/dmg-settings.py" \
  -D "app=$app_path" \
  -D "background=$background_path" \
  "Muzzle" \
  "$output_path"

print "Packaged: $output_path"
