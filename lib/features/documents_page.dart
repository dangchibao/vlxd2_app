import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import 'business_pages.dart';
import 'business_receipt.dart';
import 'reports_search.dart';

class DocumentsPage extends StatefulWidget {
  final AppRuntime runtime;
  const DocumentsPage({super.key, required this.runtime});
  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  String kind = 'payment';
  static const kinds = {
    'deposit': 'Thu đặt cọc',
    'reservationRefund': 'Hoàn đặt cọc',
    'payment': 'Phiếu thu',
    'supplierPayment': 'Chi NCC',
    'refund': 'Hoàn tiền',
    'purchaseReceipt': 'Nhập kho',
    'transfer': 'Chuyển kho',
    'returnReceipt': 'Nhận hàng trả',
    'inventoryCount': 'Kiểm kê',
    'warranty': 'Bảo hành',
    'expense': 'Chi phí',
    'shiftClose': 'Chốt ca',
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButton<String>(
        value: kind,
        items: [
          for (final e in kinds.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => kind = v!),
      ),
      Expanded(
        child: RecordList(
          key: ValueKey(kind),
          runtime: widget.runtime,
          kind: kind,
          title: 'Chứng từ đã xác nhận',
          item: (context, row, data) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${kinds[kind]} • ${shortId(data['id'] as String? ?? row.id)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  RecordDetails(data: data),
                  TextButton.icon(
                    onPressed: () => openBusinessReceipt(
                      context,
                      widget.runtime,
                      kind,
                      data,
                    ),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Xem / in phiếu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
