# Kiểm thử bảo mật cục bộ

Chỉ chạy trên project giả `demo-vlxd-bayhai` bằng Auth/Firestore Emulator. Không
cần tạo Firebase thật, không cần billing hoặc service-account trong repository.

```powershell
npm --prefix security ci
firebase emulators:exec --project demo-vlxd-bayhai --only auth,firestore "node security/run-emulator-tests.mjs"
```

Cần Java 21+, Firebase CLI 15.34.2, Node 22+ và Flutter trên PATH. Nếu Android
đang dùng Java 17, đặt JAVA_HOME chỉ cho process chạy emulator; không cần đổi
cấu hình Java toàn máy. Bản JDK thử nghiệm đã tải trong `.tools/java21` bị Git
ignore, không phải dependency phân phối của app.

10 test Rules kiểm quyền trực tiếp qua Firestore SDK. Test Dart tiếp theo kiểm
REST Auth/Firestore và trạm cloud thực hiện nguyên tử/đồng thời. Fixtures dùng
quyền `owner` của emulator để seed membership; app không có đường bypass này.
`test/emulator_rest_test.dart` được skip trong `flutter test` thường và được bật
chỉ khi chạy script trên cùng.

Rules giới hạn ai được ghi canonical; trạm Windows là thành phần được tin cậy,
không coi Rules là nơi tự tính giá vốn/kế toán. Có công cụ quản trị owner ở tools/manage-store.cjs; Auth/session đã nối UI.
Project mới đang chờ bật Auth. Chưa deploy Hosting production.

Package override grpc-js 1.14.7 xử lý advisory của phụ thuộc SDK kiểm thử;
`npm audit` sau cài đặt không còn báo lỗ hổng tại thời điểm kiểm tra. Không dùng
`npm audit fix --force` để hạ Firebase SDK sang phiên bản không tương thích.
