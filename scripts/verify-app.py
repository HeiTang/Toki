#!/usr/bin/env python3
"""Verify the same bundle contract in CI, ZIPs and mounted DMGs."""
from pathlib import Path
import base64
import filecmp
import os
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
source = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
actual = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
public_key = actual.pop('SUPublicEDKey', None)
sparkle = app / 'Contents/Frameworks/Sparkle.framework/Sparkle'
assert sparkle.is_file() == (public_key is not None), 'Sparkle framework and public key must be bundled together'
if public_key is not None:
    assert len(base64.b64decode(public_key, validate=True)) == 32, 'Invalid Sparkle Ed25519 public key'
assert actual == source, 'Packaged Info.plist differs from source'
assert actual['CFBundleName'] == actual['CFBundleDisplayName'] == 'Toki'
assert actual['CFBundlePackageType'] == 'APPL'
assert actual['CFBundleShortVersionString'] and actual['CFBundleVersion']
binary = app / 'Contents/MacOS' / actual['CFBundleExecutable']
assert binary.is_file() and os.access(binary, os.X_OK), 'Missing executable'
architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
assert architectures == ['arm64'], f'Unexpected architectures: {architectures}'
assert actual['CFBundleIconFile'] == 'Toki.icns'
icon = app / 'Contents/Resources/Toki.icns'
assert icon.read_bytes() == (root / 'Assets/AppIcon/Toki.icns').read_bytes(), 'Icon mismatch'
assert icon.read_bytes().startswith(b'icns'), 'Invalid ICNS header'
tool = app / 'Contents/Resources/ExifTool/exiftool'
assert tool.is_file() and os.access(tool, os.X_OK), 'Missing bundled ExifTool'
environment = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin')
assert subprocess.check_output([str(tool), '-ver'], env=environment, text=True).strip() == '13.55'
assert (tool.parent / 'README').is_file() and (tool.parent / 'Artistic-1.0.txt').is_file()
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
if len(sys.argv) == 3:
    original = Path(sys.argv[2]).resolve()
    paths = {entry.relative_to(app) for entry in app.rglob('*')}
    assert paths == {entry.relative_to(original) for entry in original.rglob('*')}, 'Packaged paths differ from original App'
    for path in paths:
        before, after = original / path, app / path
        if before.is_symlink() or after.is_symlink():
            same = before.is_symlink() and after.is_symlink() and os.readlink(before) == os.readlink(after)
        elif before.is_dir() and after.is_dir():
            same = True
        else:
            same = before.is_file() and after.is_file() and filecmp.cmp(before, after, shallow=False)
        assert same, f'Packaged entry differs from original App: {path}'
print(f"Verified Toki {actual['CFBundleShortVersionString']} build {actual['CFBundleVersion']} (arm64), bundled ExifTool 13.55")
