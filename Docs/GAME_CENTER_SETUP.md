# Bật và kiểm thử chơi mạng qua Game Center

Trạng thái (12/11/2026): **mã đã viết và biên dịch được, nhưng chưa từng chạy với Game Center thật.**
Máy phát triển chưa có tài khoản Apple Developer nên không thể đăng nhập Game Center từ ứng dụng.
Không được coi chơi mạng là hoạt động cho tới khi qua hết bảng kiểm thử ở cuối tài liệu.

## Cái gì đã được kiểm chứng, cái gì chưa

| Phần | Trạng thái |
|---|---|
| Dữ liệu trận: mã hoá, phát lại, từ chối nước sai luật, phát hiện sửa lịch sử, sai người giữ lượt, xử bỏ cuộc (`OnlineCore`) | Có 24 test tự động, đều đạt |
| `GameSession` nhận hành động từ xa và gửi hành động của mình | Biên dịch được; chơi đơn vẫn chạy đúng; đường chạy chơi mạng chưa được chạy |
| Đăng nhập, ghép trận, mời bạn, gửi/nhận lượt, rời trận, đấu lại (`CoCaNgua/Multiplayer`) | Chỉ biên dịch. **Chưa chạy lần nào** |
| Phòng chờ | Hiển thị được; khi chưa có entitlement thì báo "Chưa dùng được Game Center" |

## Việc bạn cần làm một lần

1. Đăng ký Apple Developer Program (trả phí hằng năm) tại https://developer.apple.com/programs/.
2. Trong Xcode → Settings → Accounts, đăng nhập Apple ID đó. Xcode sẽ tạo chứng chỉ "Apple Development".
3. Tại https://developer.apple.com/account → Identifiers, tạo App ID `com.anhkhoi.cocangua` (loại macOS) và bật **Game Center**.
   Nếu bundle id này đã có người dùng, đổi `PRODUCT_BUNDLE_IDENTIFIER` trong project rồi dùng id mới ở mọi bước.
4. Tại https://appstoreconnect.apple.com → My Apps, tạo bản ghi app macOS với bundle id đó. Không cần nộp app;
   chỉ cần bản ghi tồn tại thì Game Center mới nhận ra ứng dụng. Trong mục Game Center của bản ghi, bật Game Center.
5. Lấy Team ID (10 ký tự) ở developer.apple.com → Membership, rồi chạy:

```bash
Scripts/enable-game-center.sh <TEAM_ID>
```

6. Build bằng Xcode (⌘R) hoặc:

```bash
xcodebuild -project CoCaNgua.xcodeproj -scheme CoCaNgua -allowProvisioningUpdates build
```

`Scripts/build.sh` kiểm tra chữ ký ad‑hoc nên sau khi bật Game Center hãy build bằng Xcode. Để quay lại ký ad‑hoc:

```bash
Scripts/enable-game-center.sh --off
```

Game Center cho app chưa phát hành chạy ở môi trường sandbox; người thử phải là tài khoản thuộc team hoặc được thêm
làm người thử trong App Store Connect.

## Cách hoạt động

- **Theo lượt, không thời gian thực.** Trận là một `GKTurnBasedMatch`. Người giữ lượt đổ xúc xắc và đi quân trên máy
  mình; sau mỗi hành động dữ liệu được lưu (`saveCurrentTurn`), hết lượt thì chuyển cho người kế (`endTurn`).
  Đối thủ có thể đi ngay hoặc sau vài ngày; hạn mỗi lượt là mặc định của Game Center (một tuần).
- **Dữ liệu trận** (định dạng 4) chỉ gồm luật, màu của từng chỗ ngồi và nhật ký hành động (một byte mỗi hành động,
  gồm cả đổ hai xúc xắc, cộng điểm và bay).
  Mỗi máy tự phát lại nhật ký bằng `GameEngine`; không ai gửi "trạng thái" cho ai.
- **Kiểm tra khi nhận dữ liệu:** nước sai luật hay sai lượt, lịch sử bị sửa hoặc cắt bớt, lượt chuyển sai người,
  phiên bản dữ liệu mới hơn ứng dụng. Gặp lỗi thì ứng dụng dừng trận và báo, không tự "sửa".
- **Rời trận:** "Tạm rời" giữ trận để vào lại từ phòng chờ. "Bỏ cuộc" gỡ quân của bạn; trận tiếp tục cho người khác.
  Người hết hạn lượt hoặc thoát từ ứng dụng Game Center được máy đang giữ lượt xử bỏ cuộc.
- **Ghép trận công khai:** Game Center tạo trận ngay và điền chỗ trống khi có người khác cũng tìm trận cùng số người.
  Không có đối thủ giả; chỗ chưa có người hiện "Đang chờ người chơi".
- **Mời bạn bè:** dùng giao diện mời của Game Center (`GKTurnBasedMatchmakerViewController`, chế độ chỉ mời).
- **Luật của trận** là bộ luật trong Cài đặt của người tạo trận tại lúc họ đi nước đầu tiên.

## Giới hạn đã biết

- **Xúc xắc do máy của người đổ sinh ra.** Các máy khác kiểm tra được mọi nước đi nhưng không chứng minh được xúc xắc
  là ngẫu nhiên. Người sửa ứng dụng có thể chọn giá trị xúc xắc. Không có máy chủ tin cậy thì không loại bỏ được điều này.
- Phát hiện sửa lịch sử dựa trên nhật ký máy này đã thấy (lưu trong UserDefaults); cài lại ứng dụng thì mất mốc so sánh.
- Trên macOS không có thông báo đẩy khi ứng dụng tắt theo cách của iOS; ứng dụng hỏi lại Game Center mỗi 20 giây khi đang mở trận.
- Không có trò chuyện, không có bảng xếp hạng, không có thành tích (theo yêu cầu).

## Bảng kiểm thử (cần ít nhất hai tài khoản Game Center trên hai máy Mac)

Chưa mục nào được chạy.

| # | Kịch bản | Kết quả |
|---|---|---|
| 1 | Đăng nhập Game Center, phòng chờ hiện tên người chơi | Chưa thử |
| 2 | Tạo trận 2 người bằng "Mời bạn bè", máy kia nhận lời mời và vào trận | Chưa thử |
| 3 | "Tìm trận công khai" từ hai máy được ghép với nhau | Chưa thử |
| 4 | Đổ xúc xắc, đi quân, đá quân: máy kia thấy đúng diễn biến | Chưa thử |
| 5 | Đổ được 6 và đi tiếp trong cùng lượt; lượt chỉ chuyển khi hết quyền đổ | Chưa thử |
| 6 | Trọn một ván 2 người tới màn kết quả ở cả hai máy | Chưa thử |
| 7 | Trận 3 người và 4 người | Chưa thử |
| 8 | Tắt ứng dụng giữa trận, mở lại, vào trận từ "Trận của bạn" | Chưa thử |
| 9 | Tắt giữa lượt sau khi đã đổ xúc xắc: vào lại không được đổ lần nữa | Chưa thử |
| 10 | Mất mạng khi đang gửi lượt: hiện "đang thử lại", có mạng thì gửi tiếp | Chưa thử |
| 11 | Một người "Bỏ cuộc" khi tới lượt và khi không tới lượt | Chưa thử |
| 12 | Một người thoát trận từ ứng dụng Game Center | Chưa thử |
| 13 | "Đấu lại" sau khi trận kết thúc | Chưa thử |
| 14 | Hai máy chạy hai phiên bản ứng dụng khác định dạng dữ liệu: máy cũ báo cần cập nhật | Chưa thử |
| 15 | Dữ liệu trận bị sửa tay (dùng bản build gỡ lỗi): máy kia từ chối và báo lỗi | Chưa thử |
