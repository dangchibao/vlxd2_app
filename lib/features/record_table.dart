import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import 'business_pages.dart';
import 'catalog_art.dart';
import 'bayhai_style.dart';

String businessStatus(Object? value) => switch (value) {
  'posted' => 'Đã ghi sổ',
  'ordered' => 'Đã đặt',
  'received' => 'Đã nhận / Tiếp nhận',
  'partial' => 'Một phần',
  'active' => 'Đang hiệu lực',
  'converted' => 'Đã chuyển đơn',
  'delivered' => 'Đã giao',
  'assigned' => 'Đã phân công',
  'good' => 'Hàng tốt',
  'quarantine' => 'Cách ly',
  'damaged' => 'Hỏng',
  'closed' => 'Đã chốt',
  'completed' => 'Hoàn tất',
  'replaced' => 'Đã đổi hàng',
  'checking' => 'Đang kiểm tra',
  'repairing' => 'Đang sửa',
  'supplier' => 'Gửi NCC',
  'rejected' => 'Từ chối',
  'cancelled' => 'Đã hủy',
  'waiting' => 'Đang chờ',
  'pendingApproval' => 'Chờ duyệt',
  'reserved' => 'Đã giữ',
  'queued' => 'Chờ xử lý',
  'claimed' => 'Trạm đã nhận',
  'sent_to_system' => 'Đã gửi hệ thống in',
  'unknown' => 'Cần đối chiếu',
  'customer' => 'Khách hàng',
  'both' => 'Khách & NCC',
  'none' => 'Số lượng',
  'lot' => 'Theo lô',
  'serial' => 'Theo serial',
  null => '',
  _ => '$value',
};

class RecordTable extends StatelessWidget {
  final AppRuntime runtime;
  final String kind;
  final List<BusinessRecord> rows;
  final Widget Function(BuildContext, BusinessRecord, Map<String, dynamic>)
  details;
  const RecordTable({
    super.key,
    required this.runtime,
    required this.kind,
    required this.rows,
    required this.details,
  });
  List<(String, String)> get columns => switch (kind) {
    'catalog' => [
      ('imageUrl', 'Hình ảnh'),
      ('sku', 'Mã hàng'),
      ('name', 'Tên hàng'),
      ('group', 'Nhóm hàng'),
      ('model', 'Quy cách'),
      ('unit', 'ĐVT'),
      ('price', 'Giá bán'),
      ('active', 'Trạng thái'),
    ],
    'stock' => [
      ('productId', 'Hàng hóa'),
      ('warehouse', 'Kho'),
      ('quality', 'Chất lượng'),
      ('quantity', 'Tồn thực tế'),
      ('value', 'Giá trị tồn'),
    ],
    'sale' => [
      ('id', 'Mã đơn'),
      ('customerName', 'Khách hàng'),
      ('createdAt', 'Ngày'),
      ('total', 'Tổng tiền'),
      ('debt', 'Còn nợ'),
    ],
    'purchase' => [
      ('id', 'Mã mua'),
      ('supplierName', 'Nhà cung cấp'),
      ('createdAt', 'Ngày'),
      ('status', 'Trạng thái'),
      ('receivedValue', 'Đã nhận'),
    ],
    'party' => [
      ('code', 'Mã'),
      ('name', 'Đối tác'),
      ('phone', 'Điện thoại'),
      ('address', 'Địa chỉ'),
      ('type', 'Loại'),
    ],
    'quote' => [
      ('id', 'Mã báo giá'),
      ('customerName', 'Khách hàng'),
      ('version', 'Phiên bản'),
      ('total', 'Tổng tiền'),
      ('status', 'Trạng thái'),
    ],
    'delivery' => [
      ('id', 'Mã đơn'),
      ('customerName', 'Khách'),
      ('vehiclePlate', 'Xe'),
      ('scheduledAt', 'Lịch giao'),
      ('status', 'Trạng thái'),
    ],
    'receivable' ||
    'payable' => [('partyName', 'Đối tác'), ('balance', 'Số dư')],
    'warranty' => [
      ('id', 'Mã phiếu'),
      ('serial', 'Serial'),
      ('condition', 'Tình trạng'),
      ('status', 'Tiến độ'),
      ('cost', 'Chi phí'),
    ],
    _ => [
      ('id', 'Mã chứng từ'),
      ('createdAt', 'Ngày'),
      ('status', 'Trạng thái'),
      ('amount', 'Số tiền'),
    ],
  };
  Widget cell(BusinessRecord row, Map<String, dynamic> data, String key) {
    final value = key == 'partyName' ? data[key] ?? data['id'] : data[key];
    if (key == 'imageUrl') return ProductPhoto(value, size: 44);

    if (kind == 'catalog' && key == 'active') {
      final isActive = value != false;
      final color = isActive ? BayHaiStyle.green : BayHaiStyle.muted;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8F7F1) : const Color(0xFFF0F3F7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          isActive ? 'Đang kinh doanh' : 'Ngừng kinh doanh',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }

    if (kind == 'catalog' && key == 'group') {
      final label = value is String && value.trim().isNotEmpty
          ? value.trim()
          : 'Chưa phân nhóm';
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 145),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: BayHaiStyle.muted),
        ),
      );
    }

    if (kind == 'catalog' && key == 'sku') {
      return Text(
        '${value ?? '—'}',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0059D6),
        ),
      );
    }

    if (kind == 'catalog' && key == 'name') {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(
          '${value ?? '—'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF162B4A),
          ),
        ),
      );
    }
    if (key == 'productId' && value is String) {
      final db = runtime.db;
      return FutureBuilder(
        future: (db.select(
          db.products,
        )..where((p) => p.id.equals(value))).getSingleOrNull(),
        builder: (context, snapshot) =>
            Text(snapshot.data?.name ?? shortId(value)),
      );
    }
    if ({
      'price',
      'value',
      'total',
      'debt',
      'receivedValue',
      'balance',
      'cost',
      'amount',
    }.contains(key)) {
      return Text(
        value is int ? vnd(value) : '—',
        style: TextStyle(
          fontWeight: kind == 'catalog' && key == 'price'
              ? FontWeight.w700
              : FontWeight.normal,
          color: kind == 'catalog' && key == 'price'
              ? BayHaiStyle.primary
              : key == 'debt' && value is int && value > 0
              ? Colors.orange.shade900
              : null,
        ),
      );
    }
    if (key == 'quantity') return Text(value is int ? qty(value) : '—');
    if ({'status', 'quality', 'type'}.contains(key)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          businessStatus(value),
          style: TextStyle(color: Colors.blue.shade900, fontSize: 12),
        ),
      );
    }
    if (key == 'createdAt') {
      final date = DateTime.tryParse('$value');
      return Text(
        date == null ? '—' : DateFormat('dd/MM/yyyy').format(date.toLocal()),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: key == 'name' || key == 'address' ? 220 : 160,
      ),
      child: Text(
        key == 'id' ? shortId(value as String? ?? row.id) : '${value ?? '—'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void open(
    BuildContext context,
    BusinessRecord row,
    Map<String, dynamic> data,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Chi tiết • ${shortId(data['id'] as String? ?? row.id)}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(child: details(context, row, data)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, size) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BayHaiStyle.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: size.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  dividerThickness: 0.6,
                  columnSpacing: kind == 'catalog' ? 22 : 28,
                  horizontalMargin: 20,
                  headingRowHeight: 52,
                  headingRowColor: const WidgetStatePropertyAll(
                    Color(0xFFEAF2FF),
                  ),
                  headingTextStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF12386D),
                  ),
                  dataTextStyle: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1D2C43),
                  ),
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 72,
                  columns: [
                    for (final c in columns) DataColumn(label: Text(c.$2)),
                    const DataColumn(label: Text('Thao tác')),
                  ],
                  rows: [
                    for (var i = 0; i < rows.length; i++)
                      buildRow(context, rows[i], i),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  DataRow buildRow(BuildContext context, BusinessRecord row, int index) {
    final data = recordData(row);
    return DataRow(
      color: WidgetStatePropertyAll(
        index.isEven ? Colors.white : const Color(0xFFF6F9FE),
      ),
      onSelectChanged: (_) => open(context, row, data),
      cells: [
        for (final c in columns) DataCell(cell(row, data, c.$1)),
        DataCell(
          IconButton(
            tooltip: 'Mở chi tiết và thao tác',
            onPressed: () => open(context, row, data),
            icon: const Icon(Icons.more_horiz, color: BayHaiStyle.primary),
          ),
        ),
      ],
    );
  }
}
