# Backlog, kiểm thử và cổng nghiệm thu

Trạng thái 05/11/2026: toàn bộ backlog dưới đây CHƯA LÀM. Không có tính năng hoàn thành chỉ nhờ bản kế hoạch. Thực hiện sau khi người dùng phê duyệt.

## 1. Kế hoạch 5 giai đoạn

| Giai đoạn | Backlog và đầu ra | Điều kiện qua cổng |
|---|---|---|
| 1 — Nền tảng | Khởi tạo Flutter 3 đích; cấu trúc feature; shell theo ảnh; state reactive; Drift schema/migration; Auth/role/action; outbox/receipt/checkpoint/conflict/audit; emulator Rules; thử Windows REST; prototype trạm xác nhận; service worker/WASM; số tiền chính xác | Analyze/test xanh; lưu/khôi phục local sau kill; hai client tranh tồn chỉ một được xuất; người bán không ghi confirmed; quyền offline không tự nâng; Windows Auth/transaction/catch-up đạt; Safari persistence được đánh giá. Chưa qua cổng này không mở rộng nghiệp vụ trên kiến trúc chưa chứng minh |
| 2 — Giao dịch cốt lõi | Hàng hóa đa ngành/thuộc tính/biến thể/combo/đơn vị/giá bậc thang/lịch sử; đối tác; báo giá phiên bản; đơn nháp autosave; đặt cọc/thu nhiều lần/phân bổ/công nợ; snapshot; tính vật liệu | Chọn hàng/tính tiền tức thì, thu không trùng, số dư đúng, đơn khóa sau ghi sổ; cảnh báo thiếu tồn, command sai quyền bị từ chối. UI→logic→local→sync→security→test cho từng tính năng |
| 3 — Vận hành | Nhập/xuất/chuyển/kiểm/reservation; duyệt vượt tồn; mua và nhận nhiều đợt; lô/màu/serial; cách ly; giao nhiều chuyến/xe/tài xế/tải trọng/map; in K80 và hàng đợi | Đặt100/nhận60; không tồn âm; serial không xuất trùng; không bán hàng lỗi; giao/khấu trừ không trùng; in Windows offline và test máy thật trước đánh dấu printer đạt |
| 4 — Hoàn chỉnh nghiệp vụ | Trả/hoàn/đảo chứng từ; bảo hành; chốt ca/đối soát; bình quân gia quyền; chi phí/lợi nhuận; dashboard/báo cáo provisional vs confirmed; cảnh báo dedup | Giá vốn theo kho đúng, nhập muộn có audit, tiền thực thu đúng ca, trả/bảo hành không tự tăng tồn tốt; báo cáo đối chiếu journal |
| 5 — Bàn giao | Excel template/preview/validate/confirm; backup/restore; search tên/SKU/barcode/serial/đơn/phone; quản trị health/log/quota; EInvoice DTO; tối ưu; build/guide/package | 20 luồng bắt buộc có bằng chứng; restore diễn tập; đa nền tảng build; phân quyền và crash recovery đạt; ghi rõ test thiết bị còn thiếu; người dùng nghiệm thu trước production |

Giai đoạn 1 có thể tạo fixture/test scaffold cho giao dịch tối thiểu để chứng minh an toàn; fixture không được tính là nghiệp vụ production hoàn thành. Các dependency trước sau: kho/giá vốn cơ bản phải hỗ trợ chứng từ bán từ giai đoạn 2; giai đoạn 3/4 mở rộng toàn bộ luồng, không chờ đến cuối mới xét tính đúng.

Không ấn định ngày bàn giao khi chưa có kết quả prototype Windows/Spark, số lượng SKU/dòng đơn thực tế và thiết bị thử. Ước lượng sau giai đoạn 1 theo tốc độ hoàn thành tiêu chí thay vì số màn hình.

## 2. Ma trận kiểm thử bắt buộc

Mỗi kết quả lưu commandId, build/version, dữ liệu đầu/cuối và log đã loại secrets. Mỗi test hiện **chưa chạy** vì chưa có app.

| # | Luồng | Bằng chứng phải có |
|---|---|---|
| 1 | Reactive | Widget: chọn sản phẩm/khách/đơn vị, gõ SL/chiết khấu/tiền; không blur vẫn đúng; đo input→frame bằng profile trên thiết bị hỗ trợ, mục tiêu khoảng 100 ms |
| 2 | Offline→online | Tắt mạng, lưu đơn, restart, còn dòng/snapshot/outbox; online nhận đúng một receipt và checkpoint |
| 3 | Hai thiết bị | Cùng bán tồn cuối: chỉ transaction hợp lệ ghi sổ; còn lại conflict/chờ duyệt, không âm |
| 4 | Vượt tồn | Người bán không duyệt được kể cả gọi API; quản lý chọn chờ nhập/giao phần/từ chối; không tự xuất âm |
| 5 | Trả nhiều lần | Đặt cọc + hai lần thu; allocation không vượt nợ; timeout/retry không nhân đôi |
| 6 | Giao nhiều chuyến | Tổng giao đúng đơn; không ghi xuất hai lần; hủy/hoàn chuyến có chứng từ |
| 7 | Giá vốn | Nhập100×10.000 rồi100×14.000 → bình quân12.000; xuất50 → giá vốn600.000, còn150/1.800.000; thêm chuyển kho/trả/chi phí/nhập muộn |
| 8 | Mua từng đợt | Đặt100 chưa tăng tồn; nhận60 tốt còn40; giao dư/lỗi không tự nhập bán được |
| 9 | Lô/serial | Hai command xuất cùng serial chỉ một thành công; truy vết return; cảnh báo trộn màu/lô |
| 10 | Cách ly | Tồn tốt10 + lỗi5 chỉ bán tối đa10; đổi chất lượng cần quyền |
| 11 | Bảo hành | Nhận serial đúng đơn, lưu phụ kiện, tiến trình/chi phí/đổi; không tăng tồn tốt ngầm |
| 12 | Chốt ca | Đầu1.000.000 + thu500.000 - chi100.000 - hoàn50.000 =1.350.000; đếm1.300.000 → lệch−50.000 tức thì; chuyển khoản riêng |
| 13 | Thu nợ cũ | Nợ hôm trước thu hôm nay: ca hôm nay tăng tiền, doanh thu hôm nay không tăng lần nữa |
| 14 | Vật liệu | Gạch60×60cm,4viên/thùng →1,44m²; diện tích10m² hao5% →8thùng; kiểm làm tròn, zero/âm, chỉnh SL thủ công; thêm ống/m³ |
| 15 | Excel lỗi | SKU trùng, đơn vị sai, dòng thiếu, file hỏng/quá lớn/công thức nguy hiểm: preview chỉ lỗi, không ghi một phần ngoài policy đã duyệt |
| 16 | Backup/restore | Snapshot hợp lệ phục hồi; hash sai bị chặn; DB cloud mới hơn không bị ghi đè; outbox đã xác nhận không lặp |
| 17 | Mất điện/kill | Kill trước/sau commit local, sau upload, sau receipt, giữa apply; mở lại invariant và checkpoint đúng |
| 18 | Chống trùng | Replay command/payment/refund/stock event nhiều lần; một hiệu ứng; cùng ID khác hash bị từ chối |
| 19 | KV804 | Phiếu bán/thu/chi/kho/giao/trả; tiếng Việt, tên dài, 80mm, offline, hết giấy, mất USB/nguồn và unknown-result; kiểm bằng giấy thật |
| 20 | Build | `flutter analyze`, `flutter test`, integration/emulator; release Windows/APK/Web; chạy smoke Windows/Android thật/iPhone Safari Home Screen |

Test bổ sung: Rules deny cross-store, tự sửa role, user bị disable, approval cũ, snapshot giả, journal trực tiếp; money boundary Web; SQLite FK/migration/rollback; Safari tab đồng thời, eviction và service worker update; token expiry; trạm lease chuyển quyền; đồng bộ backlog lớn, quota và log không lộ mật khẩu/token.

## 3. CI và tiêu chuẩn hoàn thành

- PR: format/analyze, unit/widget, Rules emulator, integration database/migration; Windows runner build Windows, runner phù hợp build APK và Web. Khóa version Flutter/Node/Java/dependency; không dùng project cloud thật trong CI.
- Không đẩy secrets, không tự deploy production. Git commit theo phần sau khi kiểm diff và test; không sửa hoặc xóa ảnh nguồn. Hướng dẫn rollback code và migration forward/recovery trước phát hành.
- Mỗi feature cần màn hình theo ảnh, logic thật, persistence/restart, sync/receipt, authorization server-side phù hợp trạm và Rules, test happy/negative/concurrent; ghi status riêng nếu chưa có thiết bị.
- Báo cáo performance trên dataset được thống nhất (đề xuất thử 10.000 SKU, 12 tháng ×50 đơn/ngày trước tối ưu); không coi benchmark máy dev là cam kết cho mọi điện thoại.
- Đo reads/writes theo command thực tế, số dòng và reconnect. Mục tiêu vận hành cảnh báo sớm theo tỷ lệ quota cấu hình; bộ đếm app chỉ là ước tính, Firebase console là nơi đối chiếu. Không hứa quota còn lại chính xác nếu không có nguồn đo tin cậy.

## 4. Rủi ro và quyết định cần duyệt

| Mức | Rủi ro | Cách xử lý/cổng quyết định |
|---|---|---|
| Chặn | Chưa có backend xác nhận trên Spark | Duyệt trạm Windows được tin cậy và chấp nhận thời gian chờ khi trạm offline; hoặc chọn kiến trúc khác trước code |
| Chặn | FlutterFire Windows không dành production | Thử REST adapter bằng emulator/local, đánh giá token và transaction; thất bại thì báo lại, không lặng lẽ đổi nền tảng |
| Cao | Cloud Storage không dùng Spark | Duyệt ảnh local+backup, giới hạn truy cập từ xa; chưa hoàn thành yêu cầu ảnh sync toàn thiết bị cho đến khi có giải pháp |
| Cao | Safari mất dữ liệu/background | Lưu bền khi khả dụng, hiển thị outbox, hướng dẫn Home Screen, backup/sync; thử iPhone thật |
| Cao | Thao tác kho/tiền offline | Tạm tính, không đảm bảo tồn liên thiết bị trước xác nhận; cần quy trình không giao vượt phần đã xác nhận |
| Cao | Máy in không rõ model/driver | Xác minh KV804 và test 80mm; unknown outcome xử lý thủ công có audit |
| Cao | Giá vốn nhập muộn/điều chỉnh | Khóa chứng từ, cost journal, lệnh quản lý và đối chiếu; không hồi tố âm thầm |
| Vừa | Quota/listener/ảnh/dữ liệu tăng | Checkpoint, phân trang, retention có duyệt, đo trước chạy thật; không tự Blaze |
| Vừa | Excel package và scanner khác nền tảng | Prototype trước chọn, USB scanner trên Windows; test Safari camera |
| Vừa | Chưa audit Firebase cũ | Chờ project ID/cấu hình đúng dự án, chỉ đọc; không cần truy cập để bắt đầu emulator |

## 5. Hồ sơ bàn giao dự kiến

Source và lịch sử Git; Windows release/APK/Web khi build được; test report và danh sách feature theo trạng thái thực; hướng dẫn Firebase mới/Rules/quota/Auth bootstrap; cài iPhone PWA; thiết lập trạm xác nhận và KV804; sử dụng từng nghiệp vụ; backup/restore có diễn tập; rollback code; danh sách giới hạn và việc chưa kiểm thử thiết bị thật. Bản build không đồng nghĩa được phép triển khai production.

Đề nghị phê duyệt: kế hoạch này, kiến trúc trạm Windows được tin cậy, thử adapter REST Windows, và giới hạn ảnh local ở bước đầu; cho phép bắt đầu giai đoạn 1 bằng local/emulator. Quyền tạo project Firebase mới và deploy sẽ xin riêng trên cấu hình cụ thể sau; hiện chưa thực hiện.
