#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="${1:-package}"
OUT_DEB="${2:-GPSPlus_Custom.deb}"

if [[ ! -d "$PACKAGE_DIR/DEBIAN" ]]; then
  echo "Missing $PACKAGE_DIR/DEBIAN/control"
  exit 1
fi

fakeroot dpkg-deb --build "$PACKAGE_DIR" "$OUT_DEB"
sha256sum "$OUT_DEB" > "$OUT_DEB.sha256"

echo "Built: $OUT_DEB"