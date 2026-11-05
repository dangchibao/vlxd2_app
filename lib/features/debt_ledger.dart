import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../domain/operations.dart';
import 'business_pages.dart';
import 'material_calculator.dart';

class DebtLedger extends StatefulWidget {
  final AppRuntime runtime;
  final BusinessRecord balanceRow;
  final bool customer;
  const DebtLedger({
    super.key,
    required this.runtime,
    required this.balanceRow,
    required this.customer,
  });

  @override
  State<DebtLedger> createState() => _DebtLedgerState();
}

class _DebtLedgerState extends State<DebtLedger> {
  late final balance = recordData(widget.balanceRow)['balance'] as int;
  late final partyId = widget.balanceRow.id.substring(
    widget.balanceRow.kind.length + 1,
  );
  late final shift = TextEditingController(text: currentShift(widget.runtime));
  late final ledger = loadLedger();
  final amounts = <String, String>{};
  String method = 'cash';
  String error = '';
  bool busy = false;

  Operation get operation =>
      widget.customer ? Operation.debtCollection : Operation.supplierPayment;

  Future<
    ({
      String name,
      List<BusinessRecord> documents,
      List<Map<String, dynamic>> history,
    })
  >
  loadLedger() async {
    final db = widget.runtime.db;
    final documentKind = widget.customer ? 'sale' : 'purchaseReceipt';
    final paymentKind = widget.customer ? 'payment' : 'supplierPayment';
    final partyKey = widget.customer ? 'customerId' : 'supplierId';
    final rows = await (db.select(
      db.businessRecords,
    )..where((r) => r.kind.isIn([documentKind, paymentKind, 'party']))).get();
    final documents = <BusinessRecord>[];
    final history = <Map<String, dynamic>>[];
    var name = partyId;
    for (final row in rows) {
      final data = recordData(row);
      if (row.kind == 'party' && data['id'] == partyId) {
        name = data['name'] as String? ?? partyId;
      } else if (data[partyKey] == partyId) {
        if (row.kind == documentKind && remaining(data) > 0) documents.add(row);
        if (row.kind == paymentKind) history.add(data);
      }
    }
    documents.sort(
      (a, b) => date(recordData(a)).compareTo(date(recordData(b))),
    );
    history.sort((a, b) => date(b).compareTo(date(a)));
    return (name: name, documents: documents, history: history);
  }

  int remaining(Map<String, dynamic> data) => widget.customer
      ? data['debt'] as int
      : (data['total'] as int) - (data['paid'] as int? ?? 0);

  String date(Map<String, dynamic> data) =>
      (data['createdAt'] ?? data['receivedAt'] ?? '').toString();
  String day(Map<String, dynamic> data) => date(data).split('T').first;

  Future<void> submit(List<BusinessRecord> documents) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final allocations = <Map<String, dynamic>>[];
      var total = 0;
      for (final row in documents) {
        final value = amounts[row.id]?.trim() ?? '';
        if (value.isEmpty) continue;
        final amount = parseFixed(value, 0);
        if (amount == 0) continue;
        final data = recordData(row);
        if (amount > remaining(data)) {
          throw const FormatException(
            'Số tiền vượt phần còn lại của chứng từ.',
          );
        }
        total += amount;
        allocations.add({
          'documentId': data['id'],
          'amount': amount,
          'version': row.version,
        });
      }
      if (allocations.isEmpty ||
          allocations.length > 20 ||
          total > balance ||
          shift.text.trim().isEmpty) {
        throw const FormatException(
          'Chọn 1 đến 20 chứng từ, nhập ca và phân bổ trong số dư đã xác nhận.',
        );
      }
      await widget.runtime.enqueue(operation, partyId, {
        'amount': total,
        'method': method,
        'shiftId': shift.text.trim(),
        'allocations': allocations,
      }, expectedVersion: widget.balanceRow.version);
      if (mounted) {
        feedback(context, 'Đã lưu thanh toán chờ trạm xác nhận.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = switch (e) {
            FormatException() => e.message,
            BusinessException() => e.message,
            _ => 'Không lưu được phân bổ.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đối chiếu công nợ')),
    body: FutureBuilder(
      future: ledger,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Không đọc được sổ công nợ.'));
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final mayPost = balance > 0 && allowed(widget.runtime, operation);
        final sum = data.documents.fold(
          0,
          (total, row) => total + remaining(recordData(row)),
        );
        final history = data.history;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 2 + data.documents.length + history.length,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('Số dư đã xác nhận ${vnd(balance)}'),
                  if (!widget.customer && sum > balance)
                    Text(
                      'Chênh lệch ${vnd(sum - balance)} do khoản trả cũ chưa gắn phiếu. Số dư nhà cung cấp là giới hạn thanh toán.',
                    ),
                  const SizedBox(height: 12),
                  const Text('Chứng từ còn số tiền để phân bổ'),
                  if (data.documents.isEmpty)
                    const Text('Chưa có chứng từ phù hợp.'),
                ],
              );
            }
            if (index <= data.documents.length) {
              final row = data.documents[index - 1], record = recordData(row);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shortId(record['id'] as String)} • ${day(record)} • ${vnd(remaining(record))}',
                      ),
                      if (mayPost)
                        TextFormField(
                          key: ValueKey(row.id),
                          enabled: !busy,
                          initialValue: amounts[row.id],
                          onChanged: (value) =>
                              setState(() => amounts[row.id] = value),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Số tiền phân bổ (VND)',
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }
            if (index == 1 + data.documents.length) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mayPost && data.documents.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: 'Phương thức',
                      ),
                      items: [
                        for (final (key, label) in methods)
                          DropdownMenuItem(value: key, child: Text(label)),
                      ],
                      onChanged: busy ? null : (value) => method = value!,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: shift,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: 'Ca'),
                    ),
                    Text(
                      'Tổng phân bổ ${vnd(amounts.values.fold<int>(0, (total, value) => total + (int.tryParse(value.trim()) ?? 0)))}',
                    ),
                    if (error.isNotEmpty)
                      Text(error, style: const TextStyle(color: Colors.red)),
                    FilledButton(
                      onPressed: busy ? null : () => submit(data.documents),
                      child: Text(
                        widget.customer ? 'Lập phiếu thu' : 'Lập phiếu chi NCC',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Lịch sử thanh toán đã ghi sổ'),
                  if (history.isEmpty) const Text('Chưa có phiếu thanh toán.'),
                ],
              );
            }
            final entry = history[index - 2 - data.documents.length];
            final allocations = entry['allocations'] as List? ?? [];
            return ExpansionTile(
              title: Text('${day(entry)} • ${vnd(entry['amount'] as int)}'),
              subtitle: Text(
                entry['method'] == 'cash' ? 'Tiền mặt' : 'Chuyển khoản',
              ),
              children: [
                if (allocations.isEmpty)
                  ListTile(
                    title: Text(
                      entry['saleId'] is String
                          ? 'Đơn ${shortId(entry['saleId'] as String)}'
                          : 'Thanh toán theo số dư',
                    ),
                  ),
                for (final line in allocations)
                  ListTile(
                    title: Text(
                      '${shortId(line['documentId'] as String)} • ${vnd(line['amount'] as int)}',
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
