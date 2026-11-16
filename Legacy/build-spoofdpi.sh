#!/usr/bin/env bash
# macOS 10.15 uyumlu SpoofDPI v0.12.0'ı Intel için derler.
# Go 1.21 veya 1.22 gerekir (Go 1.23+ ile derlenen programlar macOS 11 ister).
# Kullanım: Legacy/build-spoofdpi.sh <çıktı-dosyası>
set -euo pipefail
OUT="$1"
TAG="v0.12.0"
GO="${GO:-go}"

ver="$("$GO" env GOVERSION 2>/dev/null || true)"
case "$ver" in
  go1.21*|go1.22*) ;;
  *) echo "✖ Go 1.21 veya 1.22 gerekli (bulunan: ${ver:-yok}). GO=/yol/go ile belirtebilirsiniz." >&2; exit 1 ;;
esac

SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
git clone -q --depth 1 --branch "$TAG" https://github.com/xvzc/SpoofDPI "$SRC" 2>/dev/null
( cd "$SRC" && GOTOOLCHAIN=local GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 \
    "$GO" build -trimpath -ldflags='-s -w' -o "$OUT" ./cmd/spoofdpi )
echo "✔ SpoofDPI $TAG (Intel, macOS 10.15+): $OUT"
