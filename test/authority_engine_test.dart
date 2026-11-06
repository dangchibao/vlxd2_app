import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/authority_engine.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

void main() {
  late AppDatabase db;
  late AuthorityEngine engine;
  late String product;
  var sequence = 0;
  const manager = Actor('manager', StaffRole.manager);
  Future<Map<String, dynamic>> apply(
    Operation op,
    String id,
    Map<String, dynamic> p, {
    int version = 0,
    Actor actor = manager,
    String? key,
  }) => engine.execute(
    BusinessCommand(
      id: key ?? 'cmd-${sequence++}',
      entityId: id,
      operation: op,
      payload: p,
      expectedVersion: version,
    ),
    actor,
  );
  Map<String, dynamic> item(int q, {int cost = 10000, String? quality}) => {
    'productId': product,
    'quantity': q,
    'unitCost': cost,
    'expectedPrice': 20000,
    'quality': ?quality,
  };
  Future<void> receive(
    int q, {
    String id = 'p',
    int cost = 10000,
    String? quality,
  }) async {
    await apply(Operation.purchase, id, {
      'supplierId': 'supplier',
      'warehouse': 'main',
      'lines': [item(q, cost: cost)],
    });
    await apply(Operation.receive, id, {
      'lines': [item(q, quality: quality)],
    }, version: 1);
  }

  Future<Map<String, dynamic>> sale(int q, {String id = 's'}) =>
      apply(Operation.sale, id, {
        'warehouse': 'main',
        'customerId': 'customer',
        'discount': 0,
        'lines': [item(q)],
      });
  setUp(() async {
    sequence = 0;
    db = AppDatabase(NativeDatabase.memory());
    engine = AuthorityEngine(db);
    await db.addProduct('A', 'Gạch', 'viên', 20000);
    product = (await db.select(db.products).get()).single.id;
  });
  tearDown(() => db.close());
  test(
    'Purchase no stock; receive 60 of 100; reject excess atomically',
    () async {
      final ordered = await apply(Operation.purchase, 'p', {
        'supplierId': 'supplier',
        'warehouse': 'main',
        'lines': [
          {...item(100000), 'name': 'Tên do máy gửi'},
        ],
      });
      expect((ordered['lines'] as List).single['name'], 'Gạch');
      final legacy = {
        ...ordered,
        'lines': [
          for (final line in ordered['lines'] as List)
            Map<String, dynamic>.from(line as Map)
              ..remove('name')
              ..remove('sku')
              ..remove('unit'),
        ],
      };
      await (db.update(db.businessRecords)
            ..where((row) => row.id.equals('purchase:p')))
          .write(BusinessRecordsCompanion(payload: Value(jsonEncode(legacy))));
      expect(await engine.stock('main', product), isEmpty);
      final r = await apply(Operation.receive, 'p', {
        'lines': [item(60000)],
      }, version: 1);
      expect(r['status'], 'partial');
      final receipt = await engine.read('purchaseReceipt', 'p:2');
      final line = (receipt['lines'] as List).single;
      expect(line['name'], 'Gạch');
      expect(line['sku'], 'A');
      expect(line['unit'], 'viên');
      expect(line['total'], 600000);
      expect((await engine.stock('main', product))['quantity'], 60000);
      expect((await engine.read('payable', 'supplier'))['balance'], 600000);
      await expectLater(
        apply(Operation.receive, 'p', {
          'lines': [item(41000)],
        }, version: 2),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.stock('main', product))['quantity'], 60000);
    },
  );
  test('Pipe lengths and volume use exact scale arithmetic and round up sale units', () {
    expect(
      MaterialEstimate.pipeSticks(lengthMm: 10000, stickLengthMm: 4000),
      3,
    );
    expect(
      MaterialEstimate.pipeSticks(
        lengthMm: 8000,
        stickLengthMm: 4000,
        wasteBasisPoints: 500,
      ),
      3,
    );
    expect(
      MaterialEstimate.volumeScaled(
        lengthMm: 10000,
        widthMm: 2000,
        heightMm: 100,
      ),
      2000,
    );
    expect(
      MaterialEstimate.volumeScaled(
        lengthMm: 10000,
        widthMm: 2000,
        heightMm: 100,
        wasteBasisPoints: 500,
      ),
      2100,
    );
  });
  test('Weighted average across receipts and issue cost', () async {
    await receive(100000, id: 'p1');
    await receive(100000, id: 'p2', cost: 14000);
    final r = await sale(50000);
    expect(r['cost'], 600000);
    final stock = await engine.stock('main', product);
    expect(stock['quantity'], 150000);
    expect(stock['value'], 1800000);
  });
  test('Concurrent sales cannot issue last stock twice', () async {
    await receive(1000);
    final results = await Future.wait(
      ['s1', 's2'].map((id) async {
        try {
          await sale(1000, id: id);
          return true;
        } catch (_) {
          return false;
        }
      }),
    );
    expect(results.where((v) => v).length, 1);
    expect((await engine.stock('main', product))['quantity'], 0);
    expect((await engine.read('receivable', 'customer'))['balance'], 20000);
  });
  test(
    'Idempotency returns original receipt and rejects changed payload',
    () async {
      final p = {
        'supplierId': 'supplier',
        'warehouse': 'main',
        'lines': [item(1000)],
      };
      final first = await apply(Operation.purchase, 'p', p, key: 'once');
      expect(await apply(Operation.purchase, 'p', p, key: 'once'), first);
      await expectLater(
        apply(Operation.purchase, 'p', {
          ...p,
          'supplierId': 'other',
        }, key: 'once'),
        throwsA(isA<BusinessException>()),
      );
      expect((await db.select(db.businessEvents).get()).length, 1);
    },
  );
  test('Stale versions do not produce events', () async {
    await receive(1000);
    final before = (await db.select(db.businessEvents).get()).length;
    await expectLater(
      apply(Operation.receive, 'p', {
        'lines': [item(1000)],
      }, version: 1),
      throwsA(isA<BusinessException>()),
    );
    expect((await db.select(db.businessEvents).get()).length, before);
  });
  test('Role and mandatory password guards', () async {
    await expectLater(
      apply(
        Operation.release,
        'q',
        {},
        actor: const Actor('sales', StaffRole.sales),
      ),
      throwsA(isA<BusinessException>()),
    );
    await expectLater(
      apply(
        Operation.purchase,
        'p',
        {},
        actor: const Actor('admin', StaffRole.admin, mustChangePassword: true),
      ),
      throwsA(isA<BusinessException>()),
    );
  });
  test('Quarantine excluded from sellable; release requires manager', () async {
    await receive(10000);
    await receive(5000, id: 'bad', quality: 'quarantine');
    await expectLater(sale(11000), throwsA(isA<BusinessException>()));
    await apply(Operation.release, 'release', {
      'warehouse': 'main',
      'productId': product,
      'quantity': 2000,
      'reason': 'Đã kiểm tra',
    });
    expect((await engine.stock('main', product))['quantity'], 12000);
    expect(
      (await engine.stock('main', product, quality: 'quarantine'))['quantity'],
      3000,
    );
  });
  test('Quality states share one warehouse weighted average and value is conserved', () async {
    await receive(1000, cost: 10000);
    await receive(
      1000,
      id: 'quarantine-po',
      cost: 30000,
      quality: 'quarantine',
    );
    expect((await engine.stock('main', product))['value'], 20000);
    expect(
      (await engine.stock('main', product, quality: 'quarantine'))['value'],
      20000,
    );
    final posted = await sale(1000);
    expect(posted['cost'], 20000);
    expect((await engine.stock('main', product))['value'], 0);
    expect(
      (await engine.stock('main', product, quality: 'quarantine'))['value'],
      20000,
    );
    await apply(Operation.release, 'release-average', {
      'warehouse': 'main',
      'productId': product,
      'quantity': 1000,
      'reason': 'Đã kiểm tra',
    });
    expect((await engine.stock('main', product))['value'], 20000);
    expect(
      (await engine.stock('main', product, quality: 'quarantine'))['value'],
      0,
    );
  });
  test('Multiple payments and trips never deduct stock twice', () async {
    await receive(10000);
    await sale(10000);
    await apply(Operation.payment, 's', {
      'amount': 50000,
      'method': 'cash',
      'shiftId': 'today',
    }, version: 1);
    await apply(Operation.delivery, 's', {
      'driverId': 'd',
      'vehicleId': 'v',
      'lines': [item(6000)],
    }, version: 2);
    final paid = await apply(Operation.payment, 's', {
      'amount': 150000,
      'method': 'bank',
      'shiftId': 'today',
    }, version: 3);
    expect(paid['debt'], 0);
    final delivery = await engine.read('delivery', 's');
    expect(delivery['saleVersion'], 4);
    expect(delivery['status'], 'partial');
    final d = await apply(Operation.delivery, 's', {
      'driverId': 'd',
      'vehicleId': 'v',
      'lines': [item(4000)],
    }, version: delivery['saleVersion'] as int);
    expect(d['deliveryStatus'], 'delivered');
    expect((await engine.stock('main', product))['quantity'], 0);
    final first = await engine.read('deliveryTrip', 's:3');
    final second = await engine.read('deliveryTrip', 's:5');
    expect(first['driverId'], 'd');
    expect((first['lines'] as List).single['quantity'], 6000);
    expect((second['lines'] as List).single['quantity'], 4000);
    final expense = {
      'amount': 10000,
      'method': 'cash',
      'shiftId': 'today',
      'reason': 'Chi phí chuyến giao',
      'referenceKind': 'deliveryTrip',
    };
    await expectLater(
      apply(Operation.expense, 'bad-link', {
        ...expense,
        'referenceId': 'missing',
      }),
      throwsA(isA<BusinessException>()),
    );
    final posted = await apply(Operation.expense, 'trip-cost', {
      ...expense,
      'referenceId': 's:3',
    });
    expect(posted['referenceId'], 's:3');
    expect((await engine.read('shiftTotals', 'today'))['cashNet'], 40000);
  });
  test(
    'Shift separates cash from bank and locks further collections',
    () async {
      await receive(100000);
      await sale(100000);
      await apply(Operation.payment, 's', {
        'amount': 500000,
        'method': 'cash',
        'shiftId': 'today',
      }, version: 1);
      await apply(Operation.payment, 's', {
        'amount': 200000,
        'method': 'bank',
        'shiftId': 'today',
      }, version: 2);
      await apply(Operation.expense, 'e', {
        'amount': 100000,
        'method': 'cash',
        'shiftId': 'today',
        'reason': 'Vận chuyển',
      });
      final shift = await apply(Operation.shiftClose, 'close', {
        'shiftId': 'today',
        'opening': 1000000,
        'counted': 1350000,
        'explanation': 'Thiếu 50.000',
      });
      expect(shift['expected'], 1400000);
      expect(shift['difference'], -50000);
      expect(shift['bankNet'], 200000);
      await expectLater(
        apply(Operation.payment, 's', {
          'amount': 1,
          'method': 'cash',
          'shiftId': 'today',
        }, version: 3),
        throwsA(isA<BusinessException>()),
      );
    },
  );
  test('Warranty tracks transitions without restocking', () async {
    await receive(1000);
    await sale(1000);
    await apply(Operation.warranty, 'w', {
      'saleId': 's',
      'customerId': 'customer',
      'condition': 'Lỗi',
      'accessories': 'Dây',
    });
    await apply(Operation.warrantyUpdate, 'w', {
      'status': 'checking',
      'cost': 0,
    }, version: 1);
    await expectLater(
      apply(Operation.warrantyUpdate, 'w', {
        'status': 'completed',
        'cost': 0,
      }, version: 2),
      throwsA(isA<BusinessException>()),
    );
    expect((await engine.stock('main', product))['quantity'], 0);
  });
  test('Exact material rounding and safe integer boundary', () {
    expect(
      MaterialEstimate.tileBoxes(
        areaSquareMm: 10000000,
        tileWidthMm: 600,
        tileHeightMm: 600,
        tilesPerBox: 4,
      ),
      8,
    );
    expect(roundedRatio(100, 1, 3), 33);
    expect(
      () => roundedRatio(9000000000000, 1000000000, 1),
      throwsA(isA<BusinessException>()),
    );
  });
  test('Transfer preserves inventory value across warehouses', () async {
    await receive(10000);
    await apply(Operation.transfer, 't', {
      'fromWarehouse': 'main',
      'toWarehouse': 'other',
      'lines': [item(4000)],
    });
    expect((await engine.stock('main', product))['value'], 60000);
    expect((await engine.stock('other', product))['value'], 40000);
  });
  test(
    'Return reduces debt first, quarantines goods, refund cannot duplicate',
    () async {
      await receive(10000);
      await sale(10000);
      await apply(Operation.payment, 's', {
        'amount': 150000,
        'method': 'cash',
        'shiftId': 'day',
      }, version: 1);
      final returned = await apply(Operation.returnSale, 's', {
        'reason': 'Đổi hàng',
        'lines': [item(6000)],
      }, version: 2);
      expect(returned['debt'], 0);
      expect(returned['refundDue'], 70000);
      expect(
        (await engine.stock(
          'main',
          product,
          quality: 'quarantine',
        ))['quantity'],
        6000,
      );
      expect((await engine.stock('main', product))['quantity'], 0);
      final payload = {
        'amount': 70000,
        'method': 'cash',
        'shiftId': 'day',
        'reason': 'Hoàn trả hàng',
      };
      await apply(
        Operation.refund,
        's',
        payload,
        version: 3,
        key: 'refund-once',
      );
      await apply(
        Operation.refund,
        's',
        payload,
        version: 3,
        key: 'refund-once',
      );
      expect((await engine.read('sale', 's'))['refundDue'], 0);
      await expectLater(
        apply(Operation.refund, 's', payload, version: 4),
        throwsA(isA<BusinessException>()),
      );
    },
  );
  test('Supplier payment decreases payable without changing stock', () async {
    await receive(10000);
    final payable = await engine.read('payable', 'supplier');
    await apply(Operation.supplierPayment, 'supplier', {
      'amount': 40000,
      'method': 'bank',
      'shiftId': 'day',
    }, version: payable['version'] as int);
    expect((await engine.read('payable', 'supplier'))['balance'], 60000);
    expect((await engine.stock('main', product))['quantity'], 10000);
  });
  test(
    'Changed catalog price rejects stale sale without touching stock',
    () async {
      await receive(1000);
      await expectLater(
        apply(Operation.sale, 'stale', {
          'warehouse': 'main',
          'customerId': 'customer',
          'discount': 0,
          'lines': [
            {...item(1000), 'expectedPrice': 19000},
          ],
        }),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.stock('main', product))['quantity'], 1000);
    },
  );
  test(
    'Quote conversion preserves agreed price and cannot issue stock twice',
    () async {
      await receive(1000);
      await apply(Operation.quote, 'quote', {
        'customerId': 'customer',
        'discount': 1000,
        'lines': [item(1000)],
      });
      await apply(Operation.catalog, product, {
        'sku': 'A',
        'name': 'Tên mới',
        'unit': 'viên',
        'price': 30000,
      });
      final converted = await apply(
        Operation.quoteToSale,
        'quote',
        {'saleId': 'from-quote', 'warehouse': 'main'},
        version: 1,
        actor: const Actor('seller', StaffRole.sales),
      );
      expect((converted['saleDocument'] as Map)['total'], 19000);
      expect(
        ((converted['saleDocument'] as Map)['lines'] as List).single['name'],
        'Gạch',
      );
      expect((await engine.stock('main', product))['quantity'], 0);
      await expectLater(
        apply(Operation.quoteToSale, 'quote', {
          'saleId': 'duplicate',
          'warehouse': 'main',
        }, version: 2),
        throwsA(isA<BusinessException>()),
      );
      expect(await engine.read('sale', 'duplicate'), isEmpty);
    },
  );
  test('Quote revisions retain immutable historical snapshots', () async {
    await apply(Operation.quote, 'quote', {
      'customerId': 'customer',
      'discount': 0,
      'lines': [item(1000)],
    });
    await apply(Operation.quote, 'quote', {
      'customerId': 'customer',
      'discount': 0,
      'lines': [item(2000)],
    }, version: 1);
    expect((await engine.read('quoteVersion', 'quote:1'))['total'], 20000);
    expect((await engine.read('quoteVersion', 'quote:2'))['total'], 40000);
  });
}
