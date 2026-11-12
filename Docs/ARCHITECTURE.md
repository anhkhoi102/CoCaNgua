# Kiến trúc Cờ Cá Ngựa

Trạng thái: **Phase 1, 2, 3 và 5 hoàn tất. Phase 4 đã viết mã nhưng chưa kiểm thử được.**

Hiện có: bộ luật đầy đủ, bàn cờ 2.5D, hai kiểu quân, hoạt ảnh, âm thanh, menu, cài đặt, màn thiết lập chơi đơn
(màu quân, 1–3 đối thủ máy, ba mức độ khó), ván đấu máy trọn vẹn và màn kết quả có nút chơi lại.

Chơi mạng qua Game Center: lõi dữ liệu trận có test tự động; lớp GameKit và phòng chờ mới chỉ biên dịch,
**chưa chạy lần nào với Game Center thật** vì cần tài khoản Apple Developer. Xem [GAME_CENTER_SETUP.md](GAME_CENTER_SETUP.md).

Chưa kiểm chứng khác: âm thanh chưa có ai nghe thử; hoạt ảnh (kể cả cảnh zoom khi đá quân) mới được kiểm tra qua ảnh chụp tĩnh.

## Môi trường đã kiểm tra (12/11/2026)

- Xcode 27.2, Swift 6.4.2, macOS SDK 27.2, Apple Silicon arm64.
- Deployment target: macOS 14.0. Swift language mode 6.
- Không dùng công cụ sinh project; `CoCaNgua.xcodeproj` dùng thư mục đồng bộ (file thêm vào `CoCaNgua/` tự vào target).

## Cấu trúc

```
CoCaNgua/
├── CoCaNgua.xcodeproj            target ứng dụng macOS (bundle id com.anhkhoi.cocangua)
├── CoCaNgua/                     mã ứng dụng
│   ├── App/                      CoCaNguaApp, AppCoordinator (điều hướng), SnapshotTool (chỉ bản Debug)
│   ├── Session/                  GameSession (vòng lặp ván), GameSettings (UserDefaults)
│   ├── GameClient/
│   │   ├── Rendering/            BoardLayout (vị trí logic → lưới 15×15), BoardProjection (lưới → màn hình 2.5D), PieceStyle
│   │   ├── Scenes/               BoardScene (SpriteKit): vẽ bàn, diễn hoạt, chọn quân
│   │   ├── Nodes/                HorseNode (ảnh quân dựng sẵn + vòng chọn), PieceShadow (ảnh bóng đổ)
│   │   └── Audio/                AudioManager
│   ├── Multiplayer/              GameCenterManager (đăng nhập), OnlineMatchManager (ghép trận, lượt, khôi phục), OnlineMatchStore
│   ├── UI/                       SwiftUI: MainMenu, SinglePlayerSetup, Lobby, Settings, Game (HUD, xúc xắc), MatchResult, Shared (Theme)
│   └── Resources/                Assets.xcassets, Sounds, Music, Fonts, Localizable.xcstrings
├── Packages/CoCaNguaCore/        Swift package, không phụ thuộc gì ngoài thư viện chuẩn
│   ├── Sources/GameCore/
│   │   ├── Models/               Board, Horse, Player, GameState
│   │   ├── Rules/                GameRules (cấu hình), MoveValidator, TurnManager
│   │   ├── AI/                   AIStrategy (phân tích nước đi), AIPlayer (ba mức độ)
│   │   └── Engine/               GameEngine, GameAction, GameEvent
│   ├── Sources/OnlineCore/       ActionLog, OnlineMatchData, OnlineMatchValidator (dữ liệu trận mạng, không phụ thuộc GameKit)
│   └── Tests/                    GameRulesTests, MoveValidationTests, AITests, MultiplayerStateTests
├── SupportingFiles/              Info.plist, entitlements
├── Assets/ThirdParty/            mẫu 3D gốc (CC0) của quân mã
├── Tools/                        render-knights.swift, render-seahorses.swift: dựng ảnh quân bốn màu bằng SceneKit
├── Scripts/                      build.sh, test.sh, snapshot.sh, render-pieces.sh, enable-game-center.sh
└── Docs/
```


## Quyết định kiến trúc

1. **GameCore là Swift package riêng.** Trình biên dịch bảo đảm nó không import SpriteKit/GameKit,
   và test chạy được bằng `swift test` trong vài giây mà không cần build app.
2. **Trạng thái là kiểu giá trị `Codable`.** `GameState` chứa toàn bộ ván (luật, quân, lượt, pha, số hành động).
   Lưu/khôi phục và gửi qua Game Center dùng cùng một cấu trúc.
3. **Mọi thay đổi đi qua `GameEngine.apply(_:by:)`.** Hàm này kiểm tra lượt, pha, giá trị xúc xắc và nước đi;
   hành động bị từ chối không làm đổi trạng thái. Không có đường nào khác để sửa ván.
4. **Engine không tự sinh số ngẫu nhiên.** Kết quả xúc xắc là tham số của hành động `roll(value:)`.
   Tầng trên quyết định nguồn ngẫu nhiên; hoạt ảnh xúc xắc chỉ hiển thị giá trị đã có.
5. **Engine trả về `GameEvent`** theo thứ tự xảy ra (đổ, đi, đá, đổ thêm, chuyển lượt, thắng) để tầng hiển thị diễn hoạt
   mà không phải so sánh hai trạng thái.
6. **Một nước đi được định danh bằng quân và cách dùng xúc xắc.** Hành động là `move(horse:use:)` với `use` là
   viên thứ mấy, cộng hai viên, hoặc bay; đích đến và quân bị đá do `MoveValidator` tính. Chế độ một xúc xắc
   mặc định `use` là viên duy nhất nên `move(horse:)` vẫn dùng được.
7. **`actionCount`** tăng một sau mỗi hành động được chấp nhận, dùng để phát hiện hành động trùng hoặc lệch thứ tự khi chơi mạng.
8. **Vị trí quân mã hoá thành một số nguyên** (−1 chuồng, 0–55 đường chạy, 101–106 bậc đích) để dữ liệu trận nhỏ và ổn định giữa các phiên bản.

9. **Bàn cờ 2.5D vẽ bằng mã, không dùng engine 3D lúc chạy.** Sau khi dựng, vài trăm hình của bàn được gộp thành một ảnh
   (`bakeBoard`) để SpriteKit chỉ vẽ một sprite cho phần tĩnh. Mọi hình trên bàn được mô tả trong toạ độ lưới
   15×15 (`BoardLayout`), rồi `BoardProjection` chiếu phối cảnh lên màn hình (máy quay ngẩng 50°, điểm xa nhỏ hơn).
   Bề dày của tấm bàn, chuồng và ô cờ được tạo bằng cách vẽ chồng vài lớp ở các độ cao khác nhau. `BoardScene`
   dùng `scaleMode = .resizeFill` và dựng lại bàn khi kích thước đổi, nên quân luôn khớp với ô.
   Quân là ảnh dựng sẵn từ hình khối 3D ở góc nhìn gần với bàn (38°), đứng thẳng trên ô và được vẽ theo thứ tự xa‑gần.
10. **Cảnh chỉ diễn hoạt, không quyết định.** `GameSession` gọi `GameEngine`, nhận `GameEvent`, rồi yêu cầu
    `BoardScene` diễn hoạt. Xúc xắc được quyết định trước khi hoạt ảnh lăn bắt đầu; các mặt nháy trong lúc lăn
    chỉ để trang trí.
11. **Mỗi ván một `GameSession` và một `BoardScene`.** `GameView` mang `id` của phiên để SwiftUI dựng lại
    `SpriteView`; nếu không, cảnh của ván trước vẫn hiển thị.
12. **Chuỗi giao diện viết bằng tiếng Việt ngay trong mã** và là khoá của String Catalog
    (`Localizable.xcstrings`, ngôn ngữ gốc `vi`). Thêm tiếng Anh sau này chỉ cần thêm bản dịch vào catalog.
13. **Cài đặt lưu bằng UserDefaults**, không cần SwiftData hay SQLite ở quy mô này.

## Chơi mạng

`GameSession` không biết GameKit. Nó gọi giao thức `MatchSyncing` (gửi nhật ký, chờ hành động từ xa, lấy các
hành động xử bỏ cuộc đang chờ); `OnlineMatchManager` hiện thực giao thức đó bằng `GKTurnBasedMatch`.
Mọi dữ liệu nhận về đi qua `OnlineCore.OnlineMatchValidator` trước khi tới `GameSession`.
So với tên file gợi ý trong yêu cầu: `MatchmakingManager`, `TurnBasedMatchManager` và `MatchRecoveryManager` được
gộp vào `OnlineMatchManager` vì cả ba cùng thao tác trên một `GKTurnBasedMatch`; `GameStateSerializer` là
`OnlineCore.OnlineMatchData` + `ActionLog`, đặt trong package để test được.

## Đối thủ máy

`AIStrategy.assess` mô phỏng từng nước hợp lệ bằng chính `GameEngine` và `MoveValidator`, rồi rút ra các yếu tố:
thắng ngay, giá trị quân bị đá, số bước tiến, lên bậc đích, tới cửa chuồng, ô an toàn, xác suất bị đá trước và sau
nước đi, và cơ hội đá quân ở lượt kế. Vì dùng chung bộ luật, máy tự động chơi đúng với mọi biến thể luật.
`AIPlayer.score` cộng các yếu tố đó theo trọng số. Ba mức khác nhau ở chất lượng quyết định, không đụng tới xúc xắc:

| Mức | Cách chọn nước |
|---|---|
| Dễ | 85% đi ngẫu nhiên, 15% chọn nước điểm cao nhất; không bỏ lỡ nước thắng ngay |
| Thường | Chấm điểm đầy đủ nhưng ước lượng nguy hiểm theo khoảng cách (không xét cản đường, ô an toàn) và có nhiễu ±12 điểm |
| Khó | Tính chính xác các nước đá quân của đối phương và cơ hội đá quân của mình; không có nhiễu |

Đo bằng cách cho máy đấu nhau 200 ván mỗi cặp, hai người, luật truyền thống, hạt giống cố định (`AITests`):
Khó thắng Dễ 79,5%, Thường thắng Dễ 62,5%, Khó thắng Thường 61%. Cờ Cá Ngựa phụ thuộc nhiều vào xúc xắc nên
chênh lệch không thể lớn hơn nhiều. Chưa đo với 3–4 người hay với bộ luật hiện đại.

## Game Center: khả dụng trên macOS và giới hạn

Đối chiếu với header GameKit của macOS SDK 27.2:

| API | macOS | Ghi chú |
|---|---|---|
| `GKLocalPlayer.authenticateHandler` | 10.9+ | Trên macOS trả về `NSViewController` |
| `GKTurnBasedMatch` (find, load, endTurn, saveCurrentTurn, quit, rematch) | 10.8+ | Không bị đánh dấu deprecated |
| `GKTurnBasedMatchmakerViewController` | 10.8+ | Là `NSViewController`; `matchmakingMode` từ 12.0 |
| `GKTurnBasedEventListener` qua `GKLocalPlayer.register(_:)` | 10.10+ | Nhận lượt, lời mời, kết thúc trận |
| `GKMatchRequest.recipients`, `loadFriends` | 10.10+ / 11.3+ | Mời bạn bè |
| `presentFriendRequestCreator(from: NSWindow)` | 12.0+ | Bản macOS nhận `NSWindow`, khác iOS |

Giới hạn cần biết trước khi làm Phase 4:

- **Cần tài khoản Apple Developer trả phí.** `com.apple.developer.game-center` là entitlement bị hạn chế:
  app phải được ký bằng provisioning profile và phải có bản ghi app trên App Store Connect với Game Center bật.
  Máy này hiện không có chứng chỉ ký nào (`security find-identity` trả về 0), app đang ký ad‑hoc.
  Không có điều này thì không thể đăng nhập Game Center, kể cả để thử.
- **Thử nghiệm cần ít nhất hai tài khoản Game Center** trên hai máy Mac (hoặc hai tài khoản người dùng macOS).
  Không thể tự động hoá phần này.
- **Game Center không phải máy chủ trọng tài.** Người đang giữ lượt ghi toàn bộ `matchData`. Các máy khác
  kiểm tra lại bằng cách phát lại chuỗi hành động qua `GameEngine`, nên phát hiện được nước đi sai luật,
  nhưng **không thể chứng minh xúc xắc là ngẫu nhiên** nếu không có máy chủ tin cậy. Có thể giảm rủi ro
  (ví dụ cam kết – tiết lộ hạt giống giữa các người chơi) nhưng không loại bỏ được hoàn toàn.
- **Chơi theo lượt, không theo thời gian thực.** Đối thủ có thể đi sau vài giây hoặc vài ngày; "mất kết nối"
  thể hiện bằng hạn lượt (`timeout`) và bỏ cuộc, không phải trạng thái kết nối trực tiếp.
- **Ghép trận công khai phụ thuộc số người đang tìm trận** của chính app này; với app mới có thể chờ rất lâu.
- `matchData` có giới hạn kích thước (`matchDataMaximumSize`), nên lịch sử hành động phải gọn.

Không yêu cầu nào trong bản mô tả cần máy chủ riêng, ngoại trừ chống gian lận tuyệt đối (không khả thi và đã được ghi rõ ở trên).

## Phương án đã cân nhắc và loại bỏ

**Phòng riêng qua mã phòng, không dùng Game Center** (12/11/2026): đã thiết kế và chạy thử cục bộ một dịch vụ relay
WebSocket, sau đó gỡ bỏ theo quyết định của chủ dự án vì không muốn phát sinh chi phí và công vận hành hạ tầng ngoài.
Chơi mạng quay về đúng phạm vi ban đầu: chỉ qua Game Center, không có backend riêng.

## Hoàn thiện (Phase 5)

- **Bóng đổ của quân** (`PieceShadow`): tạo một lần từ chính hình dáng quân, gồm bóng ngả theo hướng đèn chính của ảnh dựng
  (ép dẹt, xô nghiêng, mép mờ) và bóng tiếp xúc mềm dưới đế. Bóng nằm trong lớp riêng dưới mọi quân; khi quân nhảy,
  bóng trượt ra xa, nhạt và loang hơn.
- **Cảnh zoom khi đá quân** (`BoardScene.animate`): phóng to 1,9 lần vào ô va chạm ngay trước cú nhảy cuối, giữ một nhịp,
  rồi thu về trong lúc quân bị đá lộn vòng về chuồng. Thực hiện bằng cách thu phóng node `world`, không dùng `SKCameraNode`.
  Tắt cùng với "Giảm hiệu ứng" trong Cài đặt.
- **Xoay bàn** (`OrientedBoardLayout`): bàn xoay theo góc phần tư để chuồng của người chơi trên máy này nằm ở góc dưới trái,
  gần người nhìn. Chỉ là hiển thị; chiều đi và thứ tự màu quanh bàn không đổi.
- **Biểu tượng ứng dụng**: `Tools/make-icon.swift` dựng từ ảnh quân mã đỏ; `Scripts/render-pieces.sh` chạy lại nó.
- **Hiệu năng** (đo 12/11/2026, bản Debug, cửa sổ 1180×800, 15 giây chơi liên tục): trung bình 16,7 ms mỗi khung (60 khung/giây),
  p99 17,6 ms, khung chậm nhất 33,3 ms; bộ nhớ thường trú 170–260 MB. `Scripts/snapshot.sh` in lại dòng `FRAMES` mỗi lần chạy.

## Kiểm tra giao diện

`Scripts/snapshot.sh` chạy bản Debug với biến `COCANGUA_SNAPSHOT`, tự đi qua menu, cài đặt, đầu ván, chọn quân,
đá quân, giữa ván, thắng cuộc và hai kích thước cửa sổ, rồi lưu ảnh vào `snapshots/`. Công cụ này tắt tiếng
trong lúc chạy và dùng xúc xắc định trước ở vài cảnh; mã đó chỉ có trong bản Debug.

## Build và test

```bash
Scripts/build.sh debug --open
```

```bash
Scripts/test.sh
```

```bash
swift test --package-path Packages/CoCaNguaCore
```

```bash
Scripts/snapshot.sh
```

## Ngôn ngữ

- Thanh menu macOS luôn là tiếng Anh: `developmentRegion` / `DEVELOPMENT_LANGUAGE` là `en` và bundle không có thư mục `.lproj` nào, nên AppKit không đổi menu theo ngôn ngữ hệ thống.
- Trong game có hai ngôn ngữ (Việt mặc định, Anh), chọn trong Cài đặt, đổi ngay. Mọi chuỗi hiển thị đi qua `L("tiếng Việt", "English")` trong `UI/Shared/Localization.swift`; không dùng String Catalog để tránh sinh `.lproj`. `RootView` gắn `.id(settings.language)` để dựng lại màn hình khi đổi ngôn ngữ.
- Thêm chuỗi mới: luôn viết qua `L(…)`, không dùng `Text("…")` trần hay `String(localized:)`.

## Chờ hoạt ảnh trong `BoardScene`

Mọi chỗ chờ một `SKAction` phải đi qua `perform(_:on:)`. SpriteKit không gọi hàm hoàn tất khi hoạt ảnh bị gỡ (cảnh dựng lại do đổi kích thước, quay lại từ app khác), nên `placeAll(animated: false)` tự báo xong cho các hoạt ảnh đang chờ. Dùng thẳng `await node.run(…)` sẽ làm ván kẹt vĩnh viễn. Kiểm tra lại bằng `COCANGUA_BACKGROUND_TEST=resize` (bản Debug).

## iPhone

Một target cho cả macOS và iPhone (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, iOS 17+, chỉ iPhone, chỉ màn hình ngang).
Chi tiết, trạng thái kiểm thử và các bước TestFlight: `Docs/IOS_TESTFLIGHT.md`.

- `UI/Shared/Platform.swift` là lớp đệm AppKit/UIKit (`PlatformColor`, `PlatformFont`, `Color(platform:)`, `Device.isPhone`, `ScaledCanvas`, `PhoneScroll`). Mã mới không dùng thẳng `NSColor` / `UIColor`.
- Cấu hình riêng cho iOS nằm ở các khoá `[sdk=iphone*]` trong project: `SupportingFiles/Info-iOS.plist`, `SupportingFiles/CoCaNgua-iOS.entitlements`.
- Build: `Scripts/build-ios.sh` (Simulator, không cần tài khoản), `Scripts/archive-ios.sh <TEAM_ID>` (TestFlight, chưa chạy thử).
- Soát bố cục iPhone trên Mac: `COCANGUA_PHONE_PREVIEW=1 COCANGUA_ENGLISH_SHOTS=1 build/CoCaNgua.app/Contents/MacOS/CoCaNgua` (bản Debug) chụp các màn hình ở 852×393.
