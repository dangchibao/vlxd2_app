# Cập nhật source 0.4 — 05/11/2026

Đây là mốc kiểm chứng cho V1.0. Các mục sau đường phân cách là nhật ký lịch sử.

Đã nối Auth/session, cache riêng theo UID, sync outbox/receipt/event/checkpoint và trạm Windows vào UI. Có danh mục đa ngành, bảng giá/giá số lượng/quy đổi, đối tác, báo giá có phiên bản, bán/thu nợ, mua/nhận nhiều đợt và phí mua NCC, kho/giữ hàng/duyệt vượt tồn, kiểm kê, lô/serial, trả hàng/cách ly/hoàn tiền, bảo hành cơ bản, xe/lịch giao/bản đồ, thu chi/chốt ca, báo cáo, Excel, backup mã hóa/restore và tìm kiếm.

Đã thêm in từ chứng từ xác nhận, các phiếu thu/chi/nhập/trả/kiểm kê riêng, nhật ký PDF và yêu cầu in điện thoại qua claim tại trạm. Có cấu trúc chuẩn bị hóa đơn điện tử; không tự phát hành hoặc chọn thuế suất. Worker PWA chỉ cache tài nguyên app, không cache API.

Source 0.4 thêm giao diện bảng và tìm kiếm phân trang, biểu đồ doanh thu, tồn khả dụng khi lập đơn, cọc và hoàn cọc, phục hồi lệnh bị từ chối thành nháp, cùng kiểm soát phiên đăng nhập và xử lý lệnh sai kiểu dữ liệu. Giá vốn bình quân theo mã hàng và kho, có đối chiếu giá trị qua chuyển trạng thái chất lượng.

Analyze sạch, 79 kiểm thử unit/widget đạt. Bộ chạy riêng trên emulator đạt 10 ca Rules và 1 kịch bản tích hợp Auth/Firestore REST. Kiểm thử worker ngoại tuyến đạt. Đã mở bản Windows QA với dữ liệu mô phỏng và kiểm tra cập nhật số lượng, tổng đơn và báo cáo. Dữ liệu QA chỉ nằm trong môi trường mô phỏng.

Firebase `vlxd-bayhai-v1-261105` dùng Firestore Native miễn phí ở `asia-southeast1`. Email/Password đã bật, Rules đã triển khai và Auth đã xác nhận đăng nhập tài khoản `admin`. Quyền ghi sổ cần xác minh người dùng đã đổi mật khẩu khởi tạo. Chưa publish Hosting production. Xem [hướng dẫn vận hành](RUNNING_AND_SETUP.md).

Windows 0.4 đã đóng gói tại `dist/VLXD-Bay-Hai-Windows-0.4.zip` và mở được màn hình đăng nhập. Tài khoản trạm `tram` đã xác thực và phiên được đọc lại thành công từ kho bảo mật trên máy Windows hiện tại. Trạm xử lý khi app Windows đang chạy, có mạng và có phiên nhân viên hợp lệ.

Còn cần hoàn thiện combo/lắp bộ, lịch sử giá và một số báo cáo chi tiết, quy trình xử lý hàng hỏng và đổi bảo hành nâng cao, hiển thị ảnh hàng hóa và quét barcode bằng camera. Chưa đo hiệu năng trên dữ liệu lớn hoặc thử thiết bị thật Android, iPhone và KV804.

---

# Trạng thái triển khai — 05/11/2026

## Cập nhật tiếp tục triển khai (source 0.2.0)

Phần bên dưới mục này là nhật ký bản nền tảng trước; trạng thái mới được ghi ở
đây. Chưa đánh dấu V1.0 hoàn thành.

Kết quả source 0.2: analyze sạch; 36 ca unit/widget đạt; 7 ca Rules và 1 kịch bản
tích hợp REST trên emulator đạt. Test emulator được skip trong test thường,
chạy riêng qua script trong security/README.md. Windows release đã build và mở
được cửa sổ tổng quan; gói mới là `dist/VLXD-Bay-Hai-Windows-0.2-dev.zip`.
Chưa kiểm chứng thao tác in thật.
Web và APK 0.2 đã build lại thành công. APK thử nghiệm ký bằng debug key,
được sao chép tới `dist/VLXD-Bay-Hai-Android-0.2-dev.apk`. Chưa cài/chạy trên
Android hoặc iPhone thật. Gói Windows 0.2 chứa đủ DLL của máy in và SQLite.

Đã thêm schema 4 và migration giữ lại catalog/đơn nháp/outbox bản 1. Có bảng
business records, command receipts, business events, checkpoint/inbox và print jobs.

Lõi nghiệp vụ có transaction, kiểm quyền, expectedVersion, idempotency và event:
đặt mua/nhận từng đợt, tồn tốt/cách ly, bình quân liên hoàn, bán không âm tồn,
thu nhiều lần, giao nhiều chuyến, chuyển kho, trả hàng/hoàn tiền, trả NCC,
thu chi/chốt ca và state machine bảo hành cơ bản. Số lượng lõi dùng scale 1000;
UI nháp cũ vẫn dùng số nguyên. Đây là **lõi có test**, chưa phải toàn bộ phân hệ
UI đã hoạt động cho người sử dụng.

Cùng bộ xử lý có adapter SQLite và Firestore REST. Adapter cloud stage writes
rồi commit chứng từ, tồn/nợ, receipt và event trong cùng transaction; không lấy
SQLite làm bằng chứng cloud đã xác nhận. Actor của command được trạm kiểm tra
lại từ membership bên trong transaction. Rejection có receipt riêng; không
chuyển lỗi thành xác nhận thành công.

Sync engine có enqueue transactional, kiểm command trùng, receipt trước retry,
backoff/jitter, conflict/error, giới hạn batch và apply event/checkpoint nguyên tử.
Chưa nối uploader, polling và tải catalog vào giao diện đang chạy. Legacy outbox
không có actor được giữ nguyên, không tự gửi dưới danh nghĩa người đăng nhập sau.

Auth REST có sign-in/refresh/change-password, từ chối emulator từ xa, thông báo
lỗi không lộ token; SessionVault dùng secure-storage. Chưa nối màn hình đăng nhập,
bootstrap admin, xác minh đổi mật khẩu đầu tiên và quản lý nhân viên vào app.

Firestore Rules và 7 ca emulator đã đạt. Kiểm thử tích hợp Auth + Firestore REST
đã đạt trên emulator: đổi mật khẩu, token refresh, stale precondition, command
replay và hai bộ xử lý cloud cùng tranh tồn cuối (một xác nhận, một lỗi).
Không tạo Firebase thật và không deploy Rules lên cloud.

UI có thêm công cụ tính gạch tức thì và xem phiếu tạm K80. Font Noto Sans được
nhúng (OFL kèm source), có nhật ký gửi in và chặn gửi lại cùng job ID. Khi kết quả
không rõ, cần đối chiếu giấy thực tế. Chưa thử KV804 thật, chưa có mobile print
request tới trạm và chưa đủ mọi loại mẫu phiếu.

Kiểm thử mobile phát hiện tràn thanh điều hướng ở 390px, đã sửa bằng drawer.
Chưa dùng kết quả widget test để tuyên bố đã kiểm thử iPhone thật.

Đầu việc còn lại lớn nhất: nối Auth/session với UI và đồng bộ/trạm chạy nền;
hoàn thiện các màn hình nghiệp vụ; danh mục đối tác/bảng giá/quy đổi/thuộc tính;
lô/serial, giữ hàng/duyệt vượt tồn; báo giá; bản đồ/xe/tài xế; báo cáo/Excel;
backup/restore; tìm kiếm toàn hệ thống; hóa đơn DTO; QA thiết bị và hiệu năng.
Các adapter mới không được coi là chứng nhận bảo mật production.

## Nhật ký bản nền tảng ban đầu

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
