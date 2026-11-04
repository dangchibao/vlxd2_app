import 'dart:convert';

import '../domain/operations.dart';
import 'database.dart';
import 'authority_store.dart';

/// Transaction processor for the trusted station. Authentication/transport must
/// verify Actor independently; this class is not a replacement for cloud Rules.
/// It is not wired to the unauthenticated development UI.
class AuthorityEngine {
  final AuthorityStore store;
  AuthorityEngine(AppDatabase db) : store = DriftAuthorityStore(db);
  AuthorityEngine.withStore(this.store);

  Future<Map<String, dynamic>> execute(
    BusinessCommand command,
    Actor verifiedActor,
  ) => executeAuthenticated(command, () async => verifiedActor);

  Future<Map<String, dynamic>> executeAuthenticated(
    BusinessCommand command,
    Future<Actor> Function() authenticate,
  ) => store.transaction(() async {
    final verifiedActor = await authenticate();
    verifiedActor.require(command.operation);
    final fingerprint = command.fingerprint(verifiedActor.uid);
    final existing = await store.receipt(command.id);
    if (existing != null) {
      if (existing.fingerprint != fingerprint) {
        throw const BusinessException(
          'idempotency',
          'Mã giao dịch đã dùng với nội dung khác.',
        );
      }
      return jsonDecode(existing.result) as Map<String, dynamic>;
    }
    final payload =
        jsonDecode(canonicalJson(command.payload)) as Map<String, dynamic>;
    final kind = switch (command.operation) {
      Operation.receive => 'purchase',
      Operation.payment ||
      Operation.delivery ||
      Operation.returnSale ||
      Operation.refund => 'sale',
      Operation.supplierPayment => 'payable',
      Operation.warrantyUpdate => 'warranty',
      _ => command.operation.name,
    };
    final record = await _record(kind, command.entityId);
    if ((record?.version ?? 0) != command.expectedVersion) {
      throw const BusinessException(
        'conflict',
        'Chứng từ đã thay đổi. Hãy tải phiên bản mới.',
      );
    }
    final previous = record == null
        ? <String, dynamic>{}
        : jsonDecode(record.payload) as Map<String, dynamic>;
    final result = await _apply(
      command.operation,
      command.entityId,
      payload,
      previous,
      verifiedActor,
    );
    final version = (record?.version ?? 0) + 1;
    result['version'] = version;
    result['id'] = command.entityId;
    await _write(kind, command.entityId, result, version: version);
    await store.saveReceipt(command.id, fingerprint, result);
    await store.appendEvent(command, verifiedActor, {
      'entityId': command.entityId,
      'input': payload,
      'result': result,
    });
    return result;
  });

  Future<BusinessRecord?> _record(String kind, String id) =>
      store.record(kind, id);
  Future<Map<String, dynamic>> read(String kind, String id) async {
    final row = await _record(kind, id);
    return row == null ? {} : jsonDecode(row.payload) as Map<String, dynamic>;
  }

  Future<void> _write(
    String kind,
    String id,
    Map<String, dynamic> value, {
    int? version,
  }) async {
    final old = await _record(kind, id);
    final nextVersion = version ?? (old?.version ?? 0) + 1;
    await store.writeRecord(
      BusinessRecord(
        id: '$kind:$id',
        kind: kind,
        payload: jsonEncode({...value, 'version': nextVersion}),
        version: nextVersion,
      ),
    );
  }

  void _fresh(Map<String, dynamic> previous) {
    if (previous.isNotEmpty) {
      throw const BusinessException(
        'locked',
        'Chứng từ đã ghi sổ, không được ghi đè.',
      );
    }
  }

  List<Map<String, dynamic>> _lines(Map<String, dynamic> payload) {
    final raw = payload['lines'];
    if (raw is! List || raw.isEmpty || raw.length > 100) {
      throw const BusinessException(
        'validation',
        'Chứng từ cần từ 1 đến 100 dòng hàng.',
      );
    }
    final result = raw.map((l) {
      if (l is! Map<String, dynamic>) {
        throw const BusinessException('validation', 'Dòng hàng không hợp lệ.');
      }
      return l;
    }).toList();
    final keys = <String>{};
    for (final line in result) {
      final id = textField(line, 'productId');
      if (!keys.add(id)) {
        throw const BusinessException(
          'validation',
          'Sản phẩm bị lặp; hãy gộp số lượng.',
        );
      }
      integerField(line, 'quantity', min: 1, max: 1000000000);
    }
    return result;
  }

  String _stockId(String warehouse, String product, String quality) =>
      jsonEncode([warehouse, product, quality]);
  Future<Map<String, dynamic>> stock(
    String warehouse,
    String product, {
    String quality = 'good',
  }) => read('stock', _stockId(warehouse, product, quality));
  Future<void> _stockChange(
    String warehouse,
    String product,
    int quantity,
    int value, {
    String quality = 'good',
  }) async {
    final id = _stockId(warehouse, product, quality);
    final current = await read('stock', id);
    final nextQuantity = (current['quantity'] as int? ?? 0) + quantity;
    final nextValue = (current['value'] as int? ?? 0) + value;
    if (nextQuantity < 0 ||
        nextValue < 0 ||
        nextValue > 9000000000000 ||
        (nextQuantity == 0 && nextValue != 0)) {
      throw const BusinessException(
        'stock',
        'Không đủ tồn hợp lệ hoặc giá trị tồn không cân đối.',
      );
    }
    await _write('stock', id, {
      'warehouse': warehouse,
      'productId': product,
      'quality': quality,
      'quantity': nextQuantity,
      'value': nextValue,
    });
  }

  Future<int> _issue(String warehouse, String product, int quantity) async {
    final current = await stock(warehouse, product);
    final available = current['quantity'] as int? ?? 0;
    if (quantity > available) {
      throw const BusinessException(
        'oversell',
        'Vượt tồn bán được. Cần quản lý duyệt đơn chờ nhập hoặc giao phần có sẵn.',
      );
    }
    final value = roundedRatio(current['value'] as int, quantity, available);
    await _stockChange(warehouse, product, -quantity, -value);
    return value;
  }

  Future<Map<String, dynamic>> _apply(
    Operation op,
    String id,
    Map<String, dynamic> p,
    Map<String, dynamic> old,
    Actor actor,
  ) async {
    switch (op) {
      case Operation.transfer:
        _fresh(old);
        final from = textField(p, 'fromWarehouse'),
            to = textField(p, 'toWarehouse');
        if (from == to) {
          throw const BusinessException(
            'validation',
            'Kho nguồn và đích phải khác nhau.',
          );
        }
        final lines = _lines(p);
        for (final line in lines) {
          final product = textField(line, 'productId'),
              quantity = integerField(line, 'quantity', min: 1);
          final value = await _issue(from, product, quantity);
          await _stockChange(to, product, quantity, value);
        }
        return {...p, 'status': 'posted'};
      case Operation.supplierPayment:
        if (old.isEmpty) {
          throw const BusinessException(
            'missing',
            'Không tìm thấy công nợ nhà cung cấp.',
          );
        }
        await _openShift(p);
        final amount = integerField(p, 'amount', min: 1);
        if (!{'cash', 'bank'}.contains(p['method']) ||
            amount > (old['balance'] as int)) {
          throw const BusinessException(
            'validation',
            'Phương thức hoặc số tiền chi trả không hợp lệ.',
          );
        }
        return {...old, 'balance': (old['balance'] as int) - amount};
      case Operation.returnSale:
        if (old.isEmpty) {
          throw const BusinessException('missing', 'Không tìm thấy đơn gốc.');
        }
        textField(p, 'reason');
        final lines = (old['lines'] as List)
            .map((l) => Map<String, dynamic>.from(l as Map))
            .toList();
        var credit = 0, restoredCost = 0;
        for (final returned in _lines(p)) {
          final matches = lines.where(
            (l) => l['productId'] == returned['productId'],
          );
          if (matches.isEmpty) {
            throw const BusinessException(
              'validation',
              'Hàng trả không thuộc đơn gốc.',
            );
          }
          final target = matches.single;
          final previous = target['returned'] as int? ?? 0,
              quantity = integerField(returned, 'quantity', min: 1);
          final original = target['quantity'] as int;
          if (previous + quantity > original) {
            throw const BusinessException(
              'excess',
              'Trả vượt số lượng đã bán.',
            );
          }
          final net = target['netTotal'] as int? ?? target['total'] as int;
          final value =
              roundedRatio(net, previous + quantity, original) -
              roundedRatio(net, previous, original);
          final cost =
              roundedRatio(
                target['cost'] as int,
                previous + quantity,
                original,
              ) -
              roundedRatio(target['cost'] as int, previous, original);
          await _stockChange(
            old['warehouse'] as String,
            target['productId'] as String,
            quantity,
            cost,
            quality: 'quarantine',
          );
          target['returned'] = previous + quantity;
          credit += value;
          restoredCost += cost;
        }
        final reduction = credit < (old['debt'] as int)
            ? credit
            : old['debt'] as int;
        final customer = old['customerId'] as String,
            receivable = await read('receivable', old['customerId'] as String);
        await _write('receivable', customer, {
          'balance': (receivable['balance'] as int) - reduction,
        });
        return {
          ...old,
          'lines': lines,
          'debt': (old['debt'] as int) - reduction,
          'returnedValue': (old['returnedValue'] as int? ?? 0) + credit,
          'returnedCost': (old['returnedCost'] as int? ?? 0) + restoredCost,
          'refundDue': (old['refundDue'] as int? ?? 0) + credit - reduction,
        };
      case Operation.refund:
        if (old.isEmpty) {
          throw const BusinessException('missing', 'Không tìm thấy đơn gốc.');
        }
        await _openShift(p);
        textField(p, 'reason');
        final amount = integerField(p, 'amount', min: 1),
            due = old['refundDue'] as int? ?? 0;
        if (!{'cash', 'bank'}.contains(p['method']) || amount > due) {
          throw const BusinessException(
            'validation',
            'Hoàn vượt số tiền được phép hoặc sai phương thức.',
          );
        }
        return {
          ...old,
          'refundDue': due - amount,
          'refunded': (old['refunded'] as int? ?? 0) + amount,
        };
      case Operation.purchase:
        _fresh(old);
        final lines = _lines(p);
        textField(p, 'supplierId');
        textField(p, 'warehouse');
        for (final l in lines) {
          integerField(l, 'unitCost');
          if (await store.product(textField(l, 'productId')) == null) {
            throw const BusinessException(
              'missing',
              'Sản phẩm trong đơn mua không tồn tại.',
            );
          }
        }
        return {
          ...p,
          'lines': [
            for (final l in lines) {...l, 'received': 0},
          ],
          'status': 'ordered',
        };
      case Operation.receive:
        if (old.isEmpty) {
          throw const BusinessException('missing', 'Không tìm thấy đơn mua.');
        }
        final received = _lines(p);
        final lines = (old['lines'] as List)
            .map((l) => Map<String, dynamic>.from(l as Map))
            .toList();
        int receiptValue = 0;
        for (final l in received) {
          final matches = lines.where((x) => x['productId'] == l['productId']);
          if (matches.isEmpty) {
            throw const BusinessException(
              'validation',
              'Hàng nhận không thuộc đơn mua.',
            );
          }
          final ordered = matches.single;
          final quantity = integerField(l, 'quantity', min: 1, max: 1000000000);
          final done = ordered['received'] as int;
          if (done + quantity > (ordered['quantity'] as int)) {
            throw const BusinessException(
              'excess',
              'Số lượng nhận vượt số đặt còn lại.',
            );
          }
          final quality = l['quality'] ?? 'good';
          if (!{'good', 'quarantine', 'damaged'}.contains(quality)) {
            throw const BusinessException(
              'validation',
              'Trạng thái chất lượng không hợp lệ.',
            );
          }
          final value = roundedRatio(
            ordered['unitCost'] as int,
            quantity,
            1000,
          );
          await _stockChange(
            old['warehouse'] as String,
            l['productId'] as String,
            quantity,
            value,
            quality: quality as String,
          );
          ordered['received'] = done + quantity;
          receiptValue += value;
        }
        final supplier = old['supplierId'] as String;
        final debt = await read('payable', supplier);
        await _write('payable', supplier, {
          'balance': (debt['balance'] as int? ?? 0) + receiptValue,
        });
        return {
          ...old,
          'lines': lines,
          'receivedValue': (old['receivedValue'] as int? ?? 0) + receiptValue,
          'status': lines.every((l) => l['received'] == l['quantity'])
              ? 'received'
              : 'partial',
        };
      case Operation.sale:
        _fresh(old);
        final lines = _lines(p);
        final warehouse = textField(p, 'warehouse');
        final customer = textField(p, 'customerId');
        int subtotal = 0, cost = 0;
        final snapshots = <Map<String, dynamic>>[];
        for (final l in lines) {
          final product = await store.product(textField(l, 'productId'));
          if (product == null) {
            throw const BusinessException('missing', 'Sản phẩm không tồn tại.');
          }
          final quantity = integerField(l, 'quantity', min: 1, max: 1000000000);
          // Prices come from catalog; a client cannot forge their snapshot price.
          final lineTotal = roundedRatio(product.price, quantity, 1000);
          final lineCost = await _issue(warehouse, product.id, quantity);
          subtotal += lineTotal;
          cost += lineCost;
          snapshots.add({
            ...l,
            'sku': product.sku,
            'name': product.name,
            'unit': product.unit,
            'unitPrice': product.price,
            'total': lineTotal,
            'cost': lineCost,
            'delivered': 0,
          });
        }
        final discount = integerField(p, 'discount');
        if (discount > subtotal) {
          throw const BusinessException(
            'validation',
            'Chiết khấu vượt tiền hàng.',
          );
        }
        if (discount > 0 &&
            actor.role != StaffRole.admin &&
            actor.role != StaffRole.manager) {
          throw const BusinessException(
            'permission',
            'Chiết khấu cần quyền quản lý trong cấu hình hiện tại.',
          );
        }
        final total = subtotal - discount;
        var cumulative = 0, allocatedDiscount = 0;
        for (final line in snapshots) {
          cumulative += line['total'] as int;
          final allocated = subtotal == 0
              ? 0
              : roundedRatio(discount, cumulative, subtotal);
          line['netTotal'] =
              (line['total'] as int) - (allocated - allocatedDiscount);
          allocatedDiscount = allocated;
        }
        final debt = await read('receivable', customer);
        await _write('receivable', customer, {
          'balance': (debt['balance'] as int? ?? 0) + total,
        });
        return {
          ...p,
          'lines': snapshots,
          'total': total,
          'cost': cost,
          'paid': 0,
          'debt': total,
          'status': 'posted',
        };
      case Operation.payment:
        if (old.isEmpty) {
          throw const BusinessException('missing', 'Không tìm thấy đơn bán.');
        }
        final amount = integerField(p, 'amount', min: 1);
        await _openShift(p, sign: 1);
        final method = textField(p, 'method');
        if (!{'cash', 'bank'}.contains(method)) {
          throw const BusinessException(
            'validation',
            'Phương thức thanh toán không hợp lệ.',
          );
        }
        if (amount > (old['debt'] as int)) {
          throw const BusinessException(
            'overpayment',
            'Thu vượt công nợ còn lại.',
          );
        }
        final customer = old['customerId'] as String;
        final debt = await read('receivable', customer);
        await _write('receivable', customer, {
          'balance': (debt['balance'] as int) - amount,
        });
        return {
          ...old,
          'paid': (old['paid'] as int) + amount,
          'debt': (old['debt'] as int) - amount,
        };
      case Operation.delivery:
        if (old.isEmpty) {
          throw const BusinessException('missing', 'Không tìm thấy đơn bán.');
        }
        textField(p, 'driverId');
        textField(p, 'vehicleId');
        if (actor.role == StaffRole.driver &&
            (p['driverId'] != actor.uid || old['driverId'] != actor.uid)) {
          throw const BusinessException(
            'permission',
            'Chỉ được cập nhật chuyến được giao.',
          );
        }
        final delivered = _lines(p);
        final lines = (old['lines'] as List)
            .map((l) => Map<String, dynamic>.from(l as Map))
            .toList();
        for (final l in delivered) {
          final matches = lines.where((x) => x['productId'] == l['productId']);
          if (matches.isEmpty) {
            throw const BusinessException(
              'validation',
              'Hàng giao không thuộc đơn.',
            );
          }
          final target = matches.single;
          final quantity = integerField(l, 'quantity', min: 1, max: 1000000000);
          final next = (target['delivered'] as int) + quantity;
          if (next >
              (target['quantity'] as int) - (target['returned'] as int? ?? 0)) {
            throw const BusinessException('excess', 'Giao vượt số lượng đơn.');
          }
          target['delivered'] = next;
        }
        return {
          ...old,
          'lines': lines,
          'deliveryStatus': lines.every((l) => l['quantity'] == l['delivered'])
              ? 'delivered'
              : 'partial',
        };
      case Operation.quarantine:
      case Operation.release:
        _fresh(old);
        final warehouse = textField(p, 'warehouse'),
            product = textField(p, 'productId');
        final quantity = integerField(p, 'quantity', min: 1, max: 1000000000);
        textField(p, 'reason');
        if (op == Operation.quarantine) {
          final value = await _issue(warehouse, product, quantity);
          await _stockChange(
            warehouse,
            product,
            quantity,
            value,
            quality: 'quarantine',
          );
        } else {
          final current = await stock(
            warehouse,
            product,
            quality: 'quarantine',
          );
          final available = current['quantity'] as int? ?? 0;
          if (quantity > available) {
            throw const BusinessException('stock', 'Không đủ hàng cách ly.');
          }
          final value = roundedRatio(
            current['value'] as int,
            quantity,
            available,
          );
          await _stockChange(
            warehouse,
            product,
            -quantity,
            -value,
            quality: 'quarantine',
          );
          await _stockChange(warehouse, product, quantity, value);
        }
        return {...p, 'status': 'posted'};
      case Operation.expense:
        _fresh(old);
        await _openShift(p);
        integerField(p, 'amount', min: 1);
        textField(p, 'reason');
        if (!{'cash', 'bank'}.contains(p['method'])) {
          throw const BusinessException(
            'validation',
            'Phương thức chi không hợp lệ.',
          );
        }
        return {...p, 'status': 'posted'};
      case Operation.shiftClose:
        _fresh(old);
        final shiftId = textField(p, 'shiftId');
        final opening = integerField(p, 'opening'),
            counted = integerField(p, 'counted');
        final duplicate = await read('closedShift', shiftId);
        if (duplicate.isNotEmpty) {
          throw const BusinessException('locked', 'Ca đã được chốt.');
        }
        final totals = await read('shiftTotals', shiftId);
        final cash = opening + (totals['cashNet'] as int? ?? 0);
        final bank = totals['bankNet'] as int? ?? 0;
        final difference = counted - cash;
        if (difference != 0) textField(p, 'explanation');
        await _write('closedShift', shiftId, {
          'closedBy': actor.uid,
          'documentId': id,
        });
        return {
          ...p,
          'expected': cash,
          'difference': difference,
          'bankNet': bank,
          'status': 'closed',
        };
      case Operation.warranty:
        _fresh(old);
        textField(p, 'customerId');
        textField(p, 'condition');
        textField(p, 'accessories');
        final sale = await read('sale', textField(p, 'saleId'));
        if (sale.isEmpty || sale['customerId'] != p['customerId']) {
          throw const BusinessException(
            'missing',
            'Đơn bán không thuộc khách hàng.',
          );
        }
        return {...p, 'status': 'received', 'cost': 0};
      case Operation.warrantyUpdate:
        if (old.isEmpty) {
          throw const BusinessException(
            'missing',
            'Không tìm thấy phiếu bảo hành.',
          );
        }
        final next = textField(p, 'status');
        const transitions = {
          'received': {'checking'},
          'checking': {'repairing', 'supplier', 'rejected'},
          'repairing': {'completed', 'supplier'},
          'supplier': {'completed', 'rejected'},
          'completed': <String>{},
          'rejected': <String>{},
        };
        if (!(transitions[old['status']] ?? {}).contains(next)) {
          throw const BusinessException(
            'transition',
            'Bước xử lý bảo hành không hợp lệ.',
          );
        }
        return {...old, 'status': next, 'cost': integerField(p, 'cost')};
    }
  }

  Future<void> _openShift(Map<String, dynamic> payload, {int sign = -1}) async {
    final shiftId = textField(payload, 'shiftId');
    if ((await read('closedShift', shiftId)).isNotEmpty) {
      throw const BusinessException(
        'locked',
        'Ca đã chốt, không được thêm thu chi.',
      );
    }
    final amount = integerField(payload, 'amount', min: 1);
    final method = textField(payload, 'method');
    if (!{'cash', 'bank'}.contains(method)) {
      throw const BusinessException(
        'validation',
        'Phương thức thanh toán không hợp lệ.',
      );
    }
    final totals = await read('shiftTotals', shiftId);
    await _write('shiftTotals', shiftId, {
      'cashNet':
          (totals['cashNet'] as int? ?? 0) +
          (method == 'cash' ? sign * amount : 0),
      'bankNet':
          (totals['bankNet'] as int? ?? 0) +
          (method == 'bank' ? sign * amount : 0),
    });
  }
}
