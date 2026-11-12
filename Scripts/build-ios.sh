#!/usr/bin/env bash
# Build bản iPhone cho iOS Simulator (không cần tài khoản Apple Developer) để kiểm tra mã biên dịch được.
# Dùng:  Scripts/build-ios.sh            # Debug
#        Scripts/build-ios.sh release
# Bản cài lên máy thật / TestFlight: Scripts/archive-ios.sh (xem Docs/IOS_TESTFLIGHT.md).
set -euo pipefail
case "${1:-debug}" in
    release) CONFIG="Release" ;;
    debug)   CONFIG="Debug" ;;
    *) echo "Dùng: $0 [debug|release]" >&2; exit 1 ;;
esac
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
DERIVED="$PROJECT_ROOT/build/DerivedData-iOS"
echo "==> xcodebuild iOS Simulator ($CONFIG)…"
xcodebuild -project CoCaNgua.xcodeproj -scheme CoCaNgua -configuration "$CONFIG" \
           -derivedDataPath "$DERIVED" -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' build -quiet \
           2> >(grep -v "failed with exit code 0 but produced no further output" >&2)
APP="$DERIVED/Build/Products/$CONFIG-iphonesimulator/CoCaNgua.app"
[[ -d "$APP" ]] || { echo "error: không thấy $APP" >&2; exit 1; }
echo "==> Xong: $APP"
echo "    Cài vào simulator đang mở:  xcrun simctl install booted \"$APP\" && xcrun simctl launch booted com.anhkhoi.cocangua"
