import 'dart:convert';

import '../domain/operations.dart';

typedef TrackingRead = Future<Map<String, dynamic>> Function(
  String kind,
  String id,
);
typedef TrackingWrite = Future<void> Function(
  String kind,
  String id,
  Map<String, dynamic> data,
);

/// Runs inside the same authority transaction as aggregate stock and costing.
/// Lots hold quantities; valuation stays weighted-average by product/warehouse.
class StockTracking {
  final TrackingRead read;
  final TrackingWrite write;
  StockTracking(this.read, this.write);

  Future<String> mode(String product) async =>
      (await read('catalog', product))['tracking'] as String? ?? 'none';
  String positionId(
    String warehouse,
    String product,
    String lot,
    String quality,
  ) => jsonEncode([warehouse, product, lot, quality]);
  // Legacy lines use lotId; a split line carries explicit quantities.
  static List<Map<String, dynamic>> lots(Map<String, dynamic> line, int total) {
    final raw =
        line['lotAllocations'] ??
        [
          {
            'lotId': line['lotId'],
            'quantity': total,
            'colorCode': line['colorCode'],
          },
        ];
    if (raw is! List || raw.isEmpty || raw.length > 10) {
      throw const BusinessException('lot', 'Chọn từ 1 đến 10 lô mỗi dòng.');
    }
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    var sum = 0;
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const BusinessException('lot', 'Phân bổ lô không hợp lệ.');
      }
      final lot = item['lotId'], color = item['colorCode'];
      if (lot is! String ||
          lot.trim().isEmpty ||
          lot.trim().length > 80 ||
          !seen.add(lot.trim()) ||
          (color != null && (color is! String || color.trim().length > 80))) {
        throw const BusinessException(
          'lot',
          'Mã lô hoặc mã màu không hợp lệ, hoặc lô bị trùng.',
        );
      }
      final q = integerField(item, 'quantity', min: 1, max: 1000000000);
      sum += q;
      result.add({
        'lotId': lot.trim(),
        'quantity': q,
        if (color is String) 'colorCode': color.trim(),
      });
    }
    if (sum != total) {
      throw const BusinessException(
        'lot',
        'Tổng số lượng các lô phải bằng số lượng dòng hàng.',
      );
    }
    return result;
  }

  List<String> serials(Map<String, dynamic> line, int quantity) {
    final raw = line['serials'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > 200 ||
        quantity != raw.length * 1000) {
      throw const BusinessException(
        'serial',
        'Mỗi đơn vị cần một serial; tối đa 200 serial một lần.',
      );
    }
    final values = <String>[];
    for (final value in raw) {
      if (value is! String || value.trim().isEmpty || value.length > 100) {
        throw const BusinessException('serial', 'Serial không hợp lệ.');
      }
      values.add(value.trim().toUpperCase());
    }
    if (values.toSet().length != values.length) {
      throw const BusinessException('serial', 'Serial bị lặp trong chứng từ.');
    }
    return values;
  }

  Future<void> _position(
    String warehouse,
    String product,
    String lot,
    String quality,
    int delta,
  ) async {
    final id = positionId(warehouse, product, lot, quality);
    final old = await read('lotStock', id);
    final quantity = (old['quantity'] as int? ?? 0) + delta;
    if (quantity < 0) {
      throw const BusinessException(
        'lot',
        'Không đủ tồn của lô và trạng thái đã chọn.',
      );
    }
    await write('lotStock', id, {
      'warehouse': warehouse,
      'productId': product,
      'lotId': lot,
      'quality': quality,
      'quantity': quantity,
    });
  }

  Future<List<Map<String, dynamic>>?> receive(
    String warehouse,
    Map<String, dynamic> line,
    String supplier,
    String purchase,
  ) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1),
        quality = line['quality'] as String? ?? 'good';
    final tracking = await mode(product);
    if (tracking == 'none') return null;
    if (tracking == 'lot') {
      final allocations = lots(line, quantity);
      for (final allocation in allocations) {
        final lot = allocation['lotId'] as String;
        final lotKey = jsonEncode([product, lot]);
        final previous = await read('lot', lotKey);
        final color =
            allocation['colorCode'] as String? ??
            previous['colorCode'] as String? ??
            '';
        if (previous.isNotEmpty && previous['colorCode'] != color) {
          throw const BusinessException(
            'lot',
            'Mã màu khác thông tin lô đã nhập.',
          );
        }
        await write('lot', lotKey, {
          ...previous,
          'productId': product,
          'lotId': lot,
          'colorCode': color,
          'supplierId': previous['supplierId'] ?? supplier,
          'purchaseId': previous['purchaseId'] ?? purchase,
          'receivedAt':
              previous['receivedAt'] ??
              DateTime.now().toUtc().toIso8601String(),
        });
        allocation['colorCode'] = color;
        await _position(
          warehouse,
          product,
          lot,
          quality,
          allocation['quantity'] as int,
        );
      }
      return allocations;
    } else {
      for (final serial in serials(line, quantity)) {
        if ((await read('serial', serial)).isNotEmpty) {
          throw const BusinessException(
            'serial',
            'Serial đã được nhập trước đó.',
          );
        }
        await write('serial', serial, {
          'serial': serial,
          'productId': product,
          'warehouse': warehouse,
          'quality': quality,
          'status': 'available',
          'supplierId': supplier,
          'purchaseId': purchase,
        });
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> issue(
    String warehouse,
    Map<String, dynamic> line,
    String saleId, {
    required bool allowMixedColors,
  }) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1);
    final tracking = await mode(product);
    if (tracking == 'lot') {
      final allocations = lots(line, quantity);
      final colors = <String>{};
      for (final allocation in allocations) {
        final lot = allocation['lotId'] as String;
        final info = await read('lot', jsonEncode([product, lot]));
        final color = info['colorCode'] as String? ?? '';
        if (allocation['colorCode'] != null &&
            allocation['colorCode'] != color) {
          throw const BusinessException(
            'lot',
            'Mã màu không khớp với lô hàng.',
          );
        }
        allocation['colorCode'] = color;
        colors.add(color);
        await _position(
          warehouse,
          product,
          lot,
          'good',
          -(allocation['quantity'] as int),
        );
      }
      if (colors.length > 1 && !allowMixedColors) {
        throw const BusinessException(
          'lot',
          'Các lô khác mã màu. Chọn lại lô hoặc xác nhận khách đồng ý trộn màu.',
        );
      }
      return allocations;
    } else if (tracking == 'serial') {
      for (final serial in serials(line, quantity)) {
        final old = await read('serial', serial);
        if (old['productId'] != product ||
            old['warehouse'] != warehouse ||
            old['quality'] != 'good' ||
            old['status'] != 'available') {
          throw const BusinessException(
            'serial',
            'Serial không sẵn sàng để bán tại kho này.',
          );
        }
        await write('serial', serial, {
          ...old,
          'status': 'sold',
          'saleId': saleId,
        });
      }
    }
    return null;
  }

  Future<void> move(
    String from,
    String to,
    Map<String, dynamic> line, {
    String fromQuality = 'good',
    String toQuality = 'good',
  }) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1);
    final tracking = await mode(product);
    if (tracking == 'lot') {
      for (final allocation in lots(line, quantity)) {
        final lot = allocation['lotId'] as String,
            q = allocation['quantity'] as int;
        await _position(from, product, lot, fromQuality, -q);
        await _position(to, product, lot, toQuality, q);
      }
    } else if (tracking == 'serial') {
      for (final serial in serials(line, quantity)) {
        final old = await read('serial', serial);
        if (old['productId'] != product ||
            old['warehouse'] != from ||
            old['quality'] != fromQuality ||
            old['status'] != 'available') {
          throw const BusinessException(
            'serial',
            'Serial không thuộc tồn cần chuyển.',
          );
        }
        await write('serial', serial, {
          ...old,
          'warehouse': to,
          'quality': toQuality,
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>?> returnGoods(
    String warehouse,
    Map<String, dynamic> line,
    Map<String, dynamic> original,
    String saleId,
  ) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1);
    final tracking = await mode(product);
    if (tracking == 'lot') {
      final issued = lots(original, original['quantity'] as int);
      final previously = <String, int>{
        for (final item in original['returnedByLot'] as List? ?? [])
          item['lotId'] as String: item['quantity'] as int,
      };
      final requested =
          issued.length == 1 &&
              line['lotAllocations'] == null &&
              (line['lotId'] ?? '') == ''
          ? [
              {...issued.single, 'quantity': quantity},
            ]
          : lots(line, quantity);
      for (final allocation in requested) {
        final lot = allocation['lotId'] as String,
            q = allocation['quantity'] as int;
        final source = issued.where((item) => item['lotId'] == lot).firstOrNull;
        final prior = issued.length == 1
            ? original['returned'] as int? ?? 0
            : previously[lot] ?? 0;
        if (source == null || prior + q > (source['quantity'] as int)) {
          throw const BusinessException(
            'lot',
            'Lô không thuộc đơn hoặc số trả vượt số còn lại của lô.',
          );
        }
        if (issued.length > 1) previously[lot] = prior + q;
        allocation['colorCode'] = source['colorCode'] ?? '';
        await _position(warehouse, product, lot, 'quarantine', q);
      }
      if (issued.length > 1) {
        original['returnedByLot'] = [
          for (final entry in previously.entries)
            {'lotId': entry.key, 'quantity': entry.value},
        ];
      }
      return requested;
    } else if (tracking == 'serial') {
      final sold = (original['serials'] as List)
          .map((s) => (s as String).trim().toUpperCase())
          .toSet();
      for (final serial in serials(line, quantity)) {
        final old = await read('serial', serial);
        if (!sold.contains(serial) ||
            old['saleId'] != saleId ||
            old['productId'] != product ||
            old['status'] != 'sold') {
          throw const BusinessException(
            'serial',
            'Serial không thuộc đơn hoặc đã trả trước đó.',
          );
        }
        await write('serial', serial, {
          ...old,
          'status': 'available',
          'warehouse': warehouse,
          'quality': 'quarantine',
          'returnedFromSale': saleId,
        });
      }
    }
    return null;
  }

  Future<void> adjust(
    String warehouse,
    Map<String, dynamic> line,
    int delta,
    String countId,
    String quality,
  ) async {
    if (delta == 0) return;
    final product = textField(line, 'productId'),
        tracking = await mode(product);
    if (tracking == 'none') return;
    final movement = {...line, 'quantity': delta.abs(), 'quality': quality};
    if (delta > 0) {
      if (tracking == 'lot') {
        final lot = await read(
          'lot',
          jsonEncode([product, textField(line, 'lotId')]),
        );
        movement['colorCode'] = lot['colorCode'] ?? line['colorCode'] ?? '';
      }
      await receive(warehouse, movement, 'inventory-adjustment', countId);
    } else {
      await remove(
        warehouse,
        line,
        -delta,
        quality,
        status: 'adjustedOut',
        referenceKey: 'inventoryCountId',
        referenceId: countId,
      );
    }
  }

  Future<void> remove(
    String warehouse,
    Map<String, dynamic> line,
    int quantity,
    String quality, {
    required String status,
    required String referenceKey,
    required String referenceId,
  }) async {
    final product = textField(line, 'productId');
    final tracking = await mode(product);
    if (tracking == 'lot') {
      for (final allocation in lots(line, quantity)) {
        await _position(
          warehouse,
          product,
          allocation['lotId'] as String,
          quality,
          -(allocation['quantity'] as int),
        );
      }
    } else if (tracking == 'serial') {
      for (final serial in serials(line, quantity)) {
        final old = await read('serial', serial);
        if (old['productId'] != product ||
            old['warehouse'] != warehouse ||
            old['quality'] != quality ||
            old['status'] != 'available') {
          throw const BusinessException(
            'serial',
            'Serial không thuộc tồn cần xuất.',
          );
        }
        await write('serial', serial, {
          ...old,
          'status': status,
          referenceKey: referenceId,
        });
      }
    }
  }
}
