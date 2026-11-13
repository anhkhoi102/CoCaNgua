#!/usr/bin/env bash
# Đóng gói bản macOS để người dùng tải về: build Release cho cả Apple Silicon lẫn Intel rồi nén thành zip.
# Bản này ký ad-hoc (không cần tài khoản Apple Developer), nên người dùng phải cho phép mở ở lần đầu (xem README.md)
# và không dùng được Game Center.
# Dùng:  Scripts/package-macos.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
DERIVED="$PROJECT_ROOT/build/DerivedData-universal"
echo "==> xcodebuild (Release, arm64 + x86_64)…"
xcodebuild -project CoCaNgua.xcodeproj -scheme CoCaNgua -configuration Release \
           -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
           ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet
APP="$DERIVED/Build/Products/Release/CoCaNgua.app"
[[ -d "$APP" ]] || { echo "error: không thấy $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="$PROJECT_ROOT/build/release/CoCaNgua-$VERSION-macOS.zip"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
echo "==> Xong: $OUT ($(du -h "$OUT" | cut -f1), $(lipo -archs "$APP/Contents/MacOS/CoCaNgua"))"
