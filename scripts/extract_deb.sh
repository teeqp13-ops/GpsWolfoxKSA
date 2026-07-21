#!/usr/bin/env bash
set -euo pipefail

DEB_FILE="${1:-}"
OUT_DIR="${2:-out/deb-extracted}"

if [[ -z "$DEB_FILE" ]]; then
  echo "Usage: $0 path/to/file.deb [output-dir]"
  exit 1
fi

if [[ ! -f "$DEB_FILE" ]]; then
  echo "DEB file not found: $DEB_FILE"
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/control" "$OUT_DIR/data" "$OUT_DIR/raw"

echo "Extracting: $DEB_FILE"
dpkg-deb -I "$DEB_FILE" > "$OUT_DIR/control/info.txt" || true
dpkg-deb -e "$DEB_FILE" "$OUT_DIR/control"
dpkg-deb -x "$DEB_FILE" "$OUT_DIR/data"

cp "$DEB_FILE" "$OUT_DIR/raw/"
sha256sum "$DEB_FILE" > "$OUT_DIR/SHA256SUMS.txt"

find "$OUT_DIR" -type f | sort > "$OUT_DIR/FILES.txt"

echo "Done: $OUT_DIR"