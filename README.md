# vlxd2_app
Cửa hàng VLXD Bảy Hải — Flutter Windows / Android / Web.

## Trạng thái

Bản phát triển local, chưa phải V1.0 hoàn chỉnh. Hiện có danh mục hàng hóa,
tìm kiếm, tạo/khôi phục đơn nháp, tính tiền tức thì, lưu SQLite và transactional
outbox. Không có dữ liệu mẫu tự động. Đơn gửi chỉ chờ xác nhận; chưa ghi sổ,
chưa trừ kho hoặc đồng bộ cloud. Chưa có đăng nhập/phân quyền: chỉ dùng thử
trên máy riêng, không dùng cho dữ liệu kinh doanh thật.

## Chạy và kiểm tra

```powershell
flutter pub get
dart run build_runner build
flutter analyze
flutter test
flutter run -d windows
```

Database native nằm trong thư mục Documents theo `drift_flutter`, tên
`bayhai_v1.sqlite`; Web dùng SQLite WASM với lưu trữ của browser.
Mỗi nền tảng có database độc lập, hiện chưa chia sẻ dữ liệu giữa thiết bị.
Đợi thông báo “Đã lưu trên thiết bị” trước khi đóng ứng dụng.

Thêm SKU/tên/đơn vị/giá ở Hàng hóa → mở Bán hàng → tìm/chọn sản phẩm →
nhập số lượng nguyên, chiết khấu, tiền thanh toán tạm → lưu nháp hoặc gửi chờ.
Mục Đơn đã lưu mở lại các bản nháp; đơn đã gửi không sửa trực tiếp.
Số lượng thập phân/quy đổi đơn vị chưa triển khai ở bản này.

```powershell
flutter build windows --release
flutter build apk --release
flutter build web --release
```

Phân phối Windows cần cả thư mục `build/windows/x64/runner/Release`, không chỉ
file exe. Web cần phục vụ `sqlite3.wasm` với MIME `application/wasm` qua HTTPS
hoặc localhost. Web build chưa đồng nghĩa PWA offline đã được kiểm thử Safari.

Các file `web/drift_worker.dart.js` và `web/sqlite3.wasm` lấy từ release
`drift-2.35.3` của https://github.com/simolus3/drift/releases/tag/drift-2.35.3;
không đổi một file riêng khi nâng dependency. Drift MIT, SQLite public domain;
các notices của dependency phải được giữ trong màn hình License Flutter.

Audit, kiến trúc và backlog chi tiết nằm trong `docs/`. Chưa tạo Firebase,
chưa deploy production và chưa kích hoạt dịch vụ trả phí.
