# Bàn giao VLXD Bảy Hải 1.0.0

Bộ cài trong `dist` gồm Windows 11, APK Android để cài thử và gói web
PWA. Dùng [hướng dẫn vận hành](RUNNING_AND_SETUP.md) để cài trên iPhone,
thiết lập trạm Windows, cấu hình Firebase, in K80 và diễn tập sao lưu.
Cập nhật trạm Windows lên 1.0.0 trước khi gửi phiếu in từng chuyến.

Giao diện điện thoại lấy ảnh `design_reference/VLXD Bảy Hải App Screens.png`
làm tham chiếu. Các màn dùng chung bảng màu, nút, thẻ, ô tìm kiếm và thanh
điều hướng. Trang chủ có chín lối tắt. Mục **Thêm** giữ các chức năng
quản trị, đồng bộ và sao lưu trong cùng thanh điều hướng.

| Việc cần làm | Nơi thực hiện |
| --- | --- |
| Khai báo mã hàng, lô/serial, giá và định mức bộ | Hàng hóa, Excel / Sao lưu |
| Báo giá, lập đơn, thu tiền, trả hàng | Báo giá, Bán hàng, Thu chi / Công nợ |
| Mua, nhận từng đợt, chuyển kho, kiểm kê, lắp bộ | Mua hàng, Kho, Chứng từ |
| Kiểm tra từng chuyến và lập phiếu chi | Giao hàng → Từng chuyến |
| Tiếp nhận, sửa chữa hoặc đổi bảo hành | Bảo hành, Chứng từ |
| Đối chiếu quỹ, công nợ và lợi nhuận | Thu chi / Công nợ, Báo cáo |
| Kiểm tra tồn theo kỳ và xuất chứng từ Excel | Báo cáo → Nhập xuất tồn |
| Xem trước, in và đối chiếu trạng thái | Chứng từ, Yêu cầu / Nhật ký in |
| Quản lý tài khoản, đồng bộ và bản sao lưu | Nhân viên, Thiết lập, Excel / Sao lưu |

Phiếu chờ đồng bộ chỉ là dữ liệu tạm. Trạm xác nhận tồn và công nợ khi
có kết nối. Một số báo cáo lấy từ lịch sử đã đồng bộ của thiết bị.
Khi NCC giao dư và cửa hàng chấp nhận mua thêm, lập đơn mua bổ sung để
ghi nhận lượng dư. Hóa đơn điện tử ở mức chuẩn bị dữ liệu theo cấu hình.

Đã chạy 96 ca kiểm thử ứng dụng và 11 ca kiểm tra quyền, tích hợp trên
Firebase mô phỏng. Các ca kiểm tra bổ sung đối chiếu màn hình mobile
390 × 844 và tệp Excel có dữ liệu trong, ngoài khoảng ngày đã chọn.

Các bước nghiệm thu còn lại dùng thiết bị của cửa hàng. In phiếu bán, thu
và lắp bộ trên K80, kiểm tra tiếng Việt, khổ giấy và trạng thái khi ngắt USB.
Trên Android và iPhone, kiểm tra camera, cài PWA từ Safari và lưu nháp khi
mất mạng rồi mở lại. APK dùng chữ ký thử nghiệm. Gói PWA cần máy chủ tĩnh
HTTPS để cài từ Safari.
