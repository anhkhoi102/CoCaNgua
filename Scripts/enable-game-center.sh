#!/usr/bin/env bash
# Chuyển project sang ký bằng tài khoản Apple Developer và bật entitlement Game Center.
#
# Dùng:  Scripts/enable-game-center.sh <TEAM_ID>          bật (TEAM_ID gồm 10 ký tự, xem ở developer.apple.com → Membership)
#        Scripts/enable-game-center.sh --off              quay về ký ad-hoc, không Game Center
#
# Trước khi bật, cần làm xong các bước trong Docs/GAME_CENTER_SETUP.md (đăng ký App ID và bản ghi app).
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBX="$PROJECT_ROOT/CoCaNgua.xcodeproj/project.pbxproj"
ARG="${1:-}"
if [[ "$ARG" == "--off" ]]; then
    sed -i '' \
        -e 's|CODE_SIGN_ENTITLEMENTS = SupportingFiles/CoCaNgua-GameCenter.entitlements;|CODE_SIGN_ENTITLEMENTS = SupportingFiles/CoCaNgua.entitlements;|' \
        -e 's|CODE_SIGN_IDENTITY = "Apple Development";|CODE_SIGN_IDENTITY = "-";|' \
        -e 's|CODE_SIGN_STYLE = Automatic;|CODE_SIGN_STYLE = Manual;|' \
        -e 's|DEVELOPMENT_TEAM = [A-Z0-9]*;|DEVELOPMENT_TEAM = "";|' "$PBX"
    echo "Đã tắt Game Center: ký ad-hoc, không cần tài khoản."
    exit 0
fi
[[ "$ARG" =~ ^[A-Z0-9]{10}$ ]] || { echo "Dùng: $0 <TEAM_ID gồm 10 ký tự> | --off" >&2; exit 1; }
sed -i '' \
    -e 's|CODE_SIGN_ENTITLEMENTS = SupportingFiles/CoCaNgua.entitlements;|CODE_SIGN_ENTITLEMENTS = SupportingFiles/CoCaNgua-GameCenter.entitlements;|' \
    -e 's|CODE_SIGN_IDENTITY = "-";|CODE_SIGN_IDENTITY = "Apple Development";|' \
    -e 's|CODE_SIGN_STYLE = Manual;|CODE_SIGN_STYLE = Automatic;|' \
    -e "s|DEVELOPMENT_TEAM = \"\";|DEVELOPMENT_TEAM = $ARG;|" \
    -e "s|DEVELOPMENT_TEAM = [A-Z0-9]*;|DEVELOPMENT_TEAM = $ARG;|" "$PBX"
echo "Đã bật Game Center cho team $ARG."
echo "Build: xcodebuild -project CoCaNgua.xcodeproj -scheme CoCaNgua -allowProvisioningUpdates build"
echo "(hoặc mở project trong Xcode; lần đầu Xcode sẽ tự tạo provisioning profile)"
