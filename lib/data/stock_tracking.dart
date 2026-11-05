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

  Future<void> receive(
    String warehouse,
    Map<String, dynamic> line,
    String supplier,
    String purchase,
  ) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1),
        quality = line['quality'] as String? ?? 'good';
    final tracking = await mode(product);
    if (tracking == 'none') return;
    final lot = tracking == 'lot' ? textField(line, 'lotId') : '';
    if (tracking == 'lot') {
      final lotKey = jsonEncode([product, lot]);
      final previous = await read('lot', lotKey);
      final color = line['colorCode'] as String? ?? '';
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
        'supplierId': supplier,
        'purchaseId': purchase,
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await _position(warehouse, product, lot, quality, quantity);
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
  }

  Future<void> issue(
    String warehouse,
    Map<String, dynamic> line,
    String saleId,
  ) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1);
    final tracking = await mode(product);
    if (tracking == 'lot') {
      final lot = textField(line, 'lotId');
      final info = await read('lot', jsonEncode([product, lot]));
      if (line['colorCode'] != null && line['colorCode'] != info['colorCode']) {
        throw const BusinessException('lot', 'Mã màu không khớp với lô hàng.');
      }
      await _position(warehouse, product, lot, 'good', -quantity);
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
      final lot = textField(line, 'lotId');
      await _position(from, product, lot, fromQuality, -quantity);
      await _position(to, product, lot, toQuality, quantity);
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

  Future<void> returnGoods(
    String warehouse,
    Map<String, dynamic> line,
    Map<String, dynamic> original,
    String saleId,
  ) async {
    final product = textField(line, 'productId'),
        quantity = integerField(line, 'quantity', min: 1);
    final tracking = await mode(product);
    if (tracking == 'lot') {
      await _position(
        warehouse,
        product,
        textField(original, 'lotId'),
        'quarantine',
        quantity,
      );
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
      await _position(
        warehouse,
        product,
        textField(line, 'lotId'),
        quality,
        -quantity,
      );
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
