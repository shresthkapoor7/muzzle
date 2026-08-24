#!/bin/zsh
set -euo pipefail

task_root="${0:A:h:h}"
cd "$task_root"

swift build -c release

app_path="$task_root/dist/Muzzle.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$task_root/App/Info.plist" "$app_path/Contents/Info.plist"
cp "$task_root/.build/release/Muzzle" "$app_path/Contents/MacOS/Muzzle"
chmod +x "$app_path/Contents/MacOS/Muzzle"
codesign --force --deep --sign - "$app_path"

echo "Built: $app_path"
