# Kiến trúc và schema đề xuất — chờ phê duyệt

## 1. Cấu trúc

Một codebase Flutter/Dart, phân lớp theo feature: presentation → application/use cases → domain → repositories/adapters. Riverpod điều khiển state, go_router điều hướng, Drift là nguồn dữ liệu đọc cho UI. Adapter platform tách SQLite native/Web, Auth/Firestore, printer, file, camera và map. Chưa tạo các lớp hoặc migration.

UI xử lý `onChanged` ngay trên state: giá, đơn vị, số lượng, chiết khấu, trả tiền, chênh lệch ca và công cụ vật liệu. Không debounce tính tiền; chỉ debounce tìm kiếm/lưu nháp phù hợp. Database watch cập nhật danh sách; không ghi đè nội dung người dùng đang sửa bằng snapshot sync. Giá theo khách/nhóm số lượng lấy từ cache local; thiếu dữ liệu phải báo thiếu, không giả định giá bằng 0.

## 2. Quyền xác nhận trên Spark — phương án A đề nghị

Android/PWA/Windows tạo command bất biến trong hàng đợi. Chỉ một trạm Windows được quản trị cho phép xử lý command và ghi các journal/balance đã xác nhận bằng Firestore transaction. Trạm dùng tài khoản Firebase riêng với quyền giới hạn bởi Rules; không nhúng service-account/Admin SDK hoặc khóa bí mật trong ứng dụng phân phối. Người bán không được ghi confirmed balance/journal; không được tự gắn role/approval.

Đây là **trạm được tin cậy bởi cửa hàng**, không phải backend chống được chủ trạm cố tình sửa phần mềm hoặc đánh cắp tài khoản trạm. Rules chỉ ràng buộc phạm vi, cấu trúc, quyền và bất biến có thể biểu diễn; không tính toàn bộ giá vốn/kế toán tùy ý. Nếu yêu cầu bảo vệ trước cả trạm bị xâm nhập hoặc xác nhận 24/7 khi trạm tắt, phương án này không đáp ứng; phải chọn backend có thẩm quyền khác và xin duyệt kiến trúc/chi phí trước.

- Trạm tắt/mất mạng: các máy lập đơn local và chờ; không phát sinh xác nhận cuối cùng giả. Người dùng có thể ghi nhận tiền đã thực nhận thành sự kiện tạm chờ đối soát, không đồng nghĩa số dư cloud đã chốt.
- Windows offline vẫn lưu nháp, phiếu tạm, in local có nhãn trạng thái; xuất hàng khi chưa xác nhận có rủi ro vận hành và không được coi là bảo đảm tồn liên thiết bị.
- Trạm có lease/epoch, nhưng lease không thay thế transaction. Hai worker hoặc worker cũ phải cùng kiểm tra receipt/idempotency và version trong transaction.
- Phê duyệt vượt tồn/hoàn tiền/điều chỉnh là command riêng của quản lý; khi xử lý kiểm lại quyền hiện hành, nội dung phê duyệt và version. Không cấp quyền dựa trên cache role offline.
- Không thể provision Auth user khác từ client bằng Admin SDK. Đề xuất công cụ bootstrap/quản trị chạy cục bộ với xác thực quản trị tạm thời, không lưu credential vào repo, chờ duyệt tài nguyên thật; quy trình disable user phải đồng thời chặn qua membership Rules.

Phương án B chỉ để quyết định nếu A không phù hợp: backend quản lý có thẩm quyền bên ngoài Spark, hoặc giảm yêu cầu xác nhận từ xa. Không tự triển khai B.

## 3. Sync protocol

1. Trong cùng transaction SQLite: ghi aggregate local + outbox command + audit local. ID ngẫu nhiên duy nhất; mã dễ đọc có prefix thiết bị để tránh trùng offline.
2. Command có `storeId, commandId, deviceId, actorUid, aggregateId, expectedVersion, schemaVersion, payloadHash, payload, dependencies, createdAtLocal`. Server timestamp riêng; giờ máy không quyết định thứ tự ghi sổ.
3. Uploader gửi command theo ID ổn định; không ghi đè command cùng ID khác hash. Rules kiểm membership, ownership, loại thao tác, trường được phép và giới hạn payload.
4. Trạm đọc command, kiểm quyền hiện hành, approval, reference, version, tồn tốt/đặt giữ, serial, số dư và giới hạn nghiệp vụ; tính tiền/giá vốn lại bằng dữ liệu chuẩn.
5. Một Firestore transaction ghi receipt theo commandId, journal, projection số dư/tồn, version, audit và event xác nhận. Receipt tồn tại cùng hash → trả kết quả cũ; khác hash → từ chối. Side effect in/file không chạy bên trong callback transaction.
6. Nếu transaction quá lớn hoặc Rules vượt giới hạn, không chia nhỏ một chứng từ ghi sổ để rồi nhận một nửa. Đặt giới hạn số dòng qua thử nghiệm, từ chối có giải thích hoặc thiết kế saga có trạng thái tường minh được duyệt trước.
7. Client tải event đã commit theo sequence của cửa hàng; apply event + checkpoint trong một transaction SQLite. Event theo ID không apply hai lần. Sequence được cấp trong transaction trạm; phân trang/catch-up, không quét toàn bộ collection mỗi lần mở app.
8. Retry exponential backoff + jitter, giới hạn tốc độ và attempt; permission/validation đưa lỗi cần xử lý; version đưa conflict; timeout kiểm receipt trước khi gửi lại. Crash giữa upload/ack/apply vẫn phục hồi được.

Trạng thái lưu trữ: draft → local_saved → pending → syncing → confirmed; nhánh conflict/error và retry quay lại pending. `local_saved` là bền vững trên thiết bị; `confirmed` chỉ khi receipt hợp lệ. Trạng thái nghiệp vụ đơn (đặt hàng/đã ghi sổ/đã hủy), thanh toán và giao hàng tách riêng khỏi trạng thái sync.

Conflict master data có thể cho người có quyền chọn phiên bản sau so sánh trường. Kho/tiền/công nợ/serial tuyệt đối không last-write-wins. Khi command đơn đã xác nhận: sửa bằng chứng từ đảo/điều chỉnh có tham chiếu, không cập nhật lịch sử.

## 4. Kiểu dữ liệu và schema logic

Mọi bảng có `store_id`; entity có `id`, version, timestamp local/server và audit actor phù hợp. SQLite FK bật, unique/check/index đầy đủ. Xóa master data theo trạng thái lưu trữ, không cascade xóa journal.

Tiền: VND số nguyên; phép nhân/chia dùng integer/BigInt hoặc decimal chính xác. Vì Dart Web có giới hạn số nguyên chính xác, kiểm tra biên giá trị và lưu số lớn dưới dạng chuỗi chuẩn khi truyền JSON. Số lượng decimal có scale theo đơn vị; quy đổi dùng tử/mẫu dương chính xác, không dùng `double` cho sổ. Quy định làm tròn nửa lên tại tiền từng dòng, tổng bằng tổng dòng đã làm tròn; mọi điều chỉnh làm tròn có dòng riêng. Giá vốn giữ độ chính xác cao và phần dư có kiểm soát.

| Nhóm | Bảng chính và dữ liệu |
|---|---|
| Cửa hàng/quyền | stores, devices, user_profiles, memberships, roles, permissions, role_permissions, approvals; membership liên kết Auth UID; không lưu password |
| Danh mục | categories, brands, units, products(SKU/barcode/model/tracking/min_stock/active), product_attributes, variants, product_units(numerator/denominator), bundle_components, compatibility_links |
| Giá | price_lists, price_rules(customer/group/unit/min_quantity/effective dates), price_history; không sửa snapshot chứng từ cũ |
| Đối tác | parties(customer/supplier/both), addresses, customer_price_lists, credit_terms |
| Bán/báo giá | quotes, quote_versions, quote_lines, sales_orders, sales_lines, draft_revisions; dòng có snapshot tên/SKU/quy cách/đơn vị/giá/quy đổi/thuế/chiết khấu; totals và version |
| Mua | purchase_orders, purchase_lines, goods_receipts, receipt_lines, purchase_cost_allocations; received_quantity theo từng dòng, accepted/rejected/extra tách riêng |
| Kho | warehouses, stock_positions(product/warehouse/lot/quality), stock_movements, reservations, transfers, counts, adjustments, quality_transfers |
| Lô/serial | lots(product/supplier/color/batch/received_at), serials(product/status/location), serial_events; serial chuẩn hóa unique trong cửa hàng; mỗi xuất phải kiểm trạng thái hiện tại |
| Tài chính | journal_entries, journal_lines, payments, payment_allocations, refund_documents, debt_entries, expenses; chứng từ gốc/đảo, đối tác, currency, account, amount và cost snapshot |
| Ca | shifts(employee/opening/expected/counted/difference/explanation), shift_reconciliations; tiền mặt và chuyển khoản riêng |
| Giao | deliveries, delivery_lines, trips, vehicles, drivers, delivery_costs; order line reference, scheduled/actual, load/coordinates |
| Bảo hành/trả | returns, return_lines, warranty_cases, warranty_events, warranty_attachments; original sale/serial/condition/accessories/cost/status |
| Vận hành | outbox, command_receipts, inbox_events, sync_checkpoints, sync_errors, audit_events, alerts, print_jobs, print_attempts, backup_history, import_batches, import_rows, attachment_metadata |

Ràng buộc: unique(store,SKU), barcode nếu có và policy không dùng chung; unique(store,commandId), unique(eventId), unique(stockMovement source line/type), unique(payment business key), unique(alert type/entity/threshold window), unique(printJobId). Các số tiền phải không âm theo loại chứng từ; phân bổ không vượt tiền thu hoặc số nợ còn lại; journal cân đối debit/credit. Giới hạn trả/giao/nhận dựa trên tổng chứng từ đã xác nhận, không chỉ tổng trên UI.

Cloud đề xuất `stores/{storeId}` với subcollections membership, catalog, commands, receipts, events, balances, documents, journals, audits, settings. Receipt/event canonical do trạm ghi; client chỉ tạo command. SQLite giữ mô hình quan hệ, cloud dùng tài liệu có giới hạn kích thước; không sao chép nguyên một order vô hạn vào một document. Chưa có DDL/migration thực thi; schema chi tiết và Rules proof là đầu ra giai đoạn 1.

## 5. Bất biến nghiệp vụ

- Kho bán được chỉ từ trạng thái tốt; available = good_on_hand - reserved. Tồn cách ly/hỏng không dùng để xác nhận xuất. Vượt tồn tạo yêu cầu quản lý; duyệt chờ nhập/giao phần sẵn có/từ chối, không cho balance âm.
- Đơn mua không tăng tồn. Đặt 100 nhận 60 tốt → tăng 60, còn 40; số dư/hàng lỗi xử lý bằng chứng từ và quyền riêng.
- Giao nhiều chuyến không trừ kho lần nữa nếu đã ghi xuất. Chọn thời điểm ghi xuất theo phiếu xuất gắn chuyến, reservation giải phóng đúng số lượng; tổng giao/hoàn không vượt lượng hợp lệ.
- Sổ công nợ phát sinh từ chứng từ; thu nợ cũ ghi vào ca thực thu; nợ chưa thu không phải tiền mặt. Hoàn tiền và trả hàng là hai sự kiện liên kết nhưng không tự đồng nghĩa.
- Giá vốn bình quân liên hoàn theo sản phẩm/kho: sau nhập, `(giá trị tồn trước + giá trị nhập + chi phí hợp lệ phân bổ)/(lượng tồn trước + lượng nhập)`. Xuất giữ cost snapshot và giảm giá trị đúng số đã ghi. Chuyển kho mang giá trị xuất nguồn vào nhập đích; trả bán tham chiếu cost gốc khi có căn cứ.
- Nhập muộn: ghi ngày nghiệp vụ và ngày ghi sổ riêng; không âm thầm sửa giá vốn xuất quá khứ. Cần lệnh tính lại có quyền quản lý, khóa phạm vi, lập chênh lệch giá vốn và audit; đặc tả chi tiết phải được kiểm thử trước dùng thực tế.
- Bảo hành nhận hàng vào cách ly; đổi mới cần phiếu xuất, hàng nhận lại cần kiểm chất lượng trước tái bán.
- Chốt ca offline chỉ tạm; kỳ vọng tiền = đầu ca + thực thu tiền mặt - thực chi tiền mặt - hoàn tiền mặt. Xác nhận cuối chờ mọi command liên quan được xử lý.

## 6. Bảo mật, đăng nhập và phục hồi

Username chuẩn hóa ánh xạ vào định danh Auth dạng email nội bộ theo store; mapping không cho liệt kê công khai, Auth UID là khóa quyền. Bootstrap `admin` bằng công cụ tương tác: nhập mật khẩu ban đầu do chủ cửa hàng cung cấp, không đưa literal vào code/seed/log/CI. Bắt buộc đổi lần đầu, các command nghiệp vụ bị chặn đến khi cờ đổi mật khẩu được xác nhận theo quy trình có thẩm quyền; không chỉ kiểm tra màn hình.

Offline chỉ mở phiên đã xác thực/cache trên thiết bị được phép; chưa đăng nhập lần nào cần mạng. Thu hồi quyền không có hiệu lực tức thì khi mất mạng: hạn chế thời hạn phiên offline, chặn thao tác quản lý offline và kiểm quyền lại khi sync. Token lưu trong cơ chế bảo vệ của nền tảng khi khả dụng; PWA không có mức bảo vệ tương đương Windows credential store. Không ghi token/password vào log.

Role baseline: Admin quản trị; Quản lý duyệt/đối soát; Bán hàng lập đơn/thu trong phạm vi; Kho nhập/xuất/kiểm theo quyền; Giao hàng chỉ dữ liệu chuyến được giao. Action permissions kiểm ở use case, Rules và trạm; test gọi trực tiếp API để chống vượt UI.

Backup SQLite tạo snapshot nhất quán, manifest schema/app/store/device/checkpoint, checksum và attachments; mã hóa khi chứa dữ liệu nhạy cảm, khóa không nằm cùng bản sao. Restore vào database tạm để integrity_check, FK check và kiểm schema; đóng băng sync trong quá trình đổi. Không upload nguyên snapshot đè cloud: đối chiếu receipt/checkpoint, replay command chưa xác nhận có kiểm version; conflict chuyển xử lý. Restore trạm cần phục hồi lease an toàn và kiểm cloud mới hơn trước khi kích hoạt.

## 7. Máy in và hóa đơn điện tử

Render PDF K80 với font nhúng tiếng Việt, layout theo chiều rộng in thực tế của driver; PrintingAdapter Windows ghi job local bền vững và spool. Điện thoại tạo yêu cầu in cùng ID tới trạm qua Firestore khi online; Windows tự in local khi offline. In từ điện thoại khi mất Internet chưa được bảo đảm; LAN endpoint là phần mở rộng cần thiết kế pairing/TLS và kiểm Safari trước khi hứa hỗ trợ.

Retry chỉ tự thực hiện trước khi có bằng chứng spool đã nhận. Nếu kết quả không rõ, giữ `unknown`, yêu cầu người vận hành kiểm tra và in lại có audit. Không tuyên bố chống tuyệt đối hai tờ giấy qua sự cố nguồn.

EInvoiceAdapter chỉ chuẩn bị DTO người mua/dòng/thuế cấu hình/định danh; không đặt thuế mặc định, không phát hành hay mua dịch vụ. Phiếu K80 dùng tên phiếu bán hàng, không khiến người dùng hiểu là hóa đơn điện tử hợp pháp đã phát hành.
