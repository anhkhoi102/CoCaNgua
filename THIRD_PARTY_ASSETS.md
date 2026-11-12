# Tài nguyên bên thứ ba

Mọi tài nguyên dưới đây đã được tải về và tích hợp ngày 12/11/2026. Giấy phép được đọc từ file license kèm trong
từng gói (và trên trang nguồn). Không có tài nguyên nào lấy từ trò chơi thương mại hay do mô hình tạo ảnh sinh ra.

| Tài nguyên | Dùng cho | File trong project | Tác giả | Nguồn | Giấy phép | Yêu cầu ghi công |
|---|---|---|---|---|---|---|
| Stylized Chess Pieces (mẫu 3D `Knight_White.glb`) | Kiểu quân "Quân mã" (mặc định) | Mẫu gốc: `Assets/ThirdParty/lyricsz-StylizedChess/`. Ảnh dựng: `Resources/Assets.xcassets/Knights.spriteatlas` | lyricsz | https://opengameart.org/content/stylized-chess-pieces | CC0 1.0 (ghi trên trang nguồn; gói không kèm file giấy phép) | Không |
| Boardgame Pack v2 (thư mục Bonus) | Tiếng đổ xúc xắc, đặt quân, đá quân | `Sounds/dice_roll_1`, `dice_roll_2`, `dice_shake`, `land`, `capture` | Kenney Vleugels (kenney.nl) | https://opengameart.org/content/boardgame-pack | CC0 1.0 | Không |
| Interface Sounds | Tiếng bấm nút, chọn quân, lỗi, ra quân, lên bậc, tới lượt, bước quân | `Sounds/ui_click`, `ui_select`, `ui_error`, `release`, `climb`, `your_turn`, `step_1` | Kenney (kenney.nl) | https://opengameart.org/content/interface-sounds | CC0 1.0 | Không |
| 85 Short Music Jingles | Nhạc hiệu thắng cuộc (`jingles_STEEL07`) | `Sounds/win` | Kenney Vleugels (kenney.nl) | https://opengameart.org/content/85-short-music-jingles | CC0 1.0 | Không |
| Cozy Puzzle Title | Nhạc nền lặp | `Music/menu_theme.mp3` | MintoDog | https://opengameart.org/content/cozy-puzzle-title | CC0 1.0 | Không |
| Baloo 2 (phông biến thiên) | Toàn bộ chữ giao diện, có dấu tiếng Việt | `Fonts/Baloo2.ttf` | Ek Type — Copyright 2019 The Baloo 2 Project Authors (https://github.com/EkType/Baloo2) | https://github.com/google/fonts/tree/main/ofl/baloo2 | SIL OFL 1.1 | Phải kèm file giấy phép: `Fonts/Baloo2-OFL.txt` (đã đóng gói trong app) |

## Chuyển đổi

- Âm thanh gốc là OGG Vorbis, macOS không phát trực tiếp được. Đã giải mã bằng `oggdec` rồi nén lại thành AAC (`.m4a`, 128 kbps) bằng `afconvert`. Nội dung không bị chỉnh sửa.
- Nhạc nền dùng nguyên file MP3 gốc.
- **Quân mã** là ảnh dựng từ mẫu 3D CC0, lưới đa giác giữ nguyên. `Tools/render-knights.swift` tự đọc hình học trong file GLB
  (SceneKit không đọc được định dạng này), bỏ vật liệu gốc, phủ nhựa bóng theo màu người chơi, chiếu ba đèn cố định,
  dựng cùng một góc nhìn cho bốn màu và thêm viền trắng mảnh. Kết quả: bốn ảnh PNG 384×512 trong một sprite atlas.
- **Biểu tượng ứng dụng** (`AppIcon.appiconset`) do `Tools/make-icon.swift` vẽ: ảnh quân mã đỏ nói trên đứng giữa bốn mảnh ghép bốn màu và một viên xúc xắc vẽ bằng mã.

## Tự tạo, không dùng asset bên thứ ba

- **Kiểu quân "Cá ngựa"** (chọn trong Cài đặt). Không tìm được asset cá ngựa miễn phí nào dùng được (xem mục cuối), nên quân được
  tạo hoàn toàn bằng mã: `Tools/render-seahorses.swift` ghép các khối cơ bản của SceneKit (cầu, nón, trụ, xuyến)
  thành một quân kiểu Ludo có thân cá ngựa, chiếu ba đèn cố định, dựng cùng một góc nhìn cho bốn màu và thêm
  viền trắng mảnh. `Scripts/render-pieces.sh` chạy cả hai công cụ dựng quân và ghi bốn ảnh PNG 384×512 vào
  `Resources/Assets.xcassets/Seahorses.spriteatlas`. Hình khối được mô tả bằng mã do trợ lý lập trình AI viết trong dự án này; không dùng mô hình tạo ảnh
  và không dùng tác phẩm của bên thứ ba.

## Vẽ bằng mã, không dùng asset

- **Bàn cờ 2.5D**: vẽ bằng SpriteKit theo lưới 15×15 rồi chiếu phối cảnh, để giữ đúng tỉ lệ ở mọi kích thước cửa sổ.
- **Xúc xắc**: gói Boardgame Pack có sẵn hình xúc xắc nhưng chỉ 64 px, bị mờ trên màn hình Retina; xúc xắc được vẽ bằng SwiftUI.
- **Nút, khung, hạt hiệu ứng**: vẽ bằng mã cho đồng bộ với phông và bảng màu.

## Đã cân nhắc nhưng không dùng

- Kenney Board Game Icons (`chess_knight`, CC0): là quân ở bản đầu, đã thay vì trông phẳng như biểu tượng.
- 3D Chess Pieces (tunakron, CC0): quân mã góc cạnh kiểu low‑poly; đã dựng thử, chọn mẫu của lyricsz vì tròn trịa hơn.
- Quaternius Farm Animals Pack (mẫu 3D `Horse`, CC0): đã thử dựng thành tượng ngựa, bỏ vì quân cần là cá ngựa.
- Cá ngựa có sẵn: các mẫu 3D tìm được trên CGTrader, RenderHub, TurboSquid đều là hàng bán hoặc giấy phép hạn chế;
  OpenGameArt chỉ có sprite 8×8 pixel; biểu tượng `seahorse` của game-icons.net (Delapouite, CC BY 3.0) là hình phẳng.
- Kenney UI Pack, Game Icons, Particle Pack, Casino Audio, Impact Sounds: không cần sau khi các phần trên được vẽ bằng mã hoặc đã có âm thanh tương đương.
- Pixel Chess Pieces (Lucas312): CC‑BY / CC‑BY‑SA, không phải CC0.
- CraftPix freebies: giấy phép riêng, cấm phân phối lại file gốc.
- Poly Pizza: chỉ có mô hình 3D.
