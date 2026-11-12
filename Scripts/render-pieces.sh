#!/usr/bin/env bash
# Dựng lại ảnh quân cờ bốn màu cho cả hai kiểu quân và ghi vào asset catalog:
#   - Quân mã cờ vua: từ mẫu 3D CC0 trong Assets/ThirdParty/lyricsz-StylizedChess
#   - Quân cá ngựa:   hình khối tạo bằng mã
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
OUT="$(mktemp -d -t cocangua-pieces)"
swift Tools/render-knights.swift Assets/ThirdParty/lyricsz-StylizedChess/Knight_White.glb "$OUT"
swift Tools/render-seahorses.swift "$OUT"
write_atlas() {   # $1 = tên atlas, $2 = tiền tố ảnh
    local atlas="CoCaNgua/Resources/Assets.xcassets/$1.spriteatlas"
    mkdir -p "$atlas"
    printf '{ "info" : { "author" : "xcode", "version" : 1 } }\n' > "$atlas/Contents.json"
    for color in red blue green yellow; do
        local set="$atlas/$2_$color.imageset"
        mkdir -p "$set"
        cp "$OUT/$2_$color.png" "$set/$2_$color@2x.png"
        cat > "$set/Contents.json" <<JSON
{
  "images" : [
    { "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x", "filename" : "$2_$color@2x.png" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
    done
    echo "Đã cập nhật $atlas"
}
write_atlas Knights knight
write_atlas Seahorses seahorse
# Biểu tượng ứng dụng dựng từ ảnh quân mã đỏ vừa tạo.
swift "$PROJECT_ROOT/Tools/make-icon.swift" \
    "$PROJECT_ROOT/CoCaNgua/Resources/Assets.xcassets/Knights.spriteatlas/knight_red.imageset/knight_red@2x.png" \
    "$PROJECT_ROOT/CoCaNgua/Resources/Assets.xcassets/AppIcon.appiconset"
