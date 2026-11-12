#!/usr/bin/env bash
# Đóng gói bản iPhone và tải lên App Store Connect để phát qua TestFlight.
#
# Dùng:  Scripts/archive-ios.sh <TEAM_ID>            archive + tải lên
#        Scripts/archive-ios.sh <TEAM_ID> --no-upload chỉ tạo file .ipa trong build/ios-export
#
# Cần: Xcode đã đăng nhập tài khoản Apple Developer (Xcode → Settings → Accounts) và đã làm xong
# các bước chuẩn bị trong Docs/IOS_TESTFLIGHT.md. CHƯA CHẠY THỬ được vì máy chưa có tài khoản.
set -euo pipefail
TEAM="${1:-}"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "Dùng: $0 <TEAM_ID gồm 10 ký tự> [--no-upload]" >&2; exit 1; }
DESTINATION="upload"
[[ "${2:-}" == "--no-upload" ]] && DESTINATION="export"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
ARCHIVE="$PROJECT_ROOT/build/CoCaNgua-iOS.xcarchive"
EXPORT="$PROJECT_ROOT/build/ios-export"
OPTIONS="$PROJECT_ROOT/build/ExportOptions-iOS.plist"
mkdir -p "$PROJECT_ROOT/build"

echo "==> Archive (Release, iPhone)…"
xcodebuild -project CoCaNgua.xcodeproj -scheme CoCaNgua -configuration Release \
           -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
           -derivedDataPath "$PROJECT_ROOT/build/DerivedData-iOS" -allowProvisioningUpdates \
           DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
           archive

cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> Xuất bản ($DESTINATION)…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
           -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates
if [[ "$DESTINATION" == "upload" ]]; then
    echo "==> Đã tải lên. Vài phút sau bản build hiện trong App Store Connect → TestFlight."
else
    echo "==> File .ipa nằm trong $EXPORT"
fi
