import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/authority_engine.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/xlsx_catalog.dart';
import 'package:vlxd_bay_hai/data/xlsx_parties.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/domain/electronic_invoice.dart';
import 'package:vlxd_bay_hai/domain/store_alerts.dart';

void main() {
  late AppDatabase db;
  late AuthorityEngine engine;
  var sequence = 0;
  const manager = Actor('m', StaffRole.manager),
      admin = Actor('a', StaffRole.admin);
  Future<Map<String, dynamic>> run(
    Operation op,
    String id,
    Map<String, dynamic> p, {
    int version = 0,
    Actor actor = manager,
  }) => engine.execute(
    BusinessCommand(
      id: 'cmd${sequence++}',
      entityId: id,
      operation: op,
      payload: p,
      expectedVersion: version,
    ),
    actor,
  );
  Map<String, dynamic> line(int q, {int price = 100}) => {
    'productId': 'p',
    'quantity': q,
    'unitCost': 60,
    'expectedPrice': price,
  };
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    engine = AuthorityEngine(db);
    sequence = 0;
    await run(Operation.catalog, 'p', {
      'sku': 'P',
      'name': 'Gạch',
      'unit': 'viên',
      'price': 100,
      'units': {'thùng': 12000},
      'priceLists': {'Đại lý': 90},
      'quantityTiers': [
        {'priceList': 'Đại lý', 'minimum': 20000, 'price': 80},
      ],
    });
    await run(Operation.purchase, 'po', {
      'warehouse': 'main',
      'supplierId': 'ncc',
      'lines': [line(100000)],
    });
    await run(Operation.receive, 'po', {
      'lines': [line(100000)],
    }, version: 1);
  });
  tearDown(() => db.close());
  test('Station print request can be claimed once and only its owner can reconcile', () async {
    await run(Operation.sale, 's', {
      'warehouse': 'main',
      'customerId': 'c',
      'discount': 0,
      'lines': [line(1000)],
    });
    await run(Operation.printRequest, 'print', {
      'documentKind': 'sale',
      'documentId': 's',
      'documentVersion': 1,
    });
    await run(Operation.printClaim, 'print', {
      'claimToken': 'device-one',
    }, version: 1);
    await expectLater(
      run(Operation.printClaim, 'print', {
        'claimToken': 'device-two',
      }, version: 1),
      throwsA(isA<BusinessException>()),
    );
    await expectLater(
      run(Operation.printResult, 'print', {
        'claimToken': 'device-two',
        'status': 'sent_to_system',
        'note': 'x',
      }, version: 2),
      throwsA(isA<BusinessException>()),
    );
    final result = await run(Operation.printResult, 'print', {
      'claimToken': 'device-one',
      'status': 'unknown',
      'note': 'Mất điện sau gửi in, cần kiểm tra giấy',
    }, version: 2);
    expect(result['status'], 'unknown');
    await expectLater(
      run(Operation.printClaim, 'print', {'claimToken': 'retry'}, version: 3),
      throwsA(isA<BusinessException>()),
    );
  });
  test(
    'Freight charged by supplier becomes received cost and supplier payable',
    () async {
      await run(Operation.purchase, 'fees', {
        'warehouse': 'main',
        'supplierId': 'ncc',
        'lines': [line(1000)],
      });
      await run(Operation.receive, 'fees', {
        'lines': [line(1000)],
        'purchaseCosts': 40,
      }, version: 1);
      expect((await engine.stock('main', 'p'))['value'], 6100);
      expect((await engine.read('payable', 'ncc'))['balance'], 6100);
    },
  );
  test('Returns refund goods net of discount while delivery surcharge stays explicit', () async {
    await run(Operation.sale, 's', {
      'warehouse': 'main',
      'customerId': 'c',
      'discount': 0,
      'surcharge': 50,
      'lines': [line(1000)],
    });
    final result = await run(Operation.returnSale, 's', {
      'reason': 'Trả hàng',
      'lines': [line(1000)],
    }, version: 1);
    expect(result['total'], 150);
    expect(result['returnedValue'], 100);
    expect(result['debt'], 50);
  });
  test(
    'Server applies customer tiers and verifies conversion before stock issue',
    () async {
      await run(Operation.party, 'customer', {
        'name': 'Đại lý A',
        'type': 'customer',
        'priceList': 'Đại lý',
      });
      final sale = await run(Operation.sale, 's', {
        'warehouse': 'main',
        'customerId': 'customer',
        'discount': 0,
        'lines': [
          {
            ...line(24000, price: 80),
            'saleUnit': 'thùng',
            'saleQuantity': 2000,
          },
        ],
      });
      expect(sale['total'], 1920);
      expect(sale['cost'], 1440);
      await expectLater(
        run(Operation.sale, 'bad', {
          'warehouse': 'main',
          'customerId': 'customer',
          'discount': 0,
          'lines': [
            {
              ...line(1000, price: 90),
              'saleUnit': 'thùng',
              'saleQuantity': 2000,
            },
          ],
        }),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.stock('main', 'p'))['quantity'], 76000);
      await expectLater(
        run(
          Operation.party,
          'customer',
          {'name': 'Đại lý A', 'type': 'customer', 'priceList': 'Fake'},
          version: 1,
          actor: const Actor('seller', StaffRole.sales),
        ),
        throwsA(isA<BusinessException>()),
      );
    },
  );
  test(
    'Count changes valuation exactly and rejects stale stock snapshots',
    () async {
      final stock = await engine.stock('main', 'p');
      final count = {
        'warehouse': 'main',
        'productId': 'p',
        'quality': 'good',
        'stockVersion': stock['version'],
        'counted': 90000,
        'reason': 'Đếm thiếu',
      };
      await run(Operation.inventoryCount, 'count', count);
      expect((await engine.stock('main', 'p'))['value'], 5400);
      await expectLater(
        run(Operation.inventoryCount, 'stale', count),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.stock('main', 'p'))['quantity'], 90000);
    },
  );
  test('Count cannot reduce below existing reservations', () async {
    await run(Operation.reservation, 'r', {
      'warehouse': 'main',
      'customerId': 'c',
      'discount': 0,
      'lines': [line(80000)],
    });
    final stock = await engine.stock('main', 'p');
    await expectLater(
      run(Operation.inventoryCount, 'count', {
        'warehouse': 'main',
        'productId': 'p',
        'quality': 'good',
        'stockVersion': stock['version'],
        'counted': 70000,
        'reason': 'Thiếu',
      }),
      throwsA(isA<BusinessException>()),
    );
    expect((await engine.stock('main', 'p'))['quantity'], 100000);
  });
  test('Staff changes preserve forced password flag and disallow manager escalation', () async {
    await db
        .into(db.businessRecords)
        .insert(
          BusinessRecordsCompanion.insert(
            id: 'staff:employee',
            kind: 'staff',
            payload: jsonEncode({
              'role': 'sales',
              'active': true,
              'mustChangePassword': true,
            }),
            version: 1,
          ),
        );
    final payload = {
      'role': 'warehouse',
      'active': false,
      'displayName': 'Kho',
      'mustChangePassword': false,
    };
    await expectLater(
      run(Operation.staff, 'employee', payload, version: 1),
      throwsA(isA<BusinessException>()),
    );
    final result = await run(
      Operation.staff,
      'employee',
      payload,
      version: 1,
      actor: admin,
    );
    expect(result['mustChangePassword'], true);
    expect(result['active'], false);
  });
  test(
    'Delivery projection has schedule and location but no sales price',
    () async {
      await run(Operation.sale, 's', {
        'warehouse': 'main',
        'customerId': 'c',
        'discount': 0,
        'lines': [line(1000)],
      });
      await run(Operation.vehicle, 'truck', {
        'name': 'Xe tải',
        'plate': 'AB123',
        'capacityKg': 1000,
      });
      await expectLater(
        run(Operation.assignDelivery, 's', {
          'driverId': 'd',
          'vehicleId': 'truck',
          'loadKg': 1100,
        }, version: 1),
        throwsA(isA<BusinessException>()),
      );
      await run(Operation.assignDelivery, 's', {
        'driverId': 'd',
        'vehicleId': 'truck',
        'loadKg': 500,
        'scheduledAt': '2026-11-06T08:30',
        'latE6': 10776000,
        'lngE6': 106700000,
        'address': 'Địa chỉ giao',
      }, version: 1);
      final delivery = await engine.read('delivery', 's');
      expect(delivery['saleVersion'], 2);
      expect(delivery['latE6'], 10776000);
      expect(delivery['scheduledAt'], '2026-11-06T08:30');
      expect(jsonEncode(delivery), isNot(contains('unitPrice')));
      await expectLater(
        run(
          Operation.delivery,
          's',
          {
            'driverId': 'other',
            'vehicleId': 'truck',
            'lines': [line(1000)],
          },
          version: 2,
          actor: const Actor('other', StaffRole.driver),
        ),
        throwsA(isA<BusinessException>()),
      );
    },
  );
  test('Party workbook previews duplicates and never evaluates formulas', () {
    final bytes = XlsxCatalog().table(XlsxParties.headers, [
      ['C1', 'Khách', 'customer', '0901', 'Địa chỉ', ''],
      ['C1', 'Khác', 'supplier', '', '', ''],
    ]);
    final rows = XlsxParties().preview(bytes, {});
    expect(rows.first.payload['phone'], '0901');
    expect(rows.first.errors, isEmpty);
    expect(rows.last.errors, isNotEmpty);
  });
  test(
    'Alerts are deduplicated and invoice preparation never invents tax',
    () async {
      final sale = await run(Operation.sale, 's', {
        'warehouse': 'main',
        'customerId': 'c',
        'discount': 0,
        'dueAt': '2020-01-01',
        'lines': [line(1000)],
      });
      final records = await db.select(db.businessRecords).get();
      final alerts = StoreAlerts.derive(
        [...records, ...records],
        [],
        DateTime.now(),
      );
      expect(alerts.map((a) => a.id).toSet().length, alerts.length);
      final invoice = ElectronicInvoiceDraft.fromSale(
        sale,
        buyer: {'name': 'Khách'},
        taxByProduct: {},
      );
      expect(invoice.readyForProviderValidation, false);
      expect(invoice.lines.single['taxConfiguration'], null);
    },
  );
}
