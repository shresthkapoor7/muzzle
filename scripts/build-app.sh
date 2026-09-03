#!/bin/zsh
set -euo pipefail

task_root="${0:A:h:h}"
cd "$task_root"

build_arguments=(-c release)
if [[ -n "${MUZZLE_ARCH:-}" ]]; then
  build_arguments+=(--arch "$MUZZLE_ARCH")
fi

swift build "${build_arguments[@]}"

app_path="$task_root/dist/Muzzle.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$task_root/App/Info.plist" "$app_path/Contents/Info.plist"
cp "$(swift build "${build_arguments[@]}" --show-bin-path)/Muzzle" "$app_path/Contents/MacOS/Muzzle"
chmod +x "$app_path/Contents/MacOS/Muzzle"
codesign --force --deep --sign - "$app_path"

echo "Built: $app_path"
