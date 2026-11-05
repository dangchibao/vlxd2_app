import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_runtime.dart';
import '../data/xlsx_catalog.dart';
import '../domain/financial_report.dart';
import '../domain/stock_period.dart';
import 'business_pages.dart' show feedback, shortId;
import 'record_table.dart' show businessStatus;

class StockPeriodPage extends StatefulWidget {
  final AppRuntime runtime;
  final DateTime start, end;
  const StockPeriodPage({
    super.key,
    required this.runtime,
    required this.start,
    required this.end,
  });

  @override
  State<StockPeriodPage> createState() => _StockPeriodPageState();
}

class _StockPeriodPageState extends State<StockPeriodPage> {
  late final report = loadReport();
  String? warehouse;
  bool detail = false;

  Future<StockPeriod> loadReport() {
    final db = widget.runtime.db;
    return db.transaction(() async {
      final inbox =
          await (db.select(db.inboxEvents)
                ..where(
                  (row) => row.storeId.equals(widget.runtime.config.storeId),
                )
                ..where((row) => row.payload.contains('"kind":"stock"')))
              .get();
      final events = await db.select(db.businessEvents).get();
      return StockPeriod.fromLedger(inbox, events, widget.start, widget.end);
    });
  }

  String operationLabel(String operation) => switch (operation) {
    'receive' => 'Nhập hàng',
    'sale' || 'quoteToSale' || 'fulfillReservation' => 'Xuất bán',
    'returnSale' => 'Nhận hàng trả',
    'transfer' => 'Chuyển kho',
    'inventoryCount' => 'Kiểm kê',
    'assemble' => 'Lắp bộ',
    'quarantine' || 'release' || 'qualityDisposition' => 'Xử lý chất lượng',
    _ => operation,
  };

  Future<void> export(List<String> headers, List<List<Object?>> rows) async {
    try {
      await FilePicker.saveFile(
        fileName: detail ? 'bien-dong-kho.xlsx' : 'nhap-xuat-ton.xlsx',
        bytes: XlsxCatalog().table(headers, rows),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      if (mounted) {
        feedback(
          context,
          e is FormatException ? e.message : 'Không xuất được Excel.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhập xuất tồn theo kỳ')),
    body: FutureBuilder(
      future: report,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Không đọc được lịch sử kho.'));
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final warehouses =
            data.balances.map((row) => row.item.position.$1).toSet().toList()
              ..sort();
        final headers = detail
            ? [
                'Ngày',
                'Chứng từ',
                'Nghiệp vụ',
                'Kho',
                'SKU',
                'Tên hàng',
                'ĐVT',
                'Chất lượng',
                'Thay đổi lượng',
                'Thay đổi giá trị VND',
              ]
            : [
                'Kho',
                'SKU',
                'Tên hàng',
                'ĐVT',
                'Chất lượng',
                'Tồn đầu',
                'Nhập',
                'Xuất',
                'Tồn cuối',
                'Giá trị đầu VND',
                'Giá trị cuối VND',
              ];
        final rows = detail
            ? [
                for (final move in data.movements)
                  if (warehouse == null || warehouse == move.position.$1)
                    [
                      DateFormat('dd/MM/yyyy HH:mm')
                          .format(move.time.toLocal()),
                      move.commandId,
                      operationLabel(move.operation),
                      move.position.$1,
                      move.sku,
                      move.name,
                      move.unit,
                      businessStatus(move.position.$3),
                      reportQuantity(BigInt.from(move.quantity)),
                      move.value,
                    ],
              ]
            : [
                for (final balance in data.balances)
                  if (warehouse == null ||
                      warehouse == balance.item.position.$1)
                    [
                      balance.item.position.$1,
                      balance.item.sku,
                      balance.item.name,
                      balance.item.unit,
                      businessStatus(balance.item.position.$3),
                      reportQuantity(balance.opening),
                      reportQuantity(balance.incoming),
                      reportQuantity(balance.outgoing),
                      reportQuantity(balance.closing),
                      balance.openingValue.toString(),
                      balance.closingValue.toString(),
                    ],
              ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: warehouse,
                    hint: const Text('Tất cả kho'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Tất cả kho'),
                      ),
                      for (final code in warehouses)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (value) => setState(() => warehouse = value),
                  ),
                  FilterChip(
                    label: const Text('Biến động từng chứng từ'),
                    selected: detail,
                    onSelected: (value) => setState(() => detail = value),
                  ),
                  OutlinedButton.icon(
                    onPressed: data.missingHistory > 0 || rows.isEmpty
                        ? null
                        : () => export(headers, rows),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Xuất Excel'),
                  ),
                  if (data.missingHistory > 0)
                    const Text(
                      'Thiếu mốc tồn của một số bản ghi. Đồng bộ và đối chiếu trước khi xuất.',
                    ),
                ],
              ),
            ),
            if (rows.isEmpty)
              const Expanded(
                child: Center(child: Text('Chưa có biến động kho đã đồng bộ.')),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(
                        Color(0xffe7effc),
                      ),
                      columns: [
                        for (final heading in headers)
                          DataColumn(label: Text(heading)),
                      ],
                      rows: [
                        for (final row in rows.take(100))
                          DataRow(
                            cells: [
                              for (var i = 0; i < row.length; i++)
                                DataCell(
                                  Text(
                                    detail && i == 1
                                        ? shortId(row[i] as String)
                                        : '${row[i]}',
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (rows.length > 100)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Hiện 100 / ${rows.length} dòng. Xuất Excel để xem đầy đủ.',
                ),
              ),
          ],
        );
      },
    ),
  );
}
