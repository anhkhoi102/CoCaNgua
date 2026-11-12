# Luật chơi Cờ Cá Ngựa

Tài liệu này mô tả chính xác những gì `GameCore` thực thi. Mọi luật nằm ở một chỗ:
`RulesConfiguration` (cấu hình) và `MoveValidator` / `TurnManager` / `GameEngine` (thực thi).
Đấu máy và chơi mạng dùng chung đúng bộ mã này.

Không có bộ luật Cờ Cá Ngựa "chính thức". Nguồn tham khảo chính là
[Wikipedia tiếng Việt](https://vi.wikipedia.org/wiki/Cờ_cá_ngựa), đối chiếu với luật gốc
[Jeu des petits chevaux](https://fr.wikipedia.org/wiki/Jeu_des_petits_chevaux) và một số bài hướng dẫn
tiếng Việt. Chỗ nào các nguồn không thống nhất đều được ghi rõ bên dưới và tách thành tuỳ chọn.

## Bàn cờ

- Vòng quanh bàn có 56 ô, mỗi màu 14 ô. Trên màn hình quân đi **ngược chiều kim đồng hồ**.
- Trong đó bốn **ô xuất phát** (ô chờ, mỗi màu một ô: 0, 14, 28, 42) nằm ngoài đường chạy: chỉ quân vừa ra của đúng màu đó được đứng.
  Quân màu khác đi vòng tới thì nhảy qua, không tính bước, không dừng được ở đó. Quân đang chờ ở ô xuất phát không bị đá và không cản đường ai.
  Vì vậy một vòng của mỗi quân dài 52 bước: từ ô xuất phát (bước 0) tới ô cửa chuồng của mình (bước 52).
- Thứ tự lượt: Đỏ, Xanh dương, Xanh lá, Vàng, cũng ngược chiều kim đồng hồ quanh bàn. Bàn được xoay để chuồng của người chơi nằm ở góc dưới trái; các màu còn lại giữ nguyên thứ tự quanh bàn. Ô xuất phát lần lượt là 0, 14, 28, 42.
- Bốn ô cửa chuồng (13, 27, 41, 55) cách nhau 13 bước; chúng cũng là điểm đáp của nước bay.
- Ô "cửa chuồng" của mỗi màu là ô cuối vòng, ngay trước ô xuất phát của màu đó (52 bước từ ô xuất phát).
- Mỗi màu có cột về đích 6 bậc, đánh số 1–6. Chỉ quân màu đó được vào.
- Mỗi người 4 quân. Ván có 2, 3 hoặc 4 người; 2 người mặc định ngồi đối diện (Đỏ – Xanh lá).

> **Chưa kiểm chứng:** không nguồn nào ghi rõ số ô. Con số 56 là theo bàn Petits Chevaux phổ biến.
> Số ô được khai báo một chỗ trong `Board`; cần đối chiếu với hình bàn cờ thật khi vẽ bàn ở Phase 2.
>
> **Chiều đi:** chiều là chuyện hiển thị (`BoardLayout`), không ảnh hưởng luật trong `GameCore`. Ban đầu trò chơi vẽ theo
> chiều kim đồng hồ; từ 12/11/2026 đổi sang ngược chiều kim đồng hồ theo yêu cầu, trùng với mô tả trên Wikipedia tiếng Việt.

## Luật mặc định (`RulesConfiguration.traditional`)

| Luật | Giá trị mặc định |
|---|---|
| Xúc xắc | Một viên (chế độ nhanh: hai viên, xem bên dưới) |
| Bay | Viên ra 1 cho phép bay tới cửa chuồng kế tiếp thay vì đi 1 bước (xem bên dưới) |
| Ra quân | Đổ được 6; quân xuống ô xuất phát của mình |
| Đổ thêm | Đổ được 6 thì đổ thêm, không giới hạn số lần |
| Đá quân | Đi đúng số bước tới ô có quân đối phương thì đá quân đó về chuồng |
| Ô xuất phát | Ô riêng của từng màu, nằm ngoài đường chạy; còn quân mình đứng đó thì chưa ra thêm quân được |
| Cản đường | Luật cố định, không tắt được: không nước nào (đi thường, cộng hai viên, bay) được vượt qua một quân khác, kể cả quân mình. Chỉ có thể dừng trước nó, hoặc đá nó khi đổ đúng số bước |
| Chồng quân | Không; hai quân không đứng chung một ô |
| Ô an toàn | Không có. Chỉ chuồng và cột về đích là an toàn; ô cửa chuồng vẫn bị đá |
| Tới cửa chuồng | Phải dừng đúng ô cửa chuồng, không được đi quá |
| Lên đích | Từ cửa chuồng, đổ số nào lên bậc đó; các bậc thấp hơn phải trống |
| Leo trong cột | Từ bậc k lên bậc k+1 phải đổ đúng k+1 |
| Thắng | Bốn quân chiếm các bậc 6, 5, 4, 3 |
| Không có nước đi | Mất lượt. Nếu vừa đổ 6 thì vẫn được đổ thêm |
| Bắt buộc đi | Có nước hợp lệ thì phải đi một nước |
| Kết thúc ván | Ngay khi có người thắng; những người còn lại xếp hạng theo tiến độ |

## Nước bay

Áp dụng ở cả chế độ thường lẫn chế độ nhanh (`flyOnOne`, luôn bật; không có công tắc trong Cài đặt).

- Khi một viên ra 1, người chơi được chọn: đi 1 bước như thường, hoặc cho một quân **trên đường chạy** bay tới
  ô cửa chuồng gần nhất phía trước nó (của bất kỳ màu nào). Nước bay dùng hết viên 1 đó.
- Bay cũng bị cản đường: mọi ô giữa quân và ô cửa chuồng phải trống. Ô đáp theo luật thường: có quân đối phương thì đá quân đó, có quân mình thì không bay được
  (trừ khi bật chồng quân), ô an toàn thì đứng chung.
- Tính theo đường của chính quân đó, các ô cửa chuồng nằm ở bước 13, 26, 39 và 52; ô cuối cùng là cửa chuồng của mình
  nên quân không bao giờ bay quá. Quân đang ở cửa chuồng của mình, trong chuồng hoặc trong cột đích thì không bay.

## Chế độ nhanh (`diceCount = 2`)

Bật ở màn thiết lập chơi đơn hoặc trong Cài đặt → Luật chơi.

- Mỗi lần đổ hai viên. Người chơi tự chọn một trong hai cách, và có thể kết hợp bay:
  - **Dùng riêng từng viên**: mỗi viên cho một nước, theo thứ tự tuỳ ý, cho cùng một quân hoặc hai quân khác nhau.
  - **Cộng hai viên** cho một quân: quân đi một mạch đúng tổng số bước (vẫn bị cản đường trên cả quãng).
- Ra quân cần **một viên** ra giá trị ra quân (mặc định 6). Tổng hai viên bằng 6 không ra quân được.
- Sau khi dùng một viên, nếu viên còn lại không có nước hợp lệ thì viên đó bị bỏ.
- **Đổ thêm chỉ khi ra đôi** (hai viên giống nhau), kể cả khi không có nước đi. Viên 6 đơn lẻ không được đổ thêm.
  Giới hạn số lần đổ thưởng liên tiếp (nếu bật) tính theo số lần ra đôi.
- Lên và leo cột đích chỉ tính **từng viên**, không tính tổng: phải có một viên ra đúng số của bậc cần lên.
  Ví dụ đang ở bậc 3 muốn lên 6 thì phải lên 4, rồi 5, rồi 6, mỗi bậc cần một viên ra đúng 4, 5, 6; đổ 1 và 3 không lên được bậc 4.
  Ở cửa chuồng với 2 và 3: lên bậc 2 hoặc bậc 3, không lên bậc 5. (Riêng luật kiểu Ludo `pipCount` đi theo số chấm nên vẫn cộng được.)
- Thắng bằng viên thứ nhất thì ván kết thúc ngay, viên còn lại bị bỏ.

## Tự động đi

Khi chỉ có một lựa chọn thật sự thì quân tự đi (tắt được trong Cài đặt). Các quân còn trong chuồng là như nhau, nên nếu mọi
nước hợp lệ đều là ra quân thì trò chơi tự lấy ngẫu nhiên một quân. Nếu chỉ một quân đi được nhưng có nhiều cách đi,
trò chơi chỉ dừng lại hỏi khi một trong các cách đó là bay, đá quân hoặc lên bậc đích (các ô đích của quân được mở sẵn để chọn);
nếu không, quân tự đi quãng dài nhất xúc xắc cho phép (chế độ nhanh: cộng hai viên). Khi có từ hai quân đi được
(kể cả ra quân mới hay đi quân đang chạy lúc đổ ra 6) thì người chơi vẫn chọn.

## Biến thể cấu hình được

| Trường trong `RulesConfiguration` | Lựa chọn | Ghi chú |
|---|---|---|
| `releaseValues` | `[6]` (mặc định), `[1, 6]` | "Nhất – lục": nhiều nguồn tiếng Việt coi 1 hoặc 6 là luật truyền thống |
| `bonusTurnValues` | `[6]` (mặc định), `[1, 6]`, `[]` | |
| `maxConsecutiveBonusRolls` | `nil` (mặc định), `3` | Lần đổ thưởng thứ ba liên tiếp bị huỷ và mất lượt |
| `blocking` | `true` | Luôn bật, không có công tắc trong Cài đặt; trường tồn tại để test tắt được |
| `allowStacking` | `false` (mặc định), `true` | Bật thì ô có từ hai quân cùng màu không bị đá |
| `safeSquares` | `none` (mặc định), `startAndMidSquares` | Ô giữa mỗi cạnh; trên ô an toàn nhiều màu đứng chung, không ai bị đá. (`startSquares` cũ không còn tác dụng vì ô xuất phát đã là ô riêng) |
| `homeEntry` | `exactRungDirect` (mặc định), `exactRungStepwise`, `pipCount` | Xem dưới |
| `diceCount` | `1` (mặc định), `2` | Chế độ nhanh |
| `flyOnOne` | `true` | Luôn bật theo yêu cầu; trường tồn tại để engine và test tắt được |

`homeEntry`:

- `exactRungDirect`: như bảng mặc định.
- `exactRungStepwise`: từ cửa chuồng phải đổ 1 để lên bậc 1, rồi 2, 3, … (luật Petits Chevaux).
- `pipCount`: kiểu Ludo. Quân đi theo số chấm, vào thẳng cột đích, không cần dừng ở cửa chuồng,
  không được đi quá bậc 6.

Có sẵn một bộ thứ hai, `RulesConfiguration.modern` (kiểu Ludo): ô an toàn, chồng quân,
ba lần 6 mất lượt, lên đích theo số chấm.

## Khác biệt so với yêu cầu ban đầu

Bản yêu cầu liệt kê "ô an toàn" và "nhiều quân chung một ô" như luật cơ bản. Luật Việt truyền thống
không có hai điều này, nên chúng tắt trong bộ mặc định và bật được trong phần Cài đặt (hoặc dùng bộ `modern`).
Không có chỗ nào trộn ngầm hai bộ luật.

## Biến thể chưa hỗ trợ

- Kiểu hai xúc xắc truyền thống: ra quân bằng cặp 1‑6 hoặc bằng đôi. (Chế độ nhanh ở trên là một biến thể khác.)
- Leo cột bằng cách đổ số của bậc cao hơn bất kỳ.
- Phạt lùi quân khi đổ ba lần 6; đá chéo; không đá lùi.
- Chơi tiếp sau khi có người thắng để phân hạng nhì, ba.
- Quy ước cá cược ("thầu mạ", "sập hầm").
