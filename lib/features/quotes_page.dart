import 'dart:convert';

import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../domain/operations.dart';
import 'business_pages.dart';
import 'reports_search.dart';
import 'business_receipt.dart';

class QuotesPage extends StatelessWidget {
  final AppRuntime runtime;
  const QuotesPage({super.key, required this.runtime});
  void edit(
    BuildContext context, {
    BusinessRecord? row,
    Map<String, dynamic>? data,
  }) {
    Draft? draft;
    if (data != null && row != null) {
      draft = Draft(
        id: const Uuid().v4(),
        payload: jsonEncode({
          'kind': 'quote',
          'targetId': data['id'],
          'expectedVersion': row.version,
          'warehouse': 'main',
          'discount': '${data['discount']}',
          'surcharge': '${data['surcharge'] ?? 0}',
          'dueDate': data['dueAt'] ?? '',
          'party': data['customerId'],
          'items': [
            for (final line in data['lines'] as List)
              {
                'productId': line['productId'],
                'quantity': qty(
                  (line['saleQuantity'] ?? line['quantity']) as int,
                ),
                'saleUnit': line['saleUnit'] ?? line['unit'],
                'cost': '0',
                'trackingInput':
                    line['lotId'] ??
                    (line['serials'] as List? ?? []).join(', '),
              },
          ],
        }),
        status: 'draft',
        version: 0,
        updatedAt: DateTime.now(),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            OrderComposer(runtime: runtime, quote: true, draft: draft),
      ),
    );
  }

  Future<void> history(BuildContext context, Map<String, dynamic> data) async {
    final rows = await (runtime.db.select(
      runtime.db.businessRecords,
    )..where((r) => r.id.like('quoteVersion:${data['id']}:%'))).get();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lịch sử phiên bản báo giá'),
        content: SizedBox(
          width: 560,
          height: 440,
          child: ListView(
            children: [
              for (final row in rows)
                ExpansionTile(
                  title: Text(
                    'Phiên bản ${recordData(row)['quoteVersion']} • ${vnd(recordData(row)['total'] as int)}',
                  ),
                  children: [RecordDetails(data: recordData(row))],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'quote',
    title: 'Báo giá',
    actions: [
      if (allowed(runtime, Operation.quote))
        FilledButton.icon(
          onPressed: () => edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Tạo báo giá'),
        ),
    ],
    item: (context, row, data) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Báo giá ${shortId(data['id'] as String)} • Phiên bản ${row.version}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${vnd(data['total'] as int)} • ${data['status'] == 'converted' ? 'Đã chuyển đơn' : 'Đang hiệu lực'}',
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      openBusinessReceipt(context, runtime, 'quote', data),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Xem / in báo giá'),
                ),
                TextButton(
                  onPressed: () => history(context, data),
                  child: const Text('Lịch sử'),
                ),
                if (data['status'] == 'active' &&
                    allowed(runtime, Operation.quote))
                  TextButton(
                    onPressed: () => edit(context, row: row, data: data),
                    child: const Text('Tạo phiên bản sửa'),
                  ),
                if (data['status'] == 'active' &&
                    allowed(runtime, Operation.quoteToSale))
                  FilledButton(
                    onPressed: () => commandDialog(
                      context,
                      runtime,
                      title: 'Chuyển báo giá thành đơn bán',
                      operation: Operation.quoteToSale,
                      entityId: data['id'] as String,
                      version: row.version,
                      fixed: {'saleId': const Uuid().v4()},
                      fields: const [
                        InputField('warehouse', 'Kho xuất', initial: 'main'),
                      ],
                    ),
                    child: const Text('Chuyển thành đơn'),
                  ),
              ],
            ),
            RecordDetails(data: data),
          ],
        ),
      ),
    ),
  );
}
