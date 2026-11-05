# Chạy và vận hành VLXD Bảy Hải

Đây là bản đang kiểm chứng, chưa đánh dấu đáp ứng toàn bộ V1.0. Không dùng dữ
liệu kiểm thử làm số liệu cửa hàng. Xem PROGRESS.md để biết trạng thái mới nhất.

## Firebase mới, độc lập

Project: `vlxd-bayhai-v1-261105`, Firestore Native `(default)` tại
`asia-southeast1`. Khi tạo, database trả `freeTier: true`. Không gắn Billing,
không nâng Blaze, không bật Functions/Storage, không sửa project cũ.

`config/firebase.public.json` là cấu hình ứng dụng công khai, không phải khóa
quản trị. Quyền thực tế nằm ở Auth, membership, Rules và trạm được tin cậy.
Không thêm service-account key hoặc mật khẩu vào file này.

Email/Password đã bật và Firestore Rules đã triển khai trên project này.
`node tools/manage-store.cjs status` đọc trạng thái Auth hiện tại.

## Khởi tạo tài khoản bằng quyền chủ project

Cần Firebase CLI và phiên Google có quyền trên đúng project mới. Công cụ cố
định project để không thao tác nhầm project khác. Mật khẩu nhập ẩn ở terminal,
không lưu trong source, file cấu hình hoặc nhật ký của công cụ.

```powershell
node tools/manage-store.cjs create admin admin
node tools/manage-store.cjs create banhang sales
node tools/manage-store.cjs create kho warehouse
node tools/manage-store.cjs create giaohang driver
node tools/manage-store.cjs create tram station
```

Tài khoản `admin` đầu tiên của cửa hàng đã đổi mật khẩu và được kích hoạt.
Tại màn hình đổi mật khẩu lần đầu, bấm **Kiểm tra trạng thái kích hoạt**
hoặc đăng nhập lại bằng mật khẩu mới.

Khi tạo tài khoản nhân viên mới, chủ project chạy lệnh dưới đây với tên
đăng nhập của nhân viên sau khi Firebase Authentication xác nhận đổi mật khẩu.

```powershell
node tools/manage-store.cjs activate banhang
```

Lệnh kiểm tra tài khoản đang hoạt động và thời điểm đổi mật khẩu trong Auth.
Lần kích hoạt đầu ghi nhật ký cùng lúc với cấp quyền. Chạy lại trả về trạng thái
đã kích hoạt.
Tài khoản trạm dùng mật khẩu riêng ít nhất 20 ký tự do chủ cửa hàng đặt, không
được dùng mật khẩu khởi tạo của nhân viên. Trạm không đăng nhập như nhân viên.
Không có chức năng tự đặt lại mật khẩu đã có bằng lệnh create.

```powershell
node tools/manage-store.cjs set-role banhang warehouse
node tools/manage-store.cjs disable banhang
```

Sau khi đăng nhập Admin, có thể sửa vai trò/khóa nhân viên khác qua màn hình
Nhân viên; lệnh vẫn phải được trạm kiểm quyền và ghi sổ. Không tự sửa tài khoản
trạm hoặc cờ đổi mật khẩu qua màn hình này.

## Chạy ứng dụng

Các bản 0.9.0 nằm trong thư mục `dist`.

Khi cập nhật, hãy mở bản 0.8.0 trên máy trạm trước khi gửi phiếu có nhiều
lô. Với hàng theo lô, nhập mã lô nếu chỉ dùng một lô. Nếu có nhiều lô trên
một dòng, ví dụ dòng hàng 5 đơn vị gốc, nhập `A:2; B:3`. Khi nhận hàng có
thể ghi mã màu riêng theo dạng `A:2:BE; B:3:XAM`. Khi trả hàng, nhập lô
thực trả; ứng dụng hiển thị số lượng còn được trả của từng lô. Khi bán các
lô khác mã màu, chỉ xác nhận trộn màu sau khi khách đồng ý.

- Windows: giải nén `VLXD-Bay-Hai-Windows-0.9.0.zip` rồi mở
  `app/vlxd_bay_hai.exe`. Giữ các DLL và thư mục `data` cạnh file chạy.
- Android: `VLXD-Bay-Hai-Android-0.9.0.apk` có chữ ký debug dành cho cài thử
  ngoài Play Store. Hỗ trợ Android API 24 trở lên.
- iPhone: giải nén `VLXD-Bay-Hai-PWA-0.9.0.zip` lên máy chủ tĩnh HTTPS, rồi
  thêm vào màn hình chính từ Safari theo mục PWA bên dưới.

Để chạy từ mã nguồn:

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=config/firebase.public.json
```

Username được ánh xạ thành `username+shop@bayhai.invalid`. Windows lưu phiên
trong secure storage. Cache/database tách theo UID; tài khoản khác không dùng
chung nháp hoặc outbox. Không có cấu hình Firebase thì source mở giao diện xem
thử cục bộ cũ; giao diện đó không ghi sổ cloud.

Trên Windows, phiên trạm được lưu trong kho bảo mật của tài khoản Windows đã
cấu hình. Khi chuyển sang máy khác, đăng nhập nhân viên rồi vào **Đồng bộ /
Trạm** để kết nối bằng email ánh xạ của username trạm và mật khẩu riêng. Trạm
cần còn chạy và có mạng để xác nhận nghiệp vụ của các thiết bị. Chưa có Windows Service tự
chạy khi chưa mở app. Tắt trạm: các thiết bị vẫn lập nháp/lưu lệnh chờ, không
coi đó là tồn kho hoặc công nợ đã xác nhận.

Quyền offline từ phiên đã xác minh có hiệu lực tối đa 12 giờ. Không có quyền
đăng nhập lần đầu khi chưa từng xác minh online. Những giao dịch chờ luôn được
kiểm lại quyền hiện hành, version, giá, tồn và idempotency khi xác nhận.

## Danh mục mẫu và ảnh hàng hóa

Chọn **Xem danh mục mẫu** ở màn đăng nhập hoặc **Danh mục mẫu** trong Hàng
hóa. Năm mã gạch cùng ảnh, giá và tồn minh họa nằm trong gói ứng dụng và xem
được ngoại tuyến. Giá và tồn thực tế lấy từ chứng từ của cửa hàng.

Khi thêm hoặc sửa hàng hóa, chọn ảnh minh họa có sẵn hoặc dán liên kết HTTPS
của ảnh sản phẩm. Sau khi giao dịch được xác nhận, ảnh hiện trong danh sách
hàng và ở phần chọn sản phẩm khi lập đơn. Ảnh tích hợp dùng được ngoại tuyến.
Ảnh qua liên kết HTTPS cần nguồn ảnh truy cập được trên thiết bị đang dùng.

## Thao tác chính

1. Tạo đối tác và hàng hóa; đợi xác nhận trong Đồng bộ.
2. Tạo đơn mua, nhận từng đợt để có tồn. Chỉ đặt mua không cộng tồn.
3. Lập báo giá hoặc đơn bán. Đổi khách, lượng, đơn vị, phụ thu tính ngay local.
4. Muốn giữ hàng/chờ duyệt vượt tồn: bật công tắc khi lập đơn, xem mục Giữ hàng.
5. Quản lý duyệt chờ nhập/giao phần có sẵn/từ chối. Không xuất âm kho.
6. Thu tiền nhiều lần tại đơn đã ghi sổ. Chốt ca tách tiền mặt và chuyển khoản.
7. Hàng trả vào cách ly; chỉ người có quyền mới chuyển về hàng tốt.

Tiền là số nguyên VND; lượng chính xác tới 0,001 đơn vị gốc. Đơn vị quy đổi
nhập theo hệ số của đơn vị gốc. Phiếu giữ cả lượng gốc và đơn vị bán. Khi giá
đã đổi sau lúc lập nháp, lệnh bị xung đột để người dùng kiểm tra, không tự đổi
giá âm thầm. Báo giá chuyển đơn giữ giá snapshot đã duyệt.

## Lắp bộ, xử lý hàng lỗi và bảo hành

- Trong **Hàng hóa**, nhập định mức từng thành phần theo dạng `Mã=Số lượng`.
  Đồng bộ xong, vào **Kho → Lắp bộ** để tạo phiếu. Với linh kiện theo lô,
  nhập các lô thực xuất. Với linh kiện có serial, nhập các serial thực xuất.
  Nếu thành phẩm theo lô, ghi lô nhập và mã màu nếu có. Nếu thành phẩm theo
  serial, nhập một mã mới cho mỗi bộ. Phiếu kiểm tra tồn khả dụng và chuyển
  giá vốn từ linh kiện sang bộ theo định mức đã xác nhận.
- Trong **Kho**, mở tồn cách ly hoặc hàng hỏng để xác nhận hỏng, chuyển về
  cách ly sau sửa, xuất trả nhà cung cấp hoặc xuất hủy. Có trường lý do, ảnh
  HTTPS và số phiếu nhà cung cấp. Xử lý xuất trả ghi biến động tồn. Đối chiếu
  tiền và công nợ theo chứng từ tài chính tương ứng.
- Đặt thời hạn bảo hành trong **Hàng hóa** để đơn bán mới lưu thời hạn đó.
  Khi đổi, ghi sổ phiếu trả của đơn gốc và đơn bán hàng thay thế. Quản lý mở
  phiếu bảo hành và chọn **Đối chiếu đổi bảo hành** để liên kết chứng từ.
- Nút camera trên Android và PWA có trong ô mã vạch của hàng hóa và ô tìm
  hàng khi lập đơn. PWA cần HTTPS và quyền camera. Trình duyệt dùng bộ giải
  mã dự phòng có thể cần mạng lúc mở camera lần đầu. Windows nhận mã từ
  máy quét USB dạng bàn phím hoặc ô nhập tay.

Đóng bản Windows cũ trên máy trạm và mở bản 0.8.0 trước khi gửi lệnh lắp bộ
hay xử lý hàng lỗi từ điện thoại.

## Công nợ, báo cáo kho, bảng giá và tem

- Mở một dòng ở **Thu chi / Công nợ** để xem chứng từ, lịch sử trả tiền và
  phân bổ một phiếu thu hoặc chi cho nhiều chứng từ. Quản lý nhập số tiền
  từng dòng rồi xác nhận. Khoản chi NCC cũ theo số dư vẫn hiện trong lịch sử.
- Chọn thời gian ở **Báo cáo → Nhập xuất tồn**. Có thể lọc kho, chuyển sang
  từng biến động và xuất Excel. Báo cáo tách theo chất lượng hàng và dựa vào
  lịch sử đồng bộ có trên thiết bị.
- **Excel / Sao lưu** có mẫu và nút xuất bảng giá. Dòng để trống tên bảng
  và số lượng là giá gốc. Nhập số lượng nếu muốn đặt giá theo mức mua.
  Bản xem trước cho biết giá cũ và giá mới của từng dòng.
- Trong chi tiết hàng hóa, chọn **Tem mã vạch**, mã cần in và số tem.
  Xem trước hoặc lưu PDF 60 × 40 mm. Trên Windows có thể gửi in và xem lại
  nhật ký. Chọn đúng khổ giấy trên driver trước khi in.

Đóng bản Windows cũ trên máy trạm và mở bản 0.8.0 trước khi gửi lệnh
phân bổ thanh toán từ thiết bị khác.

## In K80

Trên Windows, mở **Yêu cầu / Nhật ký in → Nhật ký trên máy này → In phiếu thử K80**.
Mẫu 80 × 100 mm có viền để kiểm tra cắt mép, chữ tiếng Việt và vạch ngang
50 mm để kiểm tra tỉ lệ. Mẫu này có thể gửi in khi máy Windows ngoại tuyến.

Khi mở lại chứng từ đã có nhật ký trên máy, kiểm tra dấu **BẢN IN LẠI** và
xác nhận trước khi in thêm. Nếu một lệnh từ điện thoại đã có kết quả trong
nhật ký Windows nhưng vẫn ở trạng thái trạm đã nhận, mở lại lệnh và chọn
**Đồng bộ kết quả đã lưu**. Thao tác này chỉ đồng bộ trạng thái. Với lệnh bị
gián đoạn giữa chừng, dùng **Đối chiếu thủ công** sau khi kiểm tra bản giấy.

Windows xem trước PDF với font tiếng Việt nhúng rồi chọn máy in trong hộp
thoại hệ thống. Máy phải có driver K80 phù hợp; tên máy in không chứng minh
đã kết nối KV804. Trạng thái `sent_to_system` chỉ là đã gửi hệ thống in.

Điện thoại bấm nút gửi trạm trên màn hình phiếu. Người vận hành Windows nhận
lệnh, đợi xác nhận quyền giữ lệnh rồi mở/in một lần. Claim có version nên hai
trạm không cùng nhận một yêu cầu. Job được ghi SQLite trước khi gọi máy in.
Sau mất điện hoặc kết quả không rõ, đối chiếu giấy và nhật ký; không retry vật
lý tự động. Bản in tiếp theo của cùng chứng từ có dấu BẢN IN LẠI.

## Excel và sao lưu

Nhập `.xlsx` theo mẫu, xem trước lỗi và mã trùng, rồi xác nhận nhập vào outbox.
Không chạy công thức Excel hoặc tự ghi đè mã có sẵn. Có xuất danh mục, đối tác,
tài chính và các sổ hiện tại. Phiếu ghi sổ vẫn do trạm kiểm từng lệnh, không
coi cả file import là một giao dịch cloud nguyên tử.

Backup `.bhbackup` mã hóa AES-GCM, có kiểm toàn vẹn và khóa suy dẫn từ mật
khẩu riêng ít nhất 10 ký tự. Giữ mật khẩu riêng với file. Khôi phục chỉ thay
database cục bộ của đúng cửa hàng/tài khoản/schema; cần xem trước, đánh dấu
đồng ý và dữ liệu chưa thay đổi từ lúc xem trước. Snapshot không ghi đè cloud;
outbox được đối chiếu receipt khi đồng bộ lại. Lịch sử nằm trong mục Sao lưu.

## PWA iPhone

```powershell
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/firebase.public.json
node tools/prepare-pwa.mjs
```

Phải phục vụ toàn bộ `build/web` qua HTTPS (localhost chỉ dành kiểm thử). Mở
Safari, Share → Add to Home Screen. Mở online lần đầu để tải đủ tài nguyên và
xác minh tài khoản. Worker chỉ cache tài nguyên app, không cache Auth/API hoặc
dữ liệu người dùng; SQLite trình duyệt giữ dữ liệu nghiệp vụ. Safari có thể
thu hồi dữ liệu website, vì vậy vẫn cần backup và đồng bộ. Không dùng Private
Browsing cho dữ liệu cần giữ. Bản cập nhật chờ người dùng lưu nháp và bấm tải
lại, không cưỡng bức reload giữa lúc nhập. Chưa kiểm thử iPhone thật.

Không có lệnh deploy tự động trong CI. Chưa publish Hosting production.
