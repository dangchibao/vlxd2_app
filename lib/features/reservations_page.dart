import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import 'business_pages.dart';
import 'reports_search.dart';

String reservationStatus(Object? status) => switch (status) {
  'pendingApproval' => 'Vượt tồn • Chờ quản lý duyệt',
  'reserved' => 'Đã giữ đủ hàng',
  'waiting' => 'Đã duyệt chờ nhập',
  'partial' => 'Đã duyệt giao phần có sẵn',
  'converted' => 'Đã chuyển đơn bán',
  'rejected' => 'Đã từ chối',
  'cancelled' => 'Đã hủy',
  _ => '$status',
};

class ReservationsPage extends StatelessWidget {
  final AppRuntime runtime;
  const ReservationsPage({super.key, required this.runtime});
  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'reservation',
    title: 'Giữ hàng / Duyệt vượt tồn',
    item: (context, row, data) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đơn ${shortId(data['id'] as String)} • ${reservationStatus(data['status'])}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final line in data['lines'] as List)
              Text(
                '${line['name']} • Đặt ${qty(line['quantity'] as int)} • Giữ ${qty(line['reserved'] as int)}',
              ),
            Wrap(
              spacing: 8,
              children: [
                if ({'pendingApproval', 'waiting'}.contains(data['status']) &&
                    allowed(runtime, Operation.approveReservation))
                  FilledButton(
                    onPressed: () => commandDialog(
                      context,
                      runtime,
                      title: 'Quyết định đơn thiếu hàng',
                      operation: Operation.approveReservation,
                      entityId: data['id'] as String,
                      version: row.version,
                      fields: const [
                        InputField(
                          'decision',
                          'Quyết định',
                          choices: [
                            ('wait', 'Nhận đơn chờ nhập'),
                            ('partial', 'Giữ và giao phần có sẵn'),
                            ('reject', 'Từ chối'),
                          ],
                        ),
                        InputField('reason', 'Lý do / Phương án xử lý'),
                      ],
                    ),
                    child: const Text('Duyệt đơn'),
                  ),
                if ({
                      'reserved',
                      'waiting',
                      'partial',
                    }.contains(data['status']) &&
                    allowed(runtime, Operation.fulfillReservation))
                  OutlinedButton(
                    onPressed: () => commandDialog(
                      context,
                      runtime,
                      title: 'Nhận đủ hàng và ghi sổ bán',
                      operation: Operation.fulfillReservation,
                      entityId: data['id'] as String,
                      version: row.version,
                      fixed: {'saleId': const Uuid().v4()},
                      fields: const [],
                    ),
                    child: const Text('Ghi sổ toàn bộ'),
                  ),
                if (data['status'] == 'partial' &&
                    allowed(runtime, Operation.fulfillReservation))
                  OutlinedButton(
                    onPressed: () => commandDialog(
                      context,
                      runtime,
                      title: 'Ghi sổ phần đã giữ; lưu phần thiếu để theo dõi',
                      operation: Operation.fulfillReservation,
                      entityId: data['id'] as String,
                      version: row.version,
                      fixed: {'saleId': const Uuid().v4(), 'partial': true},
                      fields: const [],
                    ),
                    child: const Text('Ghi sổ phần có sẵn'),
                  ),
                if ({
                      'reserved',
                      'waiting',
                      'partial',
                      'pendingApproval',
                    }.contains(data['status']) &&
                    allowed(runtime, Operation.cancelReservation))
                  TextButton(
                    onPressed: () => commandDialog(
                      context,
                      runtime,
                      title: 'Hủy đơn và nhả tồn giữ',
                      operation: Operation.cancelReservation,
                      entityId: data['id'] as String,
                      version: row.version,
                      fields: const [InputField('reason', 'Lý do hủy')],
                    ),
                    child: const Text('Hủy giữ hàng'),
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

class TrackingPage extends StatelessWidget {
  final AppRuntime runtime;
  const TrackingPage({super.key, required this.runtime});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Tồn theo lô'),
            Tab(text: 'Serial thiết bị'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              for (final kind in ['lotStock', 'serial'])
                RecordList(
                  runtime: runtime,
                  kind: kind,
                  title: '',
                  item: (context, row, data) => Card(
                    child: ListTile(
                      title: Text(
                        kind == 'serial'
                            ? '${data['serial']} • ${data['productId']}'
                            : 'Lô ${data['lotId']} • ${data['productId']}',
                      ),
                      subtitle: Text(
                        'Kho ${data['warehouse']} • ${data['quality']} ${data['status'] ?? ''}',
                      ),
                      trailing: kind == 'lotStock'
                          ? Text(qty(data['quantity'] as int))
                          : null,
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Truy xuất'),
                          content: SingleChildScrollView(
                            child: RecordDetails(data: data),
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
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
