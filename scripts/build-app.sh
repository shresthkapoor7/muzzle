#!/bin/zsh
set -euo pipefail

task_root="${0:A:h:h}"
cd "$task_root"

swift build -c release

app_path="$task_root/dist/Website Blocker.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$task_root/App/Info.plist" "$app_path/Contents/Info.plist"
cp "$task_root/.build/release/WebsiteBlocker" "$app_path/Contents/MacOS/WebsiteBlocker"
chmod +x "$app_path/Contents/MacOS/WebsiteBlocker"
codesign --force --deep --sign - "$app_path"

echo "Built: $app_path"
