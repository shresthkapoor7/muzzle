#!/bin/zsh
set -euo pipefail

task_root="${0:A:h:h}"
app_path="${1:-$task_root/dist/Muzzle.app}"
version="${MUZZLE_VERSION:-dev}"
architecture="${MUZZLE_ARCH:-$(lipo -archs "$app_path/Contents/MacOS/Muzzle" | tr ' ' '-')}"
output_path="${2:-$task_root/dist/Muzzle-${version}-${architecture}.dmg}"

if [[ ! -d "$app_path" ]]; then
  print -u2 "App bundle not found: $app_path"
  exit 1
fi

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/muzzle-dmg.XXXXXX")"
trap 'rm -rf "$staging_directory"' EXIT

cp -R "$app_path" "$staging_directory/Muzzle.app"
ln -s /Applications "$staging_directory/Applications"
mkdir -p "${output_path:h}"
rm -f "$output_path"

hdiutil create \
  -volname "Muzzle" \
  -srcfolder "$staging_directory" \
  -format UDZO \
  -ov \
  "$output_path"

print "Packaged: $output_path"
