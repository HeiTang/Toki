#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive=.build/Image-ExifTool-13.55.tar.gz
checksum=5f4c81d34ad406538c2871ad72dbfceb5d9b412b2f16cbbeb4d712d270846667
mkdir -p .build
if [[ ! -f "$archive" ]]; then
  temporary=$(mktemp .build/exiftool-download.XXXXXX)
  trap 'rm -f "$temporary"' EXIT
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    https://cpan.metacpan.org/authors/id/E/EX/EXIFTOOL/Image-ExifTool-13.55.tar.gz -o "$temporary"
  printf '%s  %s\n' "$checksum" "$temporary" | shasum -a 256 -c -
  mv "$temporary" "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
# 只解壓已通過固定 SHA-256 校驗的上游套件。
tar -xzf "$archive" -C "$1" Image-ExifTool-13.55/exiftool Image-ExifTool-13.55/lib Image-ExifTool-13.55/README
