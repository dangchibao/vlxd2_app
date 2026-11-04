import 'dart:convert';

import '../data/database.dart';

class StoreAlert {
  final String id, title, detail, recordId;
  const StoreAlert(this.id, this.title, this.detail, this.recordId);
}

class StoreAlerts {
  static List<StoreAlert> derive(
    List<BusinessRecord> records,
    List<OutboxData> queue,
    DateTime now,
  ) {
    final byId = {
      for (final row in records)
        row.id: jsonDecode(row.payload) as Map<String, dynamic>,
    };
    final result = <String, StoreAlert>{};
    final available = <String, int>{};
    for (final row in records) {
      final value = byId[row.id]!;
      if (row.kind == 'stock' && value['quality'] == 'good') {
        available.update(
          value['productId'] as String,
          (q) => q + (value['quantity'] as int),
          ifAbsent: () => value['quantity'] as int,
        );
      }
      if (row.kind == 'reservedStock') {
        available.update(
          value['productId'] as String,
          (q) => q - (value['quantity'] as int),
          ifAbsent: () => -(value['quantity'] as int),
        );
      }
    }
    void add(String id, String title, String detail, String record) =>
        result[id] = StoreAlert(id, title, detail, record);
    for (final row in records) {
      final data = byId[row.id]!;
      final due = DateTime.tryParse(
        '${data[row.kind == 'purchase'
                ? 'expectedAt'
                : row.kind == 'sale'
                ? 'dueAt'
                : 'scheduledAt'] ?? ''}',
      );
      if (row.kind == 'catalog' && data['active'] != false) {
        final minimum = data['minimumStock'] as int? ?? 0;
        if ((available[data['id']] ?? 0) < minimum) {
          add(
            'stock:${row.id}',
            'Tồn thấp • ${data['name']}',
            'Tồn khả dụng thấp hơn mức tối thiểu.',
            row.id,
          );
        }
      }
      if (due != null && due.isBefore(now)) {
        if (row.kind == 'sale' && (data['debt'] as int? ?? 0) > 0) {
          add(
            'debt:${row.id}',
            'Công nợ quá hạn',
            'Đơn ${data['id']} còn ${data['debt']} VND.',
            row.id,
          );
        }
        if (row.kind == 'purchase' && data['status'] != 'received') {
          add(
            'purchase:${row.id}',
            'Đơn mua nhận trễ',
            'Đơn ${data['id']} chưa nhận đủ.',
            row.id,
          );
        }
        if (row.kind == 'delivery' && data['status'] != 'delivered') {
          add(
            'delivery:${row.id}',
            'Đơn giao trễ',
            'Đơn ${data['id']} còn phải giao.',
            row.id,
          );
        }
      }
      if (row.kind == 'reservation' && data['status'] == 'pendingApproval') {
        add(
          'approval:${row.id}',
          'Vượt tồn chờ duyệt',
          'Quản lý cần quyết định phương án nhận đơn.',
          row.id,
        );
      }
      if (row.kind == 'warranty' &&
          !{'completed', 'rejected'}.contains(data['status'])) {
        add(
          'warranty:${row.id}',
          'Bảo hành đang xử lý',
          'Phiếu ${data['id']} • ${data['status']}',
          row.id,
        );
      }
    }
    for (final row in queue.where(
      (r) => {'error', 'conflict'}.contains(r.status),
    )) {
      add(
        'sync:${row.id}',
        'Đồng bộ cần xử lý',
        '${row.operation ?? 'Nháp cũ'} • ${row.lastError ?? row.status}',
        row.aggregateId,
      );
    }
    return result.values.toList();
  }
}
