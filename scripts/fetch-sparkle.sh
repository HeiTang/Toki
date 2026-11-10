#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.1
archive=".build/Sparkle-$version.tar.xz"
checksum=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
mkdir -p .build
if [[ ! -f "$archive" ]]; then
  temporary=$(mktemp .build/sparkle-download.XXXXXX)
  trap 'rm -f "$temporary"' EXIT
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$temporary"
  printf '%s  %s\n' "$checksum" "$temporary" | shasum -a 256 -c -
  mv "$temporary" "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
tar -xJf "$archive" -C "$1" Sparkle.framework
