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
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Assets/AppIcon/Toki.icns "$app/Contents/Resources/Toki.icns"
framework="$app/Contents/Frameworks/Sparkle.framework"
sparkle_flags=()
if [[ -n "${TOKI_SPARKLE_PUBLIC_KEY:-}" ]]; then
  if ! [[ "$TOKI_SPARKLE_PUBLIC_KEY" =~ '^[A-Za-z0-9+/]{43}=$' ]]; then
    print -u2 'TOKI_SPARKLE_PUBLIC_KEY must be a base64 Ed25519 public key'
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $TOKI_SPARKLE_PUBLIC_KEY" "$app/Contents/Info.plist"
  mkdir -p "$app/Contents/Frameworks"
  /bin/bash scripts/fetch-sparkle.sh "$app/Contents/Frameworks"
  sparkle_flags=(-F "$app/Contents/Frameworks" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
fi
xcrun --sdk macosx swiftc -swift-version 5 -module-cache-path "$build_dir/swift-cache" -target "$(uname -m)-apple-macosx13.0" -O \
  "${sparkle_flags[@]}" "$build_dir"/Sources/*.swift "$build_dir"/Tests/*.swift -o "$app/Contents/MacOS/Toki"
xattr -cr "$app"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  if [[ -d "$framework" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$framework/Autoupdate" "$framework/Updater.app" "$framework"/Versions/Current/XPCServices/*.xpc "$framework"
  fi
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --deep --sign - "$app"
fi
# 使用乾淨 PATH，確認所有 EXIF 讀寫與更名測試都能使用 App 內附的版本。
PATH=/usr/bin:/bin:/usr/sbin:/sbin "$app/Contents/MacOS/Toki" --self-test
# --delete 避免舊版本封裝留下已移除的資源。
rsync -a --delete "$app/" dist/Toki.app/
codesign --verify --deep --strict dist/Toki.app
printf 'Built: %s/dist/Toki.app\n' "$PWD"
