# Bản iPhone và TestFlight

Cờ Cá Ngựa dùng **một target cho cả macOS và iPhone** (cùng mã nguồn, cùng bundle id `com.anhkhoi.cocangua`).
Nhờ chung bundle id, Mac và iPhone dùng chung một bản ghi app và chung Game Center: người chơi trên iPhone và trên Mac
vào được cùng một phòng.

## Trạng thái (12/11/2026)

| Việc | Trạng thái |
|---|---|
| Mã biên dịch cho iOS (Simulator SDK) | Đã build thành công: `Scripts/build-ios.sh` |
| Bố cục iPhone nằm ngang | Đã chạy trên iPhone 18 Pro Simulator (iOS 27.2): menu, thiết lập, màn chơi. **Chưa chạy trên máy thật**; Cài đặt, phòng chờ và màn kết quả mới soát bằng ảnh chụp trên Mac |
| Thao tác chạm trên bàn cờ | Đã thử trên Simulator: đổ xúc xắc, chạm chọn quân, đá quân; chuyển sang app khác rồi quay lại thì ván chạy tiếp |
| Game Center (đăng nhập, phòng theo mã, trận theo lượt) | Giao thức phòng đã thử bằng đường truyền giả lập; phần qua Game Center thật **chưa thử** (cần tài khoản Apple Developer) |
| Archive và tải lên TestFlight | Script đã viết, **chưa chạy** (cần tài khoản Apple Developer) |

Chạy trên Simulator: `Scripts/build-ios.sh`, rồi `xcrun simctl install booted <app>` và `xcrun simctl launch booted com.anhkhoi.cocangua`.
Thêm `SIMCTL_CHILD_COCANGUA_DEBUG_MIDGAME=1` trước lệnh launch (bản Debug) để mở thẳng một thế cờ giữa ván.
Simulator trên máy 8 GB RAM phản hồi chậm vài giây; đó không phải tốc độ của app trên iPhone thật.

## Khác biệt giữa hai nền tảng

- iPhone chỉ chạy màn hình ngang. Giao diện dùng chung với macOS, được thu nhỏ theo `Device.uiScale` và có vài bố cục riêng
  (`Device.isPhone`): menu chia hai cột; ở màn chơi bàn cờ chiếm phần lớn màn hình, khung xúc xắc bên phải, người chơi thu nhỏ thành một hàng ở mép dưới; các màn dài cho cuộn.
- Bàn cờ nhận chạm thay cho chuột; vùng bấm quanh quân rộng hơn 35%.
- Không có nút Thoát và mục Cửa sổ trong Cài đặt.
- Âm thanh dùng phiên `ambient`: tôn trọng nút gạt im lặng, không ngắt nhạc đang nghe.
- Biểu tượng iOS là ảnh vuông kín 1024 px (`icon_ios_1024.png`), do `Tools/make-icon.swift` tạo cùng lúc với biểu tượng macOS.

## Phòng chơi trực tiếp theo mã (qua Game Center, không máy chủ riêng)

Dùng trận thời gian thực `GKMatch` của Game Center: miễn phí, không có máy chủ riêng. Mã nguồn: `Multiplayer/RoomManager.swift`,
giao thức trong `OnlineCore` (`RoomCode`, `RoomPlan`, `RoomMessage`).

**Đã kiểm chứng:** giao thức (sảnh chờ, bắt đầu, đồng bộ nước đi, bot lấp chỗ trống, bot chơi thay người rời, chủ phòng rời) chạy đúng trên
đường truyền giả lập trong một máy: `COCANGUA_ROOM_TEST=1 build/CoCaNgua.app/Contents/MacOS/CoCaNgua` (bản Debug).
**Chưa kiểm chứng:** mọi thứ đi qua Game Center thật (ghép theo mã, kết nối, độ trễ) vì cần tài khoản Apple Developer và hai tài khoản Game Center.

Cách hoạt động:

- Mã phòng 6 chữ số được gửi cho Game Center làm `playerGroup` của yêu cầu ghép trận; Game Center chỉ nối những máy gửi cùng mã.
  Chữ số đầu là số chỗ của phòng (2–4).
- Chủ phòng: **Chơi mạng → Tạo phòng và lấy mã**. Sảnh chờ hiện mã, danh sách người đã vào và các chỗ còn trống.
- Khách: **Vào phòng bằng mã**. Khách thấy sảnh và chờ chủ phòng.
- Chủ phòng bấm **Bắt đầu** khi đã có ít nhất một người khác. Chỗ còn trống do bot chơi (bot chạy trên máy chủ phòng, độ khó lấy từ thiết lập chơi đơn của chủ phòng).
- Trong ván, mỗi máy tự đổ xúc xắc và đi quân của mình rồi gửi hành động; máy nhận phát lại bằng `GameEngine` và kiểm tra quyền đi, nên nước sai luật bị từ chối.
- Ai rời phòng giữa ván thì bot của chủ phòng chơi thay. Chủ phòng rời thì ván kết thúc với mọi người.

Giới hạn đã biết:

- Mọi người phải mở app suốt ván; rời ra là không vào lại được ván đó.
- Trước khi có người thứ hai, Game Center chưa tạo kết nối nào, nên chủ phòng chỉ thấy mình; khách nhập mã khi chưa có chủ phòng sẽ chờ ở trạng thái "Đang tìm phòng".
- Sau khi có hai người, người thứ ba, thứ tư vào được là nhờ chủ phòng tiếp tục gọi ghép thêm (`addPlayers`); chưa thử thật.
- Hai phòng khác nhau trùng mã (xác suất 1/100.000 cho cùng số chỗ) sẽ bị nối lẫn.
- Kiểu trận theo lượt cũ (`GKTurnBasedMatch`: mời qua danh sách bạn bè, ghép với người lạ) vẫn còn trong thẻ "Trận theo lượt".

## Các bước đưa lên TestFlight

Cần tài khoản Apple Developer (99 USD/năm). Các bước 1–3 làm một lần.

1. **Đăng nhập Xcode**: Xcode → Settings → Accounts → thêm Apple ID của tài khoản Developer. Ghi lại Team ID (10 ký tự).
2. **App ID**: developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → tạo App ID `com.anhkhoi.cocangua`,
   bật **Game Center**. (Nếu đã tạo cho bản Mac thì dùng lại.)
3. **Bản ghi app**: App Store Connect → Apps → New App → chọn cả iOS (và macOS nếu muốn), bundle id như trên.
   Trong mục Game Center của app: bật Game Center. Xem thêm `Docs/GAME_CENTER_SETUP.md`.
4. **Bật ký**: `Scripts/enable-game-center.sh <TEAM_ID>`.
5. **Tải lên**: `Scripts/archive-ios.sh <TEAM_ID>`. Mỗi lần tải lên phải tăng số build (`CURRENT_PROJECT_VERSION` trong project,
   hoặc để App Store Connect tự tăng: script đã bật `manageAppVersionAndBuildNumber`).
6. **TestFlight**: App Store Connect → TestFlight. Chờ bản build xử lý xong (vài phút tới vài chục phút).
   - *Internal Testing*: thêm tối đa 100 người thuộc team, dùng được ngay.
   - *External Testing*: tối đa 10.000 người qua email hoặc link công khai, bản đầu tiên phải qua Beta App Review.
7. Người thử cài app **TestFlight** trên iPhone, nhận lời mời, cài Cờ Cá Ngựa. Mỗi người cần đăng nhập Game Center
   (Cài đặt → Game Center) bằng Apple ID riêng.

## Danh sách kiểm thử trên iPhone (chưa chạy mục nào)

1. App mở ở màn hình ngang, không bị che bởi tai thỏ / Dynamic Island.
2. Chơi đơn trọn một ván: chạm chọn quân, chọn ô đích, đổ xúc xắc, tự đi.
3. Chuyển sang app khác rồi quay lại giữa ván: ván chạy tiếp.
4. Đổi ngôn ngữ, đổi mẫu quân, âm lượng.
5. Đăng nhập Game Center, tạo phòng 4 chỗ, vào bằng mã từ một tài khoản khác, chủ phòng bấm Bắt đầu (hai bot), chơi hết ván.
   Thử thêm: người thứ ba vào sau, khách rời giữa ván (bot chơi thay), chủ phòng rời (khách được báo), nhập mã sai.
6. Phòng iPhone ↔ Mac.
7. Toàn bộ danh sách 15 mục trong `Docs/GAME_CENTER_SETUP.md`.
