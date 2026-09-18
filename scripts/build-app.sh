#!/bin/zsh
set -euo pipefail

task_root="${0:A:h:h}"
cd "$task_root"

app_version="${MUZZLE_VERSION:-1.0}"
app_version="${app_version#v}"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]]; then
  echo "MUZZLE_VERSION must be a stable version such as 1.2.3 or v1.2.3" >&2
  exit 1
fi

build_arguments=(-c release)
if [[ -n "${MUZZLE_ARCH:-}" ]]; then
  build_arguments+=(--arch "$MUZZLE_ARCH")
fi

swift build "${build_arguments[@]}"

app_path="$task_root/dist/Muzzle.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Library/HelperTools"
cp "$task_root/App/Info.plist" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $app_version" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $app_version" "$app_path/Contents/Info.plist"
cp "$(swift build "${build_arguments[@]}" --show-bin-path)/Muzzle" "$app_path/Contents/MacOS/Muzzle"
cp "$(swift build "${build_arguments[@]}" --show-bin-path)/MuzzleHelper" "$app_path/Contents/Library/HelperTools/MuzzleHelper"
cp "$task_root/App/Resources/Muzzle.icns" "$app_path/Contents/Resources/Muzzle.icns"
chmod +x "$app_path/Contents/MacOS/Muzzle"
chmod +x "$app_path/Contents/Library/HelperTools/MuzzleHelper"
codesign --force --options runtime --identifier local.muzzle.helper --sign - "$app_path/Contents/Library/HelperTools/MuzzleHelper"
codesign --force --options runtime --sign - "$app_path"

echo "Built: $app_path"
