import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import 'business_pages.dart';

Future<void> showShiftClose(BuildContext context, AppRuntime runtime) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShiftCloseDialog(runtime: runtime),
    );

class ShiftCloseDialog extends StatefulWidget {
  final AppRuntime runtime;
  const ShiftCloseDialog({super.key, required this.runtime});
  @override
  State<ShiftCloseDialog> createState() => _ShiftCloseDialogState();
}

class _ShiftCloseDialogState extends State<ShiftCloseDialog> {
  late final shift = TextEditingController(text: currentShift(widget.runtime));
  final opening = TextEditingController(text: '0');
  final counted = TextEditingController(text: '0');
  final explanation = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final field in [shift, opening, counted]) {
      field.addListener(update);
    }
  }

  void update() => setState(() {});
  @override
  void dispose() {
    for (final field in [shift, opening, counted, explanation]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await widget.runtime.enqueue(Operation.shiftClose, const Uuid().v4(), {
        'shiftId': shift.text.trim(),
        'opening': int.parse(opening.text),
        'counted': int.parse(counted.text),
        'explanation': explanation.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is BusinessException
              ? e.message
              : 'Nhập số tiền nguyên VND hợp lệ.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.runtime.db;
    final query = db.select(db.businessRecords)
      ..where((r) => r.id.equals('shiftTotals:${shift.text.trim()}'));
    return AlertDialog(
      title: const Text('Chốt ca'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: shift,
                decoration: const InputDecoration(labelText: 'Mã ca'),
              ),
              TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiền đầu ca (VND)',
                ),
              ),
              TextField(
                controller: counted,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiền thực đếm (VND)',
                ),
              ),
              StreamBuilder(
                stream: query.watchSingleOrNull(),
                builder: (context, snapshot) {
                  final data = snapshot.data == null
                      ? <String, dynamic>{}
                      : recordData(snapshot.data!);
                  final initial = int.tryParse(opening.text),
                      actual = int.tryParse(counted.text);
                  if (snapshot.hasError) {
                    return const Text('Không đọc được số liệu ca.');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (initial == null ||
                      actual == null ||
                      initial < 0 ||
                      actual < 0) {
                    return const Text(
                      'Số tiền phải là số nguyên VND không âm.',
                    );
                  }
                  final expected = initial + (data['cashNet'] as int? ?? 0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tiền mặt dự kiến: ${vnd(expected)}'),
                        Text(
                          'Chênh lệch: ${vnd(actual - expected)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: actual == expected
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        Text(
                          'Chuyển khoản đối soát riêng: ${vnd(data['bankNet'] as int? ?? 0)}',
                        ),
                        const Text(
                          'Tạm tính từ dữ liệu đã xác nhận trên thiết bị. Trạm sẽ kiểm tra lại khi đồng bộ.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
              TextField(
                controller: explanation,
                decoration: const InputDecoration(
                  labelText: 'Giải trình nếu lệch tiền',
                ),
                maxLines: 2,
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: const Text('Lưu chốt tạm / Chờ xác nhận'),
        ),
      ],
    );
  }
}
