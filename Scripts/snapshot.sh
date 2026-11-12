#!/usr/bin/env bash
# Tự chạy qua các màn hình và lưu ảnh PNG của cửa sổ vào ./snapshots rồi thoát.
# Ứng dụng chạy trong sandbox nên ghi vào thư mục tmp của container; script này chép ảnh ra.
# Cần bản Debug: Scripts/build.sh debug
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/CoCaNgua.app/Contents/MacOS/CoCaNgua"
[[ -x "$APP_BIN" ]] || { echo "Hãy build trước: Scripts/build.sh debug" >&2; exit 1; }
CONTAINER_TMP="$HOME/Library/Containers/com.anhkhoi.cocangua/Data/tmp/snapshots"
COCANGUA_SNAPSHOT=1 "$APP_BIN"
rm -rf "$PROJECT_ROOT/snapshots"
mkdir -p "$PROJECT_ROOT/snapshots"
cp "$CONTAINER_TMP"/*.png "$PROJECT_ROOT/snapshots/"
ls -1 "$PROJECT_ROOT/snapshots"
