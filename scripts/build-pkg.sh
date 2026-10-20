#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --package-path "$ROOT"
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/usr/local/bin" "$STAGE/usr/local/share/screen-edges"
cp "$ROOT/.build/release/screen-edges" "$STAGE/usr/local/bin/screen-edges"
cp "$ROOT/scripts/install.sh" "$ROOT/scripts/uninstall.sh" "$STAGE/usr/local/share/screen-edges/"
chmod 755 "$STAGE/usr/local/bin/screen-edges" "$STAGE/usr/local/share/screen-edges/"*.sh
pkgbuild \
  --root "$STAGE" \
  --identifier com.rostyslavkhomyk.screen-edges \
  --version 1.0.0 \
  --install-location / \
  "$ROOT/ScreenEdges.pkg"
rm -rf "$STAGE"
echo "Wrote $ROOT/ScreenEdges.pkg"
echo "After installing the package, run: /usr/local/share/screen-edges/install.sh"
