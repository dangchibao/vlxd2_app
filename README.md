# VLXD Bảy Hải

Phần mềm quản lý cửa hàng vật liệu xây dựng cho Windows 11, Android và
iPhone qua PWA. Bản 1.0.0 có bán và mua hàng, kho theo lô hoặc serial, lắp
bộ, công nợ, giao hàng, bảo hành, chốt ca, báo cáo, Excel và in K80.

- [Bản bàn giao V1 và các bước nghiệm thu](docs/RELEASE_V1.md)
- [Cài đặt, kết nối trạm Windows, vận hành và sao lưu](docs/RUNNING_AND_SETUP.md)
- [Kiểm thử Firebase Emulator](security/README.md)

Phiếu lưu khi mất mạng nằm trong hàng đợi trên thiết bị. Trạm Windows
xác nhận khi đồng bộ được. Dữ liệu đã xác nhận và trạng thái chờ được
hiển thị riêng trong ứng dụng.

Để chạy mã nguồn trên Windows với cấu hình của dự án:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define-from-file=config/firebase.public.json
```

Khi đóng gói Windows, giữ cả thư mục release cùng DLL và dữ liệu đi kèm.
Gói PWA cần được phục vụ qua HTTPS và máy chủ phải trả
`sqlite3.wasm` với MIME `application/wasm`.

Các file `web/drift_worker.dart.js` và `web/sqlite3.wasm` đi cùng phiên
bản [Drift 2.35.3](https://github.com/simolus3/drift/releases/tag/drift-2.35.3).
