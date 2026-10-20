#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -m)" == arm64 ]] || { echo 'Release requires Apple Silicon' >&2; exit 1; }
app="$PWD/dist/Toki.app"
python3 scripts/verify-app.py "$app"
work=$(mktemp -d "${TMPDIR:-/tmp}/toki-package.XXXXXX")
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then hdiutil detach "$work/mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
zip="$PWD/dist/Toki-macos-arm64.zip"
dmg="$PWD/dist/Toki-macos-arm64.dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${SIGN_IDENTITY:-}" ]] || { echo 'Notarization requires SIGN_IDENTITY' >&2; exit 1; }
  notary_options=(--keychain-profile "$NOTARY_PROFILE")
  if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then notary_options+=(--keychain "$NOTARY_KEYCHAIN"); fi
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/notarize.zip"
  xcrun notarytool submit "$work/notarize.zip" "${notary_options[@]}" --wait --timeout 15m
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi
mkdir "$work/image"
ditto "$app" "$work/image/Toki.app"
ln -s /Applications "$work/image/Applications"
cp docs/INSTALL.txt "$work/image/安裝說明.txt"
hdiutil create -quiet -volname Toki -srcfolder "$work/image" -ov -format UDZO "$dmg"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
  xcrun notarytool submit "$dmg" "${notary_options[@]}" --wait --timeout 15m
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
hdiutil verify "$dmg"
hdiutil attach "$dmg" -mountpoint "$work/mount" -nobrowse -readonly -quiet
mounted=true
python3 scripts/verify-app.py "$work/mount/Toki.app"
[[ "$(readlink "$work/mount/Applications")" == /Applications ]]
# 模擬從 DMG 安裝，測試會產生暫存素材，所以先複製到可寫入目錄。
ditto "$work/mount/Toki.app" "$work/installed/Toki.app"
hdiutil detach "$work/mount" -quiet
mounted=false
PATH=/usr/bin:/bin:/usr/sbin:/sbin "$work/installed/Toki.app/Contents/MacOS/Toki" --self-test
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
ditto -x -k "$zip" "$work/unzip"
python3 scripts/verify-app.py "$work/unzip/Toki.app"
diff -qr "$app" "$work/unzip/Toki.app"
(cd dist && shasum -a 256 Toki-macos-arm64.dmg Toki-macos-arm64.zip > SHA256SUMS.txt)
printf 'Packaged DMG, ZIP and SHA256SUMS.txt in %s/dist\n' "$PWD"
