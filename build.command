#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/toki-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
app="$build_dir/Toki.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
./scripts/fetch-exiftool.sh "$build_dir"
mv "$build_dir/Image-ExifTool-13.55" "$app/Contents/Resources/ExifTool"
cp ThirdParty/ExifTool/Artistic-1.0.txt "$app/Contents/Resources/ExifTool/"
cp -R Sources Tests "$build_dir/"
swiftc -swift-version 5 -module-cache-path "$build_dir/swift-cache" -target "$(uname -m)-apple-macosx13.0" -O "$build_dir"/Sources/*.swift "$build_dir"/Tests/*.swift -o "$app/Contents/MacOS/Toki"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Assets/AppIcon/Toki.icns "$app/Contents/Resources/Toki.icns"
# 使用乾淨 PATH，確認所有 EXIF 讀寫與更名測試都能使用 App 內附的版本。
PATH=/usr/bin:/bin:/usr/sbin:/sbin "$app/Contents/MacOS/Toki" --self-test
xattr -cr "$app"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
fi
# --delete 避免舊版本封裝留下已移除的資源。
rsync -a --delete "$app/" dist/Toki.app/
codesign --verify --deep --strict dist/Toki.app
printf 'Built: %s/dist/Toki.app\n' "$PWD"
