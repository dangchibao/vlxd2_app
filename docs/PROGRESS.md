# Trạng thái triển khai — 05/11/2026

Người dùng đã cho phép chủ động triển khai hướng miễn phí sau audit. Không cần
xin duyệt lại từng thay đổi thông thường. Không tạo hoặc sửa Firebase thật,
không deploy, không bật billing trong phiên triển khai này.

## Đã triển khai và kiểm thử

- Flutter project Windows/Android/Web; Riverpod, go_router và Drift SQLite.
- Giao diện nền xanh dương, sidebar desktop và navigation mobile theo hướng ảnh.
- Thêm hàng hóa thật không tự sinh mẫu; SKU chuẩn hóa, unique và giá không âm.
- Tìm hàng theo tên/SKU; chọn vào đơn, số lượng nguyên, chiết khấu và thanh toán
  tạm tính; tổng/tiền còn nợ cập nhật khi gõ. Số lượng không hợp lệ chặn gửi.
- Tự lưu nháp sau 500 ms khi thông tin hợp lệ; mở lại từ danh sách đơn đã lưu.
- Transaction SQLite ghi đơn, outbox và audit cùng lúc; đơn gửi bị khóa sửa.
  Hàng đợi hiện tại chỉ lưu local, chưa có uploader/receipt cloud.
- Dashboard chỉ đếm dữ liệu thật có trên thiết bị; chưa hiển thị doanh thu giả.
- SQLite WASM/worker của release Drift tương thích được đặt trong web/.
- CI chạy thủ công, không deploy. Chưa thực thi workflow trên GitHub.

Kiểm tra: `flutter analyze` sạch; `flutter test` 6/6 đạt. Bộ test gồm tính tiền
nguyên/overpayment, SKU unique + rollback audit, đồng thời gửi đơn chỉ một
outbox, mở lại database còn dữ liệu, render catalog, reactive quantity không
chờ blur và không hiển thị tổng hợp lệ khi quantity rỗng.

Windows release, Web release và APK Android release đã build thành công.
Build không thay thế smoke test trên thiết bị thật. Windows đã được đóng gói
trong `dist/VLXD-Bay-Hai-Windows-dev.zip` (giải nén toàn bộ rồi chạy exe).
APK ở `build/app/outputs/flutter-apk/app-release.apk`.
APK hiện dùng debug signing key của scaffold để thử nghiệm; chưa phải bản
ký phát hành chính thức. Web đã rebuild từ source hiện tại; chưa deploy.

## Phần còn thiếu — chưa được coi là hoàn thành

Giai đoạn 1 vẫn chưa hoàn tất: Auth/đổi mật khẩu, phân quyền có thẩm quyền,
Rules/emulator, REST Windows, trạm xác nhận, retry/hash/checkpoint/conflict,
schema đầy đủ và migration nâng phiên bản chưa triển khai. Không có bảo đảm
an toàn kho/tiền nhiều thiết bị ở bản hiện tại.

Giai đoạn 2 mới có lát cắt nhỏ catalog/đơn nháp. Chưa có quy đổi/SL thập phân,
autosave dữ liệu đang nhập sai, bảng giá khách hàng, báo giá, sổ công nợ,
thanh toán thật. Product create chưa có outbox sync. Không dùng bản này để
ghi sổ cửa hàng hoặc lưu thông tin nhạy cảm.

Các mục giai đoạn 3–5 (kho, mua, lô/serial, cách ly, giao, map, printer, trả,
bảo hành, ca, giá vốn, lợi nhuận, report, Excel, backup/restore, search toàn hệ
thống, hóa đơn DTO và bàn giao chính thức) vẫn chưa triển khai.

Chưa chạy app trên Android/iPhone thật, chưa đo 100 ms trên thiết bị hỗ trợ,
chưa kiểm thử in KV804, chưa kiểm chứng offline PWA/service worker/Safari.
Font/icon vẫn là asset nền Flutter, chưa phải giao diện nghiệm thu sát ảnh.

## Tiếp theo

Hoàn thành cổng an toàn giai đoạn 1 trước khi thêm thao tác ghi sổ: schema có
version + idempotency, domain command validator, role/action guard, local
emulator Rules tests, prototype trạm xác nhận và Windows REST. Khi thiếu project
ID Firebase cũ thì để phần audit cũ pending, không truy cập project khác.
