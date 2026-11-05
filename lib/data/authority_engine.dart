import 'dart:convert';

import '../domain/operations.dart';
import '../domain/product_policy.dart';
import 'database.dart';
import 'authority_store.dart';
import 'stock_tracking.dart';

/// Transaction processor for the trusted station. Authentication/transport must
/// verify Actor independently; this class is not a replacement for cloud Rules.
/// It is not wired to the unauthenticated development UI.
class AuthorityEngine {
  final AuthorityStore store;
  AuthorityEngine(AppDatabase db) : store = DriftAuthorityStore(db);
  AuthorityEngine.withStore(this.store);
  late final tracking = StockTracking(
    read,
    (kind, id, data) => _write(kind, id, data),
  );

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
      if (existing.fingerprint != fingerprint &&
          existing.fingerprint !=
              command.legacyFingerprint(verifiedActor.uid)) {
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
      Operation.deposit || Operation.reservationRefund => 'reservation',
      Operation.printResult || Operation.printClaim => 'printRequest',
      Operation.approveReservation ||
      Operation.cancelReservation ||
      Operation.fulfillReservation => 'reservation',
      Operation.receive => 'purchase',
      Operation.quoteToSale => 'quote',
      Operation.payment ||
      Operation.assignDelivery ||
      Operation.delivery ||
      Operation.returnSale ||
      Operation.refund => 'sale',
      Operation.supplierPayment => 'payable',
      Operation.debtCollection => 'receivable',
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
    result['createdAt'] =
        previous['createdAt'] ?? DateTime.now().toUtc().toIso8601String();
    result['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await _write(kind, command.entityId, result, version: version);
    await store.saveReceipt(command.id, fingerprint, result);
    await store.appendEvent(command, verifiedActor, {
      'entityId': command.entityId,
      'input': payload,
      'result': result,
      'before': previous,
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
        payload: jsonEncode({
          ...value,
          'id': value['id'] ?? id,
          'version': nextVersion,
        }),
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
      line['productId'] = id;
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
    const qualities = ['good', 'quarantine', 'damaged'];
    if (!qualities.contains(quality)) {
      throw const BusinessException('stock', 'Chất lượng tồn không hợp lệ.');
    }
    final positions = <String, Map<String, dynamic>>{};
    var totalQuantity = quantity, totalValue = value;
    for (final state in qualities) {
      final current = await stock(warehouse, product, quality: state);
      positions[state] = current;
      totalQuantity += current['quantity'] as int? ?? 0;
      totalValue += current['value'] as int? ?? 0;
    }
    final changedQuantity =
        (positions[quality]!['quantity'] as int? ?? 0) + quantity;
    if (changedQuantity < 0 ||
        totalQuantity < 0 ||
        totalQuantity > 9000000000000 ||
        totalValue < 0 ||
        totalValue > 9000000000000 ||
        (totalQuantity == 0 && totalValue != 0)) {
      throw const BusinessException(
        'stock',
        'Không đủ tồn hợp lệ hoặc giá trị tồn không cân đối.',
      );
    }
    final information = await store.product(product);
    var cumulativeQuantity = 0, allocatedValue = 0;
    // One weighted average per product/warehouse. Quality affects availability,
    // never creates a separate costing pool. Values sum exactly after rounding.
    for (final state in qualities) {
      final previous = positions[state]!;
      final q = state == quality
          ? changedQuantity
          : previous['quantity'] as int? ?? 0;
      cumulativeQuantity += q;
      final cumulativeValue = totalQuantity == 0
          ? 0
          : roundedRatio(totalValue, cumulativeQuantity, totalQuantity);
      final positionValue = cumulativeValue - allocatedValue;
      allocatedValue = cumulativeValue;
      if (previous.isEmpty && q == 0) continue;
      if (previous['quantity'] == q &&
          previous['value'] == positionValue &&
          previous['name'] == information?.name &&
          previous['unit'] == information?.unit) {
        continue;
      }
      await _write('stock', _stockId(warehouse, product, state), {
        'name': information?.name ?? product,
        'sku': information?.sku ?? '',
        'unit': information?.unit ?? '',
        'warehouse': warehouse,
        'productId': product,
        'quality': state,
        'quantity': q,
        'value': positionValue,
      });
    }
  }

  Future<({int quantity, int value})> _valuation(
    String warehouse,
    String product,
  ) async {
    var quantity = 0, value = 0;
    for (final quality in ['good', 'quarantine', 'damaged']) {
      final current = await stock(warehouse, product, quality: quality);
      quantity += current['quantity'] as int? ?? 0;
      value += current['value'] as int? ?? 0;
    }
    return (quantity: quantity, value: value);
  }

  Future<int> _issueValue(
    String warehouse,
    String product,
    int quantity,
  ) async {
    final totals = await _valuation(warehouse, product);
    return roundedRatio(totals.value, quantity, totals.quantity);
  }

  Future<int> _issue(String warehouse, String product, int quantity) async {
    final current = await stock(warehouse, product);
    final available = current['quantity'] as int? ?? 0;
    final reserved =
        (await read(
              'reservedStock',
              jsonEncode([warehouse, product]),
            ))['quantity']
            as int? ??
        0;
    if (quantity > available - reserved) {
      throw const BusinessException(
        'oversell',
        'Vượt tồn bán được. Cần quản lý duyệt đơn chờ nhập hoặc giao phần có sẵn.',
      );
    }
    final value = await _issueValue(warehouse, product, quantity);
    await _stockChange(warehouse, product, -quantity, -value);
    return value;
  }

  Future<Map<String, dynamic>> _apply(
    Operation op,
    String id,
    Map<String, dynamic> p,
    Map<String, dynamic> old,
    Actor actor, {
    Map<String, dynamic>? quoteSnapshot,
  }) async {
    switch (op) {
      case Operation.deposit:
        if (old.isEmpty ||
            !{'reserved', 'waiting', 'partial'}.contains(old['status'])) {
          throw const BusinessException(
            'deposit',
            'Chỉ thu cọc cho đơn giữ hàng hoặc đơn chờ đã được duyệt.',
          );
        }
        final amount = integerField(p, 'amount', min: 1),
            paid = old['depositPaid'] as int? ?? 0;
        if (amount > (old['total'] as int) - paid) {
          throw const BusinessException(
            'overpayment',
            'Thu cọc vượt giá trị đơn.',
          );
        }
        await _openShift(p, sign: 1);
        await _depositChange(old['customerId'] as String, amount);
        await _write('deposit', '$id:${old['version']}', {
          ...p,
          'reservationId': id,
          'customerId': old['customerId'],
          'customerName': (await read(
            'party',
            old['customerId'] as String,
          ))['name'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        return {...old, 'depositPaid': paid + amount};
      case Operation.reservationRefund:
        if (old.isEmpty ||
            !{'cancelled', 'converted'}.contains(old['status'])) {
          throw const BusinessException(
            'deposit',
            'Chỉ hoàn cọc dư của đơn đã hủy hoặc đã chuyển bán.',
          );
        }
        final due = old['depositRefundDue'] as int? ?? 0,
            amount = integerField(p, 'amount', min: 1);
        if (amount > due) {
          throw const BusinessException(
            'overpayment',
            'Hoàn vượt tiền cọc còn lại.',
          );
        }
        textField(p, 'reason');
        await _openShift(p);
        await _depositChange(old['customerId'] as String, -amount);
        await _write('reservationRefund', '$id:${old['version']}', {
          ...p,
          'reservationId': id,
          'customerId': old['customerId'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        return {
          ...old,
          'depositRefundDue': due - amount,
          'depositRefunded': (old['depositRefunded'] as int? ?? 0) + amount,
        };
      case Operation.settings:
        if (id != 'store') {
          throw const BusinessException(
            'validation',
            'Định danh cấu hình không hợp lệ.',
          );
        }
        return {
          'name': textField(p, 'name'),
          'address': p['address'] as String? ?? '',
          'phone': p['phone'] as String? ?? '',
          'taxCode': p['taxCode'] as String? ?? '',
        };
      case Operation.printRequest:
        _fresh(old);
        final kind = textField(p, 'documentKind'),
            documentId = textField(p, 'documentId');
        if (!{
          'sale',
          'quote',
          'purchase',
          'delivery',
          'shiftClose',
          'expense',
          'payment',
          'supplierPayment',
          'refund',
          'deposit',
          'reservationRefund',
          'purchaseReceipt',
          'transfer',
          'returnReceipt',
          'inventoryCount',
          'assemble',
          'qualityDisposition',
          'warranty',
        }.contains(kind)) {
          throw const BusinessException(
            'print',
            'Loại phiếu chưa hỗ trợ gửi in.',
          );
        }
        final snapshot = await read(kind, documentId);
        if (snapshot.isEmpty ||
            (actor.role == StaffRole.driver &&
                (kind != 'delivery' || snapshot['driverId'] != actor.uid))) {
          throw const BusinessException(
            'permission',
            'Không có quyền in chứng từ này.',
          );
        }
        if (snapshot['version'] != integerField(p, 'documentVersion', min: 1)) {
          throw const BusinessException(
            'conflict',
            'Chứng từ đã thay đổi. Đồng bộ lại trước khi gửi in.',
          );
        }
        return {
          'documentKind': kind,
          'documentId': documentId,
          'snapshot': snapshot,
          'requestedBy': actor.uid,
          'status': 'queued',
        };
      case Operation.printClaim:
        if (old.isEmpty || old['status'] != 'queued') {
          throw const BusinessException(
            'locked',
            'Yêu cầu đã được trạm khác nhận.',
          );
        }
        return {
          ...old,
          'status': 'claimed',
          'claimedBy': actor.uid,
          'claimToken': textField(p, 'claimToken'),
        };
      case Operation.printResult:
        if (old.isEmpty ||
            old['status'] != 'claimed' ||
            old['claimedBy'] != actor.uid ||
            old['claimToken'] != p['claimToken']) {
          throw const BusinessException(
            'locked',
            'Yêu cầu in không thuộc quyền giữ của thiết bị này hoặc đã đối chiếu.',
          );
        }
        final status = textField(p, 'status');
        if (!{'sent_to_system', 'cancelled', 'unknown'}.contains(status)) {
          throw const BusinessException(
            'print',
            'Kết quả gửi in không hợp lệ.',
          );
        }
        return {
          ...old,
          'status': status,
          'operator': actor.uid,
          'note': textField(p, 'note'),
        };
      case Operation.vehicle:
        return {
          ...old,
          'name': textField(p, 'name'),
          'plate': textField(p, 'plate').toUpperCase(),
          'capacityKg': integerField(p, 'capacityKg', min: 1),
          'active': p['active'] != false,
        };
      case Operation.staff:
        if (actor.role != StaffRole.admin || id == actor.uid) {
          throw const BusinessException(
            'permission',
            'Chỉ Admin được chỉnh nhân viên khác.',
          );
        }
        final previous = await store.member(id);
        if (previous == null || previous['role'] == 'station') {
          throw const BusinessException(
            'permission',
            'Tài khoản cần được chủ project tạo trước; không chỉnh tài khoản trạm.',
          );
        }
        final role = textField(p, 'role');
        if (!StaffRole.values.any((r) => r.name == role) ||
            p['active'] is! bool) {
          throw const BusinessException(
            'validation',
            'Vai trò hoặc trạng thái không hợp lệ.',
          );
        }
        final result = {
          ...previous,
          'role': role,
          'active': p['active'],
          'displayName': textField(p, 'displayName'),
          'updatedBy': actor.uid,
        };
        await store.writeMember(id, result);
        return {
          'uid': id,
          'role': role,
          'active': p['active'],
          'displayName': result['displayName'],
          'mustChangePassword': previous['mustChangePassword'],
        };
      case Operation.inventoryCount:
        _fresh(old);
        final warehouse = textField(p, 'warehouse'),
            product = textField(p, 'productId');
        final quality = textField(p, 'quality');
        if (!{'good', 'quarantine', 'damaged'}.contains(quality)) {
          throw const BusinessException(
            'validation',
            'Chất lượng kiểm kê không hợp lệ.',
          );
        }
        textField(p, 'reason');
        final current = await stock(warehouse, product, quality: quality);
        if ((current['version'] ?? 0) != integerField(p, 'stockVersion')) {
          throw const BusinessException(
            'conflict',
            'Kho đã thay đổi sau lúc đếm. Hãy kiểm kê và đối chiếu lại.',
          );
        }
        final physical = current['quantity'] as int? ?? 0;
        final mode = await tracking.mode(product);
        var previous = physical;
        if (mode == 'lot') {
          final lotId = textField(p, 'lotId');
          final lot = await read(
            'lotStock',
            tracking.positionId(warehouse, product, lotId, quality),
          );
          previous = lot['quantity'] as int? ?? 0;
          if (previous != integerField(p, 'expectedLotQuantity')) {
            throw const BusinessException('conflict', 'Tồn lô đã thay đổi.');
          }
        }
        final counted = integerField(p, 'counted', max: 1000000000),
            delta = counted - previous;
        if (quality == 'good' &&
            delta < 0 &&
            -delta > await _available(warehouse, product)) {
          throw const BusinessException(
            'reserved',
            'Tồn thực đếm thấp hơn hàng đã giữ. Hủy hoặc xử lý đơn giữ trước.',
          );
        }
        final valuation = await _valuation(warehouse, product);
        final value = delta < 0
            ? -await _issueValue(warehouse, product, -delta)
            : valuation.quantity > 0
            ? roundedRatio(valuation.value, delta, valuation.quantity)
            : roundedRatio(integerField(p, 'unitCost'), delta, 1000);
        if (await store.product(product) == null) {
          throw const BusinessException('missing', 'Hàng hóa không tồn tại.');
        }
        await tracking.adjust(warehouse, p, delta, id, quality);
        if (delta != 0) {
          await _stockChange(
            warehouse,
            product,
            delta,
            value,
            quality: quality,
          );
        }
        return {
          ...p,
          'previous': previous,
          'difference': delta,
          'valueDifference': value,
          'status': 'posted',
        };
      case Operation.reservation:
        _fresh(old);
        final warehouse = textField(p, 'warehouse');
        textField(p, 'customerId');
        integerField(p, 'discount');
        final lines = _lines(p), snapshots = <Map<String, dynamic>>[];
        var oversell = false;
        for (final line in lines) {
          final product = await store.product(textField(line, 'productId'));
          if (product == null) {
            throw const BusinessException('missing', 'Hàng hóa không tồn tại.');
          }
          final terms = await _terms(product, line, p['customerId'] as String);
          if (integerField(line, 'expectedPrice') != terms['unitPrice']) {
            throw const BusinessException(
              'conflict',
              'Hàng hóa hoặc giá đã thay đổi. Đồng bộ và kiểm tra lại.',
            );
          }
          final available = await _available(warehouse, product.id);
          if (integerField(line, 'quantity', min: 1) > available) {
            oversell = true;
          }
          snapshots.add({
            ...line,
            ...terms,
            'name': product.name,
            'sku': product.sku,
            'unit': product.unit,
            'reserved': 0,
          });
        }
        if (!oversell) {
          for (final line in snapshots) {
            await _reserve(
              warehouse,
              line['productId'] as String,
              line['quantity'] as int,
            );
            line['reserved'] = line['quantity'];
          }
        }
        final subtotal = snapshots.fold<int>(
              0,
              (sum, line) =>
                  sum +
                  roundedRatio(
                    line['unitPrice'] as int,
                    line['quantity'] as int,
                    1000,
                  ),
            ),
            discount = integerField(p, 'discount');
        final approved = {
          StaffRole.admin,
          StaffRole.manager,
        }.contains(actor.role);
        if (discount > subtotal || (discount > 0 && !approved)) {
          throw const BusinessException(
            'permission',
            'Chiết khấu cần quản lý duyệt và không được vượt tiền hàng.',
          );
        }
        return {
          ...p,
          'total': subtotal - discount + _surcharge(p),
          'discountApproved': approved,
          'depositPaid': 0,
          'depositRefundDue': 0,
          'depositRefunded': 0,
          'lines': snapshots,
          'ownerUid': actor.uid,
          'warehouse': warehouse,
          'customerId': textField(p, 'customerId'),
          'status': oversell ? 'pendingApproval' : 'reserved',
        };
      case Operation.approveReservation:
        if (old.isEmpty ||
            !{'pendingApproval', 'waiting'}.contains(old['status'])) {
          throw const BusinessException(
            'locked',
            'Yêu cầu không còn chờ duyệt.',
          );
        }
        final decision = textField(p, 'decision');
        textField(p, 'reason');
        if (!{'wait', 'partial', 'reject'}.contains(decision)) {
          throw const BusinessException(
            'validation',
            'Quyết định không hợp lệ.',
          );
        }
        final warehouse = old['warehouse'] as String;
        final lines = [
          for (final line in old['lines'] as List)
            Map<String, dynamic>.from(line as Map),
        ];
        if (decision == 'partial') {
          for (final line in lines) {
            final available = await _available(
                  warehouse,
                  line['productId'] as String,
                ),
                wanted = line['quantity'] as int;
            var q = available < wanted ? available : wanted;
            if (line['lotAllocations'] != null) {
              final lots = <Map<String, dynamic>>[];
              var remaining = q;
              final product = line['productId'] as String;
              for (final lot in StockTracking.lots(line, wanted)) {
                if (remaining <= 0) break;
                final position = await read(
                  'lotStock',
                  tracking.positionId(
                    warehouse,
                    product,
                    lot['lotId'] as String,
                    'good',
                  ),
                );
                final physical = position['quantity'] as int? ?? 0;
                final requested = lot['quantity'] as int;
                final limit = requested < remaining ? requested : remaining;
                final take = physical < limit ? physical : limit;
                if (take > 0) {
                  lots.add({...lot, 'quantity': take});
                  remaining -= take;
                }
              }
              q -= remaining;
              line['approvedLotAllocations'] = lots;
            }
            if (q > 0) {
              await _reserve(warehouse, line['productId'] as String, q);
            }
            line['reserved'] = q;
          }
        }
        return {
          ...old,
          'lines': lines,
          'approvedBy': actor.uid,
          'approvalReason': p['reason'],
          'status': switch (decision) {
            'wait' => 'waiting',
            'partial' => 'partial',
            _ => 'rejected',
          },
        };
      case Operation.cancelReservation:
      case Operation.fulfillReservation:
        if (old.isEmpty ||
            !{
              'reserved',
              'partial',
              'waiting',
              'pendingApproval',
            }.contains(old['status'])) {
          throw const BusinessException('locked', 'Đơn giữ hàng đã kết thúc.');
        }
        if (actor.role == StaffRole.sales && old['ownerUid'] != actor.uid) {
          throw const BusinessException(
            'permission',
            'Chỉ xử lý đơn giữ hàng của mình.',
          );
        }
        if (op == Operation.fulfillReservation &&
            old['status'] == 'pendingApproval') {
          throw const BusinessException(
            'permission',
            'Vượt tồn chưa được quản lý duyệt.',
          );
        }
        final warehouse = old['warehouse'] as String;
        final original = [
          for (final line in old['lines'] as List)
            Map<String, dynamic>.from(line as Map),
        ];
        for (final line in original) {
          await _reserve(
            warehouse,
            line['productId'] as String,
            -(line['reserved'] as int),
          );
        }
        if (op == Operation.cancelReservation) {
          return {
            ...old,
            'status': 'cancelled',
            'cancelledBy': actor.uid,
            'depositRefundDue': old['depositPaid'] as int? ?? 0,
          };
        }
        final saleId = textField(p, 'saleId');
        if ((await read('sale', saleId)).isNotEmpty) {
          throw const BusinessException('duplicate', 'Mã đơn bán đã tồn tại.');
        }
        final partial = p['partial'] == true;
        if (partial && old['status'] != 'partial') {
          throw const BusinessException(
            'validation',
            'Chỉ giao phần có sẵn sau khi quản lý duyệt.',
          );
        }
        final lines = <Map<String, dynamic>>[];
        for (final line in original) {
          final q = partial ? line['reserved'] as int : line['quantity'] as int;
          if (q > 0) {
            final factor = line['unitFactor'] as int? ?? 1000;
            if ((BigInt.from(q) * BigInt.from(1000)) % BigInt.from(factor) !=
                BigInt.zero) {
              throw const BusinessException(
                'unit',
                'Phần giao không đủ đơn vị quy đổi; đổi sang đơn vị gốc trước khi ghi sổ.',
              );
            }
            lines.add(
              {
                ...line,
                if (partial && line['lotAllocations'] != null)
                  'lotAllocations': line['approvedLotAllocations'],
                'quantity': q,
                'saleQuantity':
                    (BigInt.from(q) * BigInt.from(1000) ~/ BigInt.from(factor))
                        .toInt(),
                if (partial && line['serials'] is List)
                  'serials': (line['serials'] as List).take(q ~/ 1000).toList(),
              }..remove('approvedLotAllocations'),
            );
          }
        }
        if (partial && (old['discount'] as int) > 0) {
          throw const BusinessException(
            'validation',
            'Đơn có chiết khấu cần nhận đủ hàng hoặc hủy và tạo lại phần giao để đối chiếu chiết khấu.',
          );
        }
        final result = await _apply(
          Operation.sale,
          saleId,
          {...old, 'lines': lines, 'reservationId': id},
          {},
          actor,
          quoteSnapshot: old,
        );
        final prepaid = old['depositPaid'] as int? ?? 0,
            applied = prepaid < (result['total'] as int)
                ? prepaid
                : result['total'] as int;
        if (applied > 0) {
          final customer = old['customerId'] as String,
              receivable = await read(
                'receivable',
                old['customerId'] as String,
              );
          await _write('receivable', customer, {
            'balance': (receivable['balance'] as int) - applied,
          });
          await _depositChange(customer, -applied);
          result['paid'] = applied;
          result['debt'] = (result['total'] as int) - applied;
          result['depositApplied'] = applied;
        }
        final sale = {
          ...result,
          'id': saleId,
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
        await _write('sale', saleId, sale, version: 1);
        return {
          ...old,
          'status': 'converted',
          'saleId': saleId,
          'saleDocument': sale,
          'depositAllocated': applied,
          'depositRefundDue': prepaid - applied,
          'unfulfilledLines': [
            for (final line in original)
              if (partial &&
                  (line['quantity'] as int) > (line['reserved'] as int))
                {
                  ...line,
                  'quantity':
                      (line['quantity'] as int) - (line['reserved'] as int),
                },
          ],
        };
      case Operation.quote:
        if (old['status'] == 'converted') {
          throw const BusinessException(
            'locked',
            'Báo giá đã chuyển thành đơn.',
          );
        }
        textField(p, 'customerId');
        final lines = _lines(p), snapshots = <Map<String, dynamic>>[];
        var subtotal = 0;
        for (final line in lines) {
          final product = await store.product(textField(line, 'productId'));
          if (product == null) {
            throw const BusinessException('missing', 'Hàng hóa không tồn tại.');
          }
          final terms = await _terms(product, line, p['customerId'] as String);
          final price = terms['unitPrice'] as int;
          if (integerField(line, 'expectedPrice') != price) {
            throw const BusinessException(
              'conflict',
              'Giá hàng đã thay đổi. Đồng bộ và kiểm tra lại báo giá.',
            );
          }
          final total = roundedRatio(
            price,
            integerField(line, 'quantity', min: 1),
            1000,
          );
          subtotal += total;
          snapshots.add({
            ...line,
            'sku': product.sku,
            'name': product.name,
            'unit': product.unit,
            ...terms,
            'total': total,
          });
        }
        final discount = integerField(p, 'discount');
        if (discount > subtotal) {
          throw const BusinessException(
            'validation',
            'Chiết khấu vượt tổng tiền.',
          );
        }
        final approved =
            actor.role == StaffRole.admin || actor.role == StaffRole.manager;
        if (discount > 0 && !approved) {
          throw const BusinessException(
            'permission',
            'Chiết khấu cần quản lý duyệt.',
          );
        }
        final result = {
          ...p,
          'customerId': textField(p, 'customerId'),
          'lines': snapshots,
          'total': subtotal - discount + _surcharge(p),
          'storeSnapshot': await read('settings', 'store'),
          'customerName':
              (await read('party', p['customerId'] as String))['name'] ??
              p['customerId'],
          'buyerSnapshot': await read('party', p['customerId'] as String),
          'surcharge': _surcharge(p),
          'discount': discount,
          'discountApproved': approved,
          'status': 'active',
        };
        final version = (old['version'] as int? ?? 0) + 1;
        await _write('quoteVersion', '$id:$version', {
          ...result,
          'quoteId': id,
          'quoteVersion': version,
        });
        return result;
      case Operation.quoteToSale:
        if (old.isEmpty || old['status'] != 'active') {
          throw const BusinessException(
            'locked',
            'Báo giá không còn ở trạng thái có thể chuyển đơn.',
          );
        }
        final saleId = textField(p, 'saleId');
        if ((await read('sale', saleId)).isNotEmpty) {
          throw const BusinessException('duplicate', 'Mã đơn bán đã tồn tại.');
        }
        final result = await _apply(
          Operation.sale,
          saleId,
          {
            'warehouse': textField(p, 'warehouse'),
            'customerId': old['customerId'],
            'discount': old['discount'],
            'surcharge': old['surcharge'] ?? 0,
            'dueAt': old['dueAt'] ?? '',
            'quoteId': id,
            if (old['allowMixedLotColors'] == true) 'allowMixedLotColors': true,
            'lines': [
              for (final line in old['lines'] as List)
                {
                  ...(line as Map<String, dynamic>),
                  'productId': line['productId'],
                  'quantity': line['quantity'],
                },
            ],
          },
          {},
          actor,
          quoteSnapshot: old,
        );
        final sale = {
          ...result,
          'id': saleId,
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
        await _write('sale', saleId, sale, version: 1);
        return {
          ...old,
          'status': 'converted',
          'saleId': saleId,
          'saleDocument': sale,
        };
      case Operation.assignDelivery:
        if (old.isEmpty) {
          throw const BusinessException('missing', 'Không tìm thấy đơn bán.');
        }
        final driver = textField(p, 'driverId'),
            vehicle = textField(p, 'vehicleId');
        final vehicleData = await read('vehicle', vehicle);
        final load = p['loadKg'] == null ? 0 : integerField(p, 'loadKg');
        if (vehicleData.isNotEmpty &&
            (vehicleData['active'] == false ||
                load > (vehicleData['capacityKg'] as int))) {
          throw const BusinessException(
            'vehicle',
            'Xe ngừng hoạt động hoặc chuyến hàng vượt tải trọng khai báo.',
          );
        }
        final schedule = (p['scheduledAt'] as String? ?? '').trim();
        if (schedule.isNotEmpty && DateTime.tryParse(schedule) == null) {
          throw const BusinessException(
            'validation',
            'Lịch giao dùng dạng năm-tháng-ngày hoặc năm-tháng-ngàyTgiờ:phút.',
          );
        }
        if ((p['latE6'] == null) != (p['lngE6'] == null)) {
          throw const BusinessException(
            'validation',
            'Cần đủ vĩ độ và kinh độ.',
          );
        }
        if (p['latE6'] != null) {
          integerField(p, 'latE6', min: -90000000, max: 90000000);
          integerField(p, 'lngE6', min: -180000000, max: 180000000);
        }
        final destination = {
          ...old,
          'driverId': driver,
          'vehicleId': vehicle,
          'vehiclePlate': vehicleData['plate'] ?? vehicle,
          'loadKg': load,
          'scheduledAt': schedule,
          'address': p['address'] as String? ?? '',
          if (p['latE6'] != null) 'latE6': p['latE6'],
          if (p['lngE6'] != null) 'lngE6': p['lngE6'],
        };
        await _deliveryProjection(id, {...destination}, 'assigned');
        return {...destination, 'deliveryStatus': 'assigned'};
      case Operation.catalog:
        final sku = textField(p, 'sku').toUpperCase(),
            name = textField(p, 'name'),
            unit = textField(p, 'unit');
        final price = integerField(p, 'price', max: 1000000000000);
        final catalogData = {...old, ...p};
        ProductPolicy.validate(catalogData);
        final trackingMode =
            p['tracking'] as String? ?? old['tracking'] as String? ?? 'none';
        if (!{'none', 'lot', 'serial'}.contains(trackingMode)) {
          throw const BusinessException(
            'validation',
            'Chế độ theo dõi không hợp lệ.',
          );
        }
        if (old.isNotEmpty && (old['tracking'] ?? 'none') != trackingMode) {
          throw const BusinessException(
            'locked',
            'Không đổi chế độ lô/serial của mã hàng đã xác nhận; tạo mã hàng mới để tách tồn.',
          );
        }
        if (sku.length > 128 || name.length > 300 || unit.length > 30) {
          throw const BusinessException(
            'validation',
            'Mã, tên hoặc đơn vị quá dài.',
          );
        }
        final index = await read('sku', sku);
        if (index.isNotEmpty && index['productId'] != id) {
          throw const BusinessException('duplicate', 'Mã hàng đã tồn tại.');
        }
        if (old.isNotEmpty && old['sku'] != sku) {
          throw const BusinessException(
            'locked',
            'Không đổi SKU của hàng đã xác nhận.',
          );
        }
        final components = <String, int>{};
        for (final entry in (catalogData['components'] as Map? ?? {}).entries) {
          final componentSku = (entry.key as String).toUpperCase();
          final componentId = (await read('sku', componentSku))['productId'];
          final component = componentId is String
              ? await read('catalog', componentId)
              : <String, dynamic>{};
          if (componentSku == sku ||
              components.containsKey(componentSku) ||
              component.isEmpty ||
              component['active'] == false ||
              (component['tracking'] ?? 'none') != 'none' ||
              (component['components'] as Map?)?.isNotEmpty == true ||
              trackingMode != 'none') {
            throw const BusinessException(
              'components',
              'Chọn mã thành phần đang kinh doanh, không theo lô/serial và không phải bộ sản phẩm.',
            );
          }
          components[componentSku] = entry.value as int;
        }
        await store.writeProduct(
          Product(id: id, sku: sku, name: name, unit: unit, price: price),
        );
        await _write('sku', sku, {'productId': id});
        await _write(
          'priceHistory',
          '$id:${(old['version'] as int? ?? 0) + 1}',
          {
            'productId': id,
            'price': price,
            'priceLists': catalogData['priceLists'] ?? {},
            'quantityTiers': catalogData['quantityTiers'] ?? [],
            'changedBy': actor.uid,
            'changedAt': DateTime.now().toUtc().toIso8601String(),
          },
        );
        return {
          ...old,
          ...p,
          'sku': sku,
          'name': name,
          'unit': unit,
          'price': price,
          'tracking': trackingMode,
          'components': components,
        };
      case Operation.party:
        final name = textField(p, 'name'), type = textField(p, 'type');
        if (actor.role == StaffRole.sales &&
            (p['priceList'] ?? old['priceList'] ?? '') !=
                (old['priceList'] ?? '')) {
          throw const BusinessException(
            'permission',
            'Quản lý phải duyệt việc thay đổi bảng giá khách hàng.',
          );
        }
        if (!{'customer', 'supplier', 'both'}.contains(type)) {
          throw const BusinessException(
            'validation',
            'Loại đối tác không hợp lệ.',
          );
        }
        if (actor.role == StaffRole.sales && type != 'customer') {
          throw const BusinessException(
            'permission',
            'Bán hàng chỉ được tạo khách hàng.',
          );
        }
        final code = (p['code'] as String? ?? old['code'] as String? ?? '')
            .trim()
            .toUpperCase();
        if (code.isNotEmpty) {
          final index = await read('partyCode', code);
          if (code.length > 128 ||
              (index.isNotEmpty && index['partyId'] != id)) {
            throw const BusinessException(
              'duplicate',
              'Mã đối tác bị trùng hoặc quá dài.',
            );
          }
          if (old.isNotEmpty && old['code'] != null && old['code'] != code) {
            throw const BusinessException(
              'locked',
              'Không đổi mã đối tác đã có.',
            );
          }
          await _write('partyCode', code, {'partyId': id});
        }
        return {
          ...old,
          ...p,
          'name': name,
          'code': code,
          'type': type,
          'phone': p['phone'] as String? ?? '',
          'address': p['address'] as String? ?? '',
        };
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
          await tracking.move(from, to, line);
          await _stockChange(to, product, quantity, value);
        }
        return {...p, 'status': 'posted'};
      case Operation.debtCollection:
        if (old.isEmpty) {
          throw const BusinessException(
            'missing',
            'Không tìm thấy công nợ khách hàng.',
          );
        }
        final amount = integerField(p, 'amount', min: 1);
        if (amount > (old['balance'] as int)) {
          throw const BusinessException(
            'overpayment',
            'Thu vượt công nợ khách hàng.',
          );
        }
        await _openShift(p, sign: 1);
        final allocations = await _allocateDebt(id, p, customer: true);
        final party = await read('party', id);
        await _write('payment', 'allocated:$id:${old['version']}', {
          ...p,
          'allocations': allocations,
          'customerId': id,
          'customerName': party['name'],
          'storeSnapshot': await read('settings', 'store'),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        return {...old, 'balance': (old['balance'] as int) - amount};
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
        final allocations = p.containsKey('allocations')
            ? await _allocateDebt(id, p, customer: false)
            : null;
        await _write('supplierPayment', '$id:${old['version']}', {
          ...p,
          'allocations': ?allocations,
          'supplierId': id,
          'supplierName': (await read('party', id))['name'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'storeSnapshot': await read('settings', 'store'),
        });
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
        final returnSnapshots = <Map<String, dynamic>>[];
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
          final returnedLots = await tracking.returnGoods(
            old['warehouse'] as String,
            returned,
            target,
            id,
          );
          await _stockChange(
            old['warehouse'] as String,
            target['productId'] as String,
            quantity,
            cost,
            quality: 'quarantine',
          );
          target['returned'] = previous + quantity;
          returnSnapshots.add({
            ...returned,
            'lotAllocations': ?returnedLots,
            'name': target['name'],
            'sku': target['sku'],
            'unit': target['unit'],
            'unitPrice': target['unitPrice'],
            'total': value,
          });
          credit += value;
          restoredCost += cost;
        }
        final reduction = credit < (old['debt'] as int)
            ? credit
            : old['debt'] as int;
        await _write('returnReceipt', '$id:${old['version']}', {
          'saleId': id,
          'customerId': old['customerId'],
          'customerName': old['customerName'],
          'storeSnapshot': old['storeSnapshot'],
          'warehouse': old['warehouse'],
          'reason': p['reason'],
          'lines': returnSnapshots,
          'total': credit,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
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
        await _write('refund', '$id:${old['version']}', {
          ...p,
          'saleId': id,
          'customerId': old['customerId'],
          'customerName': old['customerName'],
          'storeSnapshot': old['storeSnapshot'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
        return {
          ...old,
          'refundDue': due - amount,
          'refunded': (old['refunded'] as int? ?? 0) + amount,
        };
      case Operation.purchase:
        _fresh(old);
        _date(p, 'expectedAt');
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
          'storeSnapshot': await read('settings', 'store'),
          'warehouse': textField(p, 'warehouse'),
          'supplierId': textField(p, 'supplierId'),
          'supplierName':
              (await read('party', p['supplierId'] as String))['name'] ??
              p['supplierId'],
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
        final fees = p['purchaseCosts'] == null
            ? 0
            : integerField(p, 'purchaseCosts');
        final receiptLines = <Map<String, dynamic>>[];
        var weightTotal = 0, accumulatedWeight = 0, allocatedFees = 0;
        final weights = <String, int>{};
        for (final receivedLine in received) {
          final target = lines
              .where((l) => l['productId'] == receivedLine['productId'])
              .firstOrNull;
          if (target == null) {
            throw const BusinessException(
              'validation',
              'Hàng nhận không thuộc đơn mua.',
            );
          }
          final weight = roundedRatio(
            target['unitCost'] as int,
            receivedLine['quantity'] as int,
            1000,
          );
          weights[receivedLine['productId'] as String] = weight;
          weightTotal += weight;
        }
        if (weightTotal == 0) {
          for (final line in received) {
            weights[line['productId'] as String] = line['quantity'] as int;
            weightTotal += line['quantity'] as int;
          }
        }
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
          accumulatedWeight += weights[l['productId']]!;
          final nextFees = roundedRatio(fees, accumulatedWeight, weightTotal);
          final value =
              roundedRatio(ordered['unitCost'] as int, quantity, 1000) +
              nextFees -
              allocatedFees;
          allocatedFees = nextFees;
          final receivedLots = await tracking.receive(
            old['warehouse'] as String,
            l,
            old['supplierId'] as String,
            id,
          );
          await _stockChange(
            old['warehouse'] as String,
            l['productId'] as String,
            quantity,
            value,
            quality: quality as String,
          );
          receiptLines.add({...l, 'lotAllocations': ?receivedLots});
          ordered['received'] = done + quantity;
          receiptValue += value;
        }
        final supplier = old['supplierId'] as String;
        await _write('purchaseReceipt', '$id:${(old['version'] as int) + 1}', {
          'purchaseId': id,
          'supplierId': supplier,
          'warehouse': old['warehouse'],
          'lines': receiptLines,
          'total': receiptValue,
          'purchaseCosts': fees,
          'receivedAt': DateTime.now().toUtc().toIso8601String(),
        });
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
        _date(p, 'dueAt');
        if (p['quoteId'] != null && quoteSnapshot == null) {
          throw const BusinessException(
            'validation',
            'Chuyển báo giá qua đúng nghiệp vụ chuyển đơn.',
          );
        }
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
          final quoted = quoteSnapshot == null
              ? null
              : (quoteSnapshot['lines'] as List)
                    .cast<Map<String, dynamic>>()
                    .firstWhere((q) => q['productId'] == product.id);
          final price = quoted == null
              ? (await _terms(product, l, customer))['unitPrice'] as int
              : quoted['unitPrice'] as int;
          if (quoted == null && integerField(l, 'expectedPrice') != price) {
            throw const BusinessException(
              'conflict',
              'Giá hàng đã thay đổi. Đồng bộ và kiểm tra lại đơn.',
            );
          }
          final lineTotal = roundedRatio(price, quantity, 1000);
          final issuedLots = await tracking.issue(
            warehouse,
            l,
            id,
            allowMixedColors: p['allowMixedLotColors'] == true,
          );
          final lineCost = await _issue(warehouse, product.id, quantity);
          subtotal += lineTotal;
          cost += lineCost;
          snapshots.add(
            {
              ...l,
              'lotAllocations': ?issuedLots,
              'returned': 0,
              if (quoted == null) ...await _terms(product, l, customer),
              'sku': quoted?['sku'] ?? product.sku,
              'name': quoted?['name'] ?? product.name,
              'unit': quoted?['unit'] ?? product.unit,
              'unitPrice': price,
              'warrantyDays':
                  (await read('catalog', product.id))['warrantyDays'] as int? ??
                  0,
              'total': lineTotal,
              'cost': lineCost,
              'delivered': 0,
            }..remove('returnedByLot'),
          );
        }
        final discount = integerField(p, 'discount');
        if (discount > subtotal) {
          throw const BusinessException(
            'validation',
            'Chiết khấu vượt tiền hàng.',
          );
        }
        if (discount > 0 &&
            quoteSnapshot?['discountApproved'] != true &&
            actor.role != StaffRole.admin &&
            actor.role != StaffRole.manager) {
          throw const BusinessException(
            'permission',
            'Chiết khấu cần quyền quản lý trong cấu hình hiện tại.',
          );
        }
        final total = subtotal - discount + _surcharge(p);
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
          'warehouse': warehouse,
          'customerId': customer,
          'total': total,
          'surcharge': _surcharge(p),
          'storeSnapshot':
              quoteSnapshot?['storeSnapshot'] ??
              await read('settings', 'store'),
          'customerName':
              quoteSnapshot?['customerName'] ??
              (await read('party', customer))['name'] ??
              customer,
          'buyerSnapshot':
              quoteSnapshot?['buyerSnapshot'] ?? await read('party', customer),
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
        await _write('payment', '$id:${old['version']}', {
          ...p,
          'saleId': id,
          'customerId': customer,
          'customerName': old['customerName'],
          'storeSnapshot': old['storeSnapshot'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
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
        final status = lines.every((l) => l['quantity'] == l['delivered'])
            ? 'delivered'
            : 'partial';
        final result = {
          ...old,
          'lines': lines,
          'deliveryStatus': status,
          'driverId': p['driverId'],
          'vehicleId': p['vehicleId'],
        };
        await _write('deliveryTrip', '$id:${(old['version'] as int) + 1}', {
          'saleId': id,
          'driverId': actor.uid,
          'vehicleId': p['vehicleId'],
          'lines': delivered,
          'deliveredAt': DateTime.now().toUtc().toIso8601String(),
        });
        await _deliveryProjection(id, result, status);
        return result;
      case Operation.assemble:
        _fresh(old);
        final warehouse = textField(p, 'warehouse');
        final productId = textField(p, 'productId');
        final kits = integerField(p, 'kits', min: 1, max: 1000000);
        final kit = await read('catalog', productId);
        final components = kit['components'] as Map? ?? {};
        if (components.isEmpty ||
            kit['active'] == false ||
            (kit['tracking'] ?? 'none') != 'none') {
          throw const BusinessException(
            'components',
            'Bộ sản phẩm chưa có định mức hợp lệ.',
          );
        }
        if (kit['version'] != integerField(p, 'catalogVersion', min: 1)) {
          throw const BusinessException(
            'conflict',
            'Định mức đã đổi. Mở lại phiếu lắp bộ.',
          );
        }
        var total = 0;
        final lines = <Map<String, dynamic>>[];
        for (final entry in components.entries) {
          final sku = entry.key as String;
          final componentId = (await read('sku', sku))['productId'];
          final item = componentId is String
              ? await read('catalog', componentId)
              : <String, dynamic>{};
          if (componentId is! String ||
              componentId == productId ||
              item.isEmpty ||
              item['active'] == false ||
              (item['tracking'] ?? 'none') != 'none' ||
              (item['components'] as Map?)?.isNotEmpty == true) {
            throw BusinessException(
              'components',
              'Thành phần $sku không còn hợp lệ.',
            );
          }
          final quantity = integerField(
            {'quantity': (entry.value as int) * kits},
            'quantity',
            min: 1,
            max: 1000000000,
          );
          final cost = await _issue(warehouse, componentId, quantity);
          total += cost;
          lines.add({
            'productId': componentId,
            'sku': sku,
            'name': item['name'],
            'unit': item['unit'],
            'quantity': quantity,
            'cost': cost,
          });
        }
        final quantity = kits * 1000;
        await _stockChange(warehouse, productId, quantity, total);
        return {
          'warehouse': warehouse,
          'productId': productId,
          'name': kit['name'],
          'unit': kit['unit'],
          'quantity': quantity,
          'value': total,
          'catalogVersion': kit['version'],
          'lines': lines,
          'status': 'posted',
        };
      case Operation.qualityDisposition:
        _fresh(old);
        final warehouse = textField(p, 'warehouse');
        final product = textField(p, 'productId');
        final from = textField(p, 'quality');
        final action = textField(p, 'action');
        final quantity = integerField(p, 'quantity', min: 1, max: 1000000000);
        final reason = textField(p, 'reason');
        final target = switch ((from, action)) {
          ('quarantine', 'damage') => 'damaged',
          ('damaged', 'repair') => 'quarantine',
          ('quarantine' || 'damaged', 'discard' || 'supplier') => '',
          _ => throw const BusinessException(
            'quality',
            'Cách xử lý không phù hợp trạng thái tồn.',
          ),
        };
        final current = await stock(warehouse, product, quality: from);
        if (current['version'] != integerField(p, 'stockVersion', min: 1)) {
          throw const BusinessException(
            'conflict',
            'Tồn đã thay đổi. Mở lại phiếu xử lý.',
          );
        }
        if (quantity > (current['quantity'] as int)) {
          throw const BusinessException(
            'stock',
            'Không đủ hàng trong trạng thái này.',
          );
        }
        final value = await _issueValue(warehouse, product, quantity);
        final photo = p['imageUrl'] as String? ?? '';
        final url = Uri.tryParse(photo);
        if (photo.isNotEmpty &&
            (photo.length > 1000 ||
                url == null ||
                url.scheme != 'https' ||
                url.host.isEmpty ||
                url.userInfo.isNotEmpty)) {
          throw const BusinessException(
            'quality',
            'Ảnh bằng chứng cần liên kết HTTPS hợp lệ.',
          );
        }
        final reference = action == 'supplier' ? textField(p, 'reference') : '';
        if (target.isEmpty) {
          await tracking.remove(
            warehouse,
            p,
            quantity,
            from,
            status: action == 'supplier' ? 'returnedToSupplier' : 'discarded',
            referenceKey: 'dispositionId',
            referenceId: id,
          );
        } else {
          await tracking.move(
            warehouse,
            warehouse,
            p,
            fromQuality: from,
            toQuality: target,
          );
        }
        await _stockChange(
          warehouse,
          product,
          -quantity,
          -value,
          quality: from,
        );
        if (target.isNotEmpty) {
          await _stockChange(
            warehouse,
            product,
            quantity,
            value,
            quality: target,
          );
        }
        return {
          ...p,
          'name': current['name'],
          'unit': current['unit'],
          'reason': reason,
          'imageUrl': photo,
          'reference': reference,
          'toQuality': target,
          'value': value,
          'status': 'posted',
        };
      case Operation.quarantine:
      case Operation.release:
        _fresh(old);
        final warehouse = textField(p, 'warehouse'),
            product = textField(p, 'productId');
        final quantity = integerField(p, 'quantity', min: 1, max: 1000000000);
        textField(p, 'reason');
        if (op == Operation.quarantine) {
          await tracking.move(warehouse, warehouse, p, toQuality: 'quarantine');
          final value = await _issue(warehouse, product, quantity);
          await _stockChange(
            warehouse,
            product,
            quantity,
            value,
            quality: 'quarantine',
          );
        } else {
          await tracking.move(
            warehouse,
            warehouse,
            p,
            fromQuality: 'quarantine',
          );
          final current = await stock(
            warehouse,
            product,
            quality: 'quarantine',
          );
          final available = current['quantity'] as int? ?? 0;
          if (quantity > available) {
            throw const BusinessException('stock', 'Không đủ hàng cách ly.');
          }
          final value = await _issueValue(warehouse, product, quantity);
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
        String? warrantyUntil;
        if (p['productId'] != null) {
          final line = (sale['lines'] as List)
              .where((l) => l['productId'] == p['productId'])
              .firstOrNull;
          if (line == null || (line['returned'] ?? 0) == line['quantity']) {
            throw const BusinessException(
              'warranty',
              'Hàng không thuộc đơn hoặc đã trả toàn bộ.',
            );
          }
          final days = line['warrantyDays'] as int? ?? 0;
          final soldAt = DateTime.tryParse(sale['createdAt'] as String? ?? '');
          if (days > 0 && soldAt != null) {
            final until = soldAt.add(Duration(days: days));
            if (!DateTime.now().isBefore(until)) {
              throw const BusinessException(
                'warranty',
                'Sản phẩm đã hết hạn bảo hành ghi trên đơn.',
              );
            }
            warrantyUntil = until.toIso8601String();
          }
          if ((p['serial'] as String? ?? '').trim().isNotEmpty) {
            final serial = textField(p, 'serial').toUpperCase();
            final sold = await read('serial', serial);
            if (sold['saleId'] != p['saleId'] ||
                sold['status'] != 'sold' ||
                sold['productId'] != p['productId']) {
              throw const BusinessException(
                'warranty',
                'Serial không còn thuộc đơn bán này.',
              );
            }
          }
        }
        return {
          ...p,
          'customerName': sale['customerName'],
          'warrantyUntil': ?warrantyUntil,
          'status': 'received',
          'cost': 0,
        };
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
          'checking': {'repairing', 'supplier', 'rejected', 'replaced'},
          'repairing': {'completed', 'supplier', 'replaced'},
          'supplier': {'completed', 'rejected', 'replaced'},
          'completed': <String>{},
          'rejected': <String>{},
        };
        if (!(transitions[old['status']] ?? {}).contains(next)) {
          throw const BusinessException(
            'transition',
            'Bước xử lý bảo hành không hợp lệ.',
          );
        }
        final cost = integerField(p, 'cost');
        if (next != 'replaced') return {...old, 'status': next, 'cost': cost};
        if (!{StaffRole.admin, StaffRole.manager}.contains(actor.role)) {
          throw const BusinessException(
            'permission',
            'Chỉ quản lý được xác nhận đổi bảo hành.',
          );
        }
        final product = textField(old, 'productId');
        final returnId = textField(p, 'returnId');
        final replacementId = textField(p, 'replacementSaleId');
        final returned = await read('returnReceipt', returnId);
        final replacement = await read('sale', replacementId);
        final returnLine = (returned['lines'] as List? ?? [])
            .where((line) => line['productId'] == product)
            .firstOrNull;
        final replacementLine = (replacement['lines'] as List? ?? [])
            .where((line) => line['productId'] == product)
            .firstOrNull;
        final serial = (old['serial'] as String? ?? '').trim().toUpperCase();
        if (returned['saleId'] != old['saleId'] ||
            replacementId == old['saleId'] ||
            replacement['customerId'] != old['customerId'] ||
            returnLine == null ||
            replacementLine == null ||
            (replacementLine['quantity'] as int) -
                    (replacementLine['returned'] as int? ?? 0) <
                (returnLine['quantity'] as int) ||
            (serial.isNotEmpty &&
                !(returnLine['serials'] as List? ?? []).any(
                  (s) => s.toString().trim().toUpperCase() == serial,
                ))) {
          throw const BusinessException(
            'warranty',
            'Phiếu trả hoặc đơn thay thế không khớp hàng và khách bảo hành.',
          );
        }
        final returnKey = jsonEncode(['return', returnId, product]);
        final replacementKey = jsonEncode(['sale', replacementId, product]);
        if ((await read('warrantyLink', returnKey)).isNotEmpty ||
            (await read('warrantyLink', replacementKey)).isNotEmpty) {
          throw const BusinessException(
            'warranty',
            'Chứng từ đã được dùng để đổi bảo hành.',
          );
        }
        for (final key in [returnKey, replacementKey]) {
          await _write('warrantyLink', key, {'warrantyId': id});
        }
        return {
          ...old,
          'status': next,
          'cost': cost,
          'returnId': returnId,
          'replacementSaleId': replacementId,
        };
    }
  }

  Future<void> _deliveryProjection(
    String id,
    Map<String, dynamic> sale,
    String status,
  ) async {
    await _write('delivery', id, {
      'id': id,
      'driverId': sale['driverId'],
      'vehicleId': sale['vehicleId'],
      'customerId': sale['customerId'],
      'address': sale['address'] ?? '',
      'scheduledAt': sale['scheduledAt'] ?? '',
      'vehiclePlate': sale['vehiclePlate'] ?? sale['vehicleId'],
      'loadKg': sale['loadKg'] ?? 0,
      if (sale['latE6'] != null) 'latE6': sale['latE6'],
      if (sale['lngE6'] != null) 'lngE6': sale['lngE6'],
      'saleVersion': (sale['version'] as int) + 1,
      'status': status,
      'lines': [
        for (final line in sale['lines'] as List)
          {
            'productId': line['productId'],
            'name': line['name'],
            'unit': line['unit'],
            'quantity': line['quantity'],
            'delivered': line['delivered'],
          },
      ],
    });
  }

  Future<int> _available(String warehouse, String product) async {
    final physical = (await stock(warehouse, product))['quantity'] as int? ?? 0;
    final reserved =
        (await read(
              'reservedStock',
              jsonEncode([warehouse, product]),
            ))['quantity']
            as int? ??
        0;
    return physical - reserved;
  }

  int _surcharge(Map<String, dynamic> payload) => payload['surcharge'] == null
      ? 0
      : integerField(payload, 'surcharge', max: 1000000000000);
  Future<void> _depositChange(String customer, int delta) async {
    final old = await read('customerDeposit', customer),
        next = (old['balance'] as int? ?? 0) + delta;
    if (next < 0 || next > 9000000000000) {
      throw const BusinessException('deposit', 'Số dư cọc không hợp lệ.');
    }
    await _write('customerDeposit', customer, {'balance': next});
  }

  void _date(Map<String, dynamic> payload, String key) {
    final raw = payload[key] as String? ?? '';
    if (raw.isNotEmpty && DateTime.tryParse(raw) == null) {
      throw const BusinessException(
        'validation',
        'Ngày hẹn hoặc hạn nợ cần dạng năm-tháng-ngày.',
      );
    }
  }

  Future<Map<String, dynamic>> _terms(
    Product product,
    Map<String, dynamic> line,
    String customer,
  ) async {
    final catalog = await read('catalog', product.id);
    final party = await read('party', customer);
    final selected = line['saleUnit'] as String? ?? product.unit;
    final raw =
        line['saleQuantity'] as int? ?? integerField(line, 'quantity', min: 1);
    final base = ProductPolicy.baseQuantity(
      catalog,
      product.unit,
      selected,
      raw,
    );
    if (base != integerField(line, 'quantity', min: 1)) {
      throw const BusinessException('unit', 'Số lượng gốc không khớp quy đổi.');
    }
    final priceList = party['priceList'] as String? ?? '';
    final price = ProductPolicy.price(catalog, product.price, priceList, base);
    return {
      'unitPrice': price,
      'taxConfiguration': catalog['tax'],
      'saleUnit': selected,
      'saleQuantity': raw,
      'priceList': priceList,
      'unitFactor': selected == product.unit
          ? 1000
          : (catalog['units'] as Map)[selected],
    };
  }

  Future<void> _reserve(String warehouse, String product, int delta) async {
    final id = jsonEncode([warehouse, product]);
    final previous = await read('reservedStock', id);
    final next = (previous['quantity'] as int? ?? 0) + delta;
    final physical = (await stock(warehouse, product))['quantity'] as int? ?? 0;
    if (next < 0 || next > physical) {
      throw const BusinessException('stock', 'Tồn giữ chỗ không còn hợp lệ.');
    }
    await _write('reservedStock', id, {
      'warehouse': warehouse,
      'productId': product,
      'quantity': next,
    });
  }

  Future<List<Map<String, dynamic>>> _allocateDebt(
    String party,
    Map<String, dynamic> payload, {
    required bool customer,
  }) async {
    final raw = payload['allocations'];
    if (raw is! List || raw.isEmpty || raw.length > 20) {
      throw const BusinessException(
        'allocation',
        'Chọn từ 1 đến 20 chứng từ để phân bổ.',
      );
    }
    final kind = customer ? 'sale' : 'purchaseReceipt';
    final partyKey = customer ? 'customerId' : 'supplierId';
    final expected = integerField(payload, 'amount', min: 1);
    final selected = <String>{};
    final lines = <Map<String, dynamic>>[];
    var total = 0, snapshotBytes = 0;
    for (final line in raw) {
      if (line is! Map<String, dynamic>) {
        throw const BusinessException(
          'allocation',
          'Dòng phân bổ không hợp lệ.',
        );
      }
      final id = textField(line, 'documentId');
      final amount = integerField(line, 'amount', min: 1);
      if (!selected.add(id)) {
        throw const BusinessException('allocation', 'Chứng từ bị chọn trùng.');
      }
      total += amount;
      if (total > expected) {
        throw const BusinessException(
          'allocation',
          'Phân bổ vượt số tiền thanh toán.',
        );
      }
      final document = await read(kind, id);
      if (document[partyKey] != party ||
          document['version'] != integerField(line, 'version', min: 1)) {
        throw const BusinessException(
          'conflict',
          'Chứng từ đã đổi hoặc không thuộc đối tác.',
        );
      }
      snapshotBytes += utf8.encode(jsonEncode(document)).length;
      if (snapshotBytes > 250000) {
        throw const BusinessException(
          'allocation',
          'Nhóm chứng từ quá lớn. Chia thanh toán thành các phiếu nhỏ hơn.',
        );
      }
      final paid = document['paid'] as int? ?? 0;
      final remaining = customer
          ? document['debt'] as int
          : (document['total'] as int) - paid;
      if (amount > remaining) {
        throw const BusinessException(
          'overpayment',
          'Phân bổ vượt số tiền còn lại của chứng từ.',
        );
      }
      await _write(kind, id, {
        ...document,
        'paid': paid + amount,
        if (customer) 'debt': remaining - amount,
      });
      lines.add({'documentId': id, 'amount': amount});
    }
    if (total != expected) {
      throw const BusinessException(
        'allocation',
        'Tổng phân bổ phải bằng số tiền thanh toán.',
      );
    }
    return lines;
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
