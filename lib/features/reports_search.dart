import 'dart:convert';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../domain/financial_report.dart';
import '../data/xlsx_catalog.dart';
import 'business_pages.dart';

class ReportsPage extends StatefulWidget {
  final AppRuntime runtime;
  const ReportsPage({super.key, required this.runtime});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  int days = 30;
  String exportKind = 'stock';
  Future<void> exportSummary(
    FinancialReport report,
    DateTime start,
    DateTime end,
  ) async {
    try {
      await FilePicker.saveFile(
        fileName: 'bao-cao-tai-chinh.xlsx',
        bytes: XlsxCatalog().table(
          ['Chỉ tiêu', 'Giá trị VND / Số lượng'],
          [
            ['Từ ngày', start.toIso8601String()],
            ['Đến trước ngày', end.toIso8601String()],
            ['Doanh thu thuần', report.revenue.toString()],
            ['Giá vốn', report.cost.toString()],
            ['Lợi nhuận gộp', report.grossProfit.toString()],
            ['Chi phí', report.expenses.toString()],
            ['Sau chi phí', report.netProfit.toString()],
            ['Tiền mặt', report.cashNet.toString()],
            ['Chuyển khoản', report.bankNet.toString()],
            ['Số đơn bán', report.sales],
          ],
        ),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (_) {
      if (mounted) feedback(context, 'Không xuất được báo cáo.');
    }
  }

  Future<void> exportRecords() async {
    try {
      final kind = exportKind, db = widget.runtime.db;
      final rows =
          await (db.select(db.businessRecords)
                ..where((r) => r.kind.equals(kind))
                ..limit(20001))
              .get();
      if (rows.length > 20000) {
        throw const FormatException('Chọn khoảng dữ liệu nhỏ hơn 20.000 dòng.');
      }
      final columns = switch (kind) {
        'stock' => ['productId', 'warehouse', 'quality', 'quantity', 'value'],
        'receivable' || 'payable' => ['balance'],
        'sale' => [
          'customerId',
          'createdAt',
          'total',
          'paid',
          'debt',
          'returnedValue',
          'cost',
        ],
        'purchase' => ['supplierId', 'createdAt', 'status', 'receivedValue'],
        'delivery' => [
          'customerId',
          'driverId',
          'vehiclePlate',
          'scheduledAt',
          'status',
          'address',
        ],
        'warranty' => [
          'customerId',
          'saleId',
          'serial',
          'condition',
          'status',
          'cost',
        ],
        'shiftClose' => [
          'shiftId',
          'opening',
          'expected',
          'counted',
          'difference',
          'bankNet',
        ],
        _ => ['status'],
      };
      const labels = {
        'id': 'Mã',
        'productId': 'Hàng hóa',
        'warehouse': 'Kho',
        'quality': 'Chất lượng',
        'quantity': 'Số lượng gốc',
        'value': 'Giá trị VND',
        'balance': 'Số dư VND',
        'customerId': 'Khách hàng',
        'supplierId': 'Nhà cung cấp',
        'createdAt': 'Ngày tạo',
        'total': 'Tổng VND',
        'paid': 'Đã thu VND',
        'debt': 'Còn nợ VND',
        'returnedValue': 'Giá trị trả VND',
        'cost': 'Giá vốn / Chi phí VND',
        'status': 'Trạng thái',
        'receivedValue': 'Giá trị đã nhận VND',
        'driverId': 'Tài xế',
        'vehiclePlate': 'Xe',
        'scheduledAt': 'Lịch giao',
        'address': 'Địa chỉ',
        'saleId': 'Đơn bán',
        'serial': 'Serial',
        'condition': 'Tình trạng',
        'shiftId': 'Ca',
        'opening': 'Đầu ca VND',
        'expected': 'Dự kiến VND',
        'counted': 'Thực đếm VND',
        'difference': 'Lệch VND',
        'bankNet': 'Chuyển khoản VND',
      };
      await FilePicker.saveFile(
        fileName: 'bao-cao-$kind.xlsx',
        bytes: XlsxCatalog().table(
          ['Mã', ...columns.map((c) => labels[c] ?? c)],
          [
            for (final row in rows)
              [
                row.id,
                ...columns.map((c) {
                  final value = recordData(row)[c];
                  return c == 'quantity' && value is int
                      ? qty(value)
                      : value as Object?;
                }),
              ],
          ],
        ),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      if (mounted) {
        feedback(
          context,
          e is FormatException ? e.message : 'Không xuất được báo cáo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: widget.runtime.db.select(widget.runtime.db.businessEvents).watch(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('Không đọc được sổ giao dịch.'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final now = DateTime.now(),
          start = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: days - 1)),
          end = DateTime(now.year, now.month, now.day + 1);
      final events = snapshot.data!,
          report = FinancialReport.fromEvents(events, start, end);
      return ListView(
        children: [
          Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Báo cáo đã xác nhận',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              DropdownButton<int>(
                value: days,
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 ngày')),
                  DropdownMenuItem(value: 30, child: Text('30 ngày')),
                  DropdownMenuItem(value: 90, child: Text('90 ngày')),
                ],
                onChanged: (v) => setState(() => days = v!),
              ),
              OutlinedButton.icon(
                onPressed: () => exportSummary(report, start, end),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Xuất tài chính Excel'),
              ),
            ],
          ),
          Text(
            '${DateFormat('dd/MM/yyyy').format(start)} – ${DateFormat('dd/MM/yyyy').format(end.subtract(const Duration(days: 1)))}',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: exportKind,
                items: [
                  for (final pair in [
                    ('stock', 'Tồn kho'),
                    ('receivable', 'Nợ khách hàng'),
                    ('payable', 'Nợ NCC'),
                    ('sale', 'Bán hàng'),
                    ('purchase', 'Mua hàng'),
                    ('delivery', 'Giao hàng'),
                    ('warranty', 'Bảo hành'),
                    ('shiftClose', 'Chốt ca'),
                  ])
                    DropdownMenuItem(value: pair.$1, child: Text(pair.$2)),
                ],
                onChanged: (v) => setState(() => exportKind = v!),
              ),
              OutlinedButton(
                onPressed: exportRecords,
                child: const Text('Xuất sổ hiện tại Excel'),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in [
                ('Doanh thu thuần', report.revenue),
                ('Giá vốn thuần', report.cost),
                ('Lợi nhuận gộp', report.grossProfit),
                ('Chi phí vận hành', report.expenses),
                ('Sau chi phí', report.netProfit),
                ('Thu/chi tiền mặt', report.cashNet),
                ('Thu/chi chuyển khoản', report.bankNet),
              ])
                SizedBox(
                  width: 240,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.$1),
                          const SizedBox(height: 8),
                          Text(
                            largeVnd(entry.$2),
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: entry.$2.isNegative
                                  ? Colors.red
                                  : Colors.blue.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Đơn bán trong kỳ: ${report.sales}'),
          const SizedBox(height: 16),
          const Text(
            'Doanh thu trừ hàng trả; giá vốn theo snapshot khi xuất. Thu nợ và trả NCC không cộng thêm doanh thu hoặc chi phí vận hành.',
          ),
          const SizedBox(height: 20),
          for (final event
              in events.reversed
                  .where(
                    (e) =>
                        !e.occurredAt.isBefore(start) &&
                        e.occurredAt.isBefore(end),
                  )
                  .take(100))
            Card(
              child: ListTile(
                title: Text(switch (event.kind) {
                  'sale' => 'Ghi sổ bán hàng',
                  'returnSale' => 'Ghi nhận trả hàng',
                  'payment' => 'Thu tiền',
                  'refund' => 'Hoàn tiền',
                  'expense' => 'Chi phí',
                  'supplierPayment' => 'Trả tiền NCC',
                  _ => 'Cập nhật chứng từ',
                }),
                subtitle: Text(
                  '${DateFormat('dd/MM HH:mm').format(event.occurredAt.toLocal())} • ${event.commandId.substring(0, event.commandId.length < 8 ? event.commandId.length : 8)}',
                ),
              ),
            ),
        ],
      );
    },
  );
}

class GlobalSearchPage extends StatefulWidget {
  final AppRuntime runtime;
  const GlobalSearchPage({super.key, required this.runtime});
  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  String query = '';
  List<Product> products = [];
  List<BusinessRecord> records = [];
  bool busy = false;
  int generation = 0;
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> search(String value) async {
    final current = ++generation;
    setState(() {
      query = value.toLowerCase().trim();
      busy = true;
    });
    final p = await widget.runtime.db.select(widget.runtime.db.products).get();
    final r = await widget.runtime.db
        .select(widget.runtime.db.businessRecords)
        .get();
    if (!mounted || current != generation) return;
    setState(() {
      products = p
          .where((p) => '${p.sku} ${p.name}'.toLowerCase().contains(query))
          .take(40)
          .toList();
      records = r
          .where(
            (r) =>
                {
                  'sale',
                  'purchase',
                  'party',
                  'warranty',
                  'serial',
                  'catalog',
                  'quote',
                  'reservation',
                  'delivery',
                  'inventoryCount',
                }.contains(r.kind) &&
                '${r.id} ${r.payload}'.toLowerCase().contains(query),
          )
          .take(60)
          .toList();
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Tìm kiếm toàn hệ thống',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Mã đơn, tên hàng, SKU, khách hàng, số điện thoại…',
        ),
        onChanged: (value) {
          debounce?.cancel();
          debounce = Timer(
            const Duration(milliseconds: 200),
            () => search(value),
          );
        },
      ),
      const SizedBox(height: 12),
      Expanded(
        child: query.isEmpty
            ? const Center(
                child: Text(
                  'Nhập thông tin để tìm trong dữ liệu trên thiết bị.',
                ),
              )
            : busy
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  for (final p in products)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(p.name),
                        subtitle: Text(
                          '${p.sku} • ${vnd(p.price)} / ${p.unit}',
                        ),
                      ),
                    ),
                  for (final r in records)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          r.kind == 'party'
                              ? Icons.person_outline
                              : Icons.description_outlined,
                        ),
                        title: Text(
                          (jsonDecode(r.payload)
                                      as Map<String, dynamic>)['name']
                                  as String? ??
                              '${r.kind} • ${shortId(r.id.split(':').last)}',
                        ),
                        subtitle: const Text('Mở chi tiết chứng từ'),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Chi tiết'),
                            content: SizedBox(
                              width: 540,
                              child: SingleChildScrollView(
                                child: RecordDetails(
                                  data: jsonDecode(
                                    r.payload,
                                  ) as Map<String, dynamic>,
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Đóng'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

class RecordDetails extends StatelessWidget {
  final Map<String, dynamic> data;
  const RecordDetails({super.key, required this.data});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final key in [
        'name',
        'sku',
        'phone',
        'address',
        'status',
        'createdAt',
        'group',
        'barcode',
        'brand',
        'model',
        'tracking',
        'serial',
        'lotId',
        'colorCode',
        'scheduledAt',
        'reason',
        'condition',
        'accessories',
      ])
        if (data[key] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${switch (key) {
                'name' => 'Tên',
                'sku' => 'Mã hàng',
                'phone' => 'Điện thoại',
                'address' => 'Địa chỉ',
                'status' => 'Trạng thái',
                'createdAt' => 'Ngày tạo',
                'group' => 'Nhóm hàng',
                'barcode' => 'Barcode',
                'brand' => 'Thương hiệu',
                'model' => 'Model',
                'tracking' => 'Theo dõi tồn',
                'serial' => 'Serial',
                'lotId' => 'Mã lô',
                'colorCode' => 'Mã màu',
                'scheduledAt' => 'Lịch',
                'reason' => 'Lý do',
                'condition' => 'Tình trạng',
                _ => 'Phụ kiện',
              }}: ${data[key]}',
            ),
          ),
      for (final key in [
        'total',
        'paid',
        'debt',
        'cost',
        'refundDue',
        'amount',
        'surcharge',
      ])
        if (data[key] is int)
          Text(
            '${switch (key) {
              'total' => 'Tổng tiền',
              'paid' => 'Đã thu',
              'debt' => 'Còn nợ',
              'cost' => 'Giá vốn',
              'refundDue' => 'Chờ hoàn',
              'amount' => 'Số tiền',
              _ => 'Phụ thu',
            }}: ${vnd(data[key] as int)}',
          ),
      if (data['lines'] is List)
        for (final line in data['lines'] as List)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(line['name'] as String? ?? line['productId'] as String),
            subtitle: Text('Số lượng: ${qty(line['quantity'] as int)}'),
          ),
      for (final key in ['attributes', 'units', 'priceLists'])
        if (data[key] is Map && (data[key] as Map).isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(switch (key) {
            'attributes' => 'Thuộc tính',
            'units' => 'Quy đổi đơn vị',
            _ => 'Bảng giá',
          }, style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final e in (data[key] as Map).entries)
            Text('${e.key}: ${key == 'units' ? qty(e.value as int) : e.value}'),
        ],
    ],
  );
}
