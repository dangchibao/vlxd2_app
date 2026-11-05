import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/authority_engine.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

void main() {
  late AppDatabase db;
  late AuthorityEngine engine;
  var sequence = 0;
  const actor = Actor('manager', StaffRole.manager);
  Future<Map<String, dynamic>> run(
    Operation op,
    String id,
    Map<String, dynamic> payload, [
    int version = 0,
  ]) => engine.execute(
    BusinessCommand(
      id: 'cmd-${sequence++}',
      entityId: id,
      operation: op,
      payload: payload,
      expectedVersion: version,
    ),
    actor,
  );
  Future<void> catalog(String tracking) => run(Operation.catalog, 'p', {
    'sku': 'P',
    'name': 'Thiết bị',
    'unit': 'cái',
    'price': 20000,
    'tracking': tracking,
  });
  Map<String, dynamic> line(
    int q, {
    String? lot,
    List<String>? serials,
    String color = '',
  }) => {
    'productId': 'p',
    'quantity': q,
    'unitCost': 10000,
    'expectedPrice': 20000,
    'lotId': lot,
    'serials': serials,
    'colorCode': color,
  };
  Future<void> receive(
    Map<String, dynamic> detail, {
    String purchase = 'po',
  }) async {
    await run(Operation.purchase, purchase, {
      'warehouse': 'main',
      'supplierId': 'ncc',
      'lines': [detail],
    });
    await run(Operation.receive, purchase, {
      'lines': [detail],
    }, 1);
  }

  Future<Map<String, dynamic>> sell(
    Map<String, dynamic> detail, [
    String id = 'sale',
  ]) => run(Operation.sale, id, {
    'warehouse': 'main',
    'customerId': 'c',
    'discount': 0,
    'lines': [detail],
  });
  Map<String, dynamic> split(int total, Map<String, int> lots) => {
    ...line(total),
    'lotAllocations': [
      for (final lot in lots.entries) {'lotId': lot.key, 'quantity': lot.value},
    ],
  };
  Future<int?> lotQuantity(
    String lot, {
    String warehouse = 'main',
    String quality = 'good',
  }) async =>
      (await engine.read(
            'lotStock',
            engine.tracking.positionId(warehouse, 'p', lot, quality),
          ))['quantity']
          as int?;
  final lotError = throwsA(
    isA<BusinessException>().having((e) => e.code, 'code', 'lot'),
  );

  setUp(() {
    sequence = 0;
    db = AppDatabase(NativeDatabase.memory());
    engine = AuthorityEngine(db);
  });
  tearDown(() => db.close());
  test(
    'Lots reject wrong color or insufficient selected lot atomically',
    () async {
      await catalog('lot');
      await receive(line(3000, lot: 'L1', color: 'RED'));
      await receive(
        line(4000, lot: 'L2', color: 'BLUE'),
        purchase: 'po2',
      );
      await expectLater(
        sell(line(4000, lot: 'L1', color: 'RED')),
        throwsA(isA<BusinessException>()),
      );
      await expectLater(
        sell(line(1000, lot: 'L1', color: 'BLUE')),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.stock('main', 'p'))['quantity'], 7000);
      await sell(line(1500, lot: 'L1', color: 'RED'));
      await run(Operation.returnSale, 'sale', {
        'reason': 'Bể',
        'lines': [line(500)],
      }, 1);
      final position = engine.tracking.positionId(
        'main',
        'p',
        'L1',
        'quarantine',
      );
      expect((await engine.read('lotStock', position))['quantity'], 500);
      expect(
        (await engine.stock('main', 'p', quality: 'quarantine'))['value'],
        5000,
      );
    },
  );
  test('Serial receipt, issue, return and quarantine release prevent duplicate movements', () async {
    await catalog('serial');
    await receive(line(2000, serials: ['SN1', 'SN2']));
    await expectLater(
      receive(line(1000, serials: ['sn1']), purchase: 'duplicate'),
      throwsA(isA<BusinessException>()),
    );
    expect((await engine.stock('main', 'p'))['quantity'], 2000);
    await sell(line(1000, serials: ['sn1']));
    await expectLater(
      sell(line(1000, serials: ['SN1']), 'twice'),
      throwsA(isA<BusinessException>()),
    );
    await expectLater(
      run(Operation.returnSale, 'sale', {
        'reason': 'Lỗi',
        'lines': [
          line(1000, serials: ['SN2']),
        ],
      }, 1),
      throwsA(isA<BusinessException>()),
    );
    await run(Operation.returnSale, 'sale', {
      'reason': 'Lỗi',
      'lines': [
        line(1000, serials: ['SN1']),
      ],
    }, 1);
    expect((await engine.read('serial', 'SN1'))['quality'], 'quarantine');
    await expectLater(
      sell(line(1000, serials: ['SN1']), 'bad'),
      throwsA(isA<BusinessException>()),
    );
    await run(Operation.release, 'release', {
      ...line(1000, serials: ['SN1']),
      'warehouse': 'main',
      'reason': 'Đã sửa',
    });
    await sell(line(1000, serials: ['SN1']), 'new-sale');
    expect((await engine.read('serial', 'SN1'))['saleId'], 'new-sale');
  });
  test('Split receipt and sale retain value, confirm color, and cap returns per lot', () async {
    await catalog('lot');
    await receive({
      ...split(5000, {'L1': 3000, 'L2': 2000}),
      'lotAllocations': [
        {'lotId': 'L1', 'quantity': 3000, 'colorCode': 'BE'},
        {'lotId': 'L2', 'quantity': 2000, 'colorCode': 'XAM'},
      ],
    });
    expect(await lotQuantity('L1'), 3000);
    expect(await lotQuantity('L2'), 2000);
    expect((await engine.stock('main', 'p'))['value'], 50000);
    expect((await engine.read('payable', 'ncc'))['balance'], 50000);

    await expectLater(sell(split(3000, {'L1': 1000, 'L2': 3000})), lotError);
    await expectLater(sell(split(4000, {'L1': 1000, 'L2': 3000})), lotError);
    await expectLater(sell(split(3000, {'L1': 2000, 'L2': 1000})), lotError);
    expect(await engine.read('sale', 'sale'), isEmpty);
    expect(await lotQuantity('L1'), 3000);
    expect(await lotQuantity('L2'), 2000);

    final sale = await run(Operation.sale, 'sale', {
      'warehouse': 'main',
      'customerId': 'c',
      'discount': 0,
      'allowMixedLotColors': true,
      'lines': [
        split(3000, {'L1': 2000, 'L2': 1000}),
      ],
    });
    expect(sale['total'], 60000);
    expect((sale['lines'] as List).single['lotAllocations'], [
      {'lotId': 'L1', 'quantity': 2000, 'colorCode': 'BE'},
      {'lotId': 'L2', 'quantity': 1000, 'colorCode': 'XAM'},
    ]);
    Future<Map<String, dynamic>> returnLine(
      Map<String, dynamic> l,
      int version,
    ) => run(Operation.returnSale, 'sale', {
      'reason': 'Bể',
      'lines': [l],
    }, version);
    await expectLater(returnLine(line(1000), 1), lotError);
    await expectLater(returnLine(split(2000, {'L2': 2000}), 1), lotError);
    await returnLine(split(1500, {'L1': 500, 'L2': 1000}), 1);
    await expectLater(returnLine(split(1000, {'L2': 1000}), 2), lotError);
    final updated = await returnLine(line(1500, lot: 'L1'), 2);
    expect((updated['lines'] as List).single['returnedByLot'], [
      {'lotId': 'L1', 'quantity': 2000},
      {'lotId': 'L2', 'quantity': 1000},
    ]);
    expect(await lotQuantity('L1', quality: 'quarantine'), 2000);
    expect(await lotQuantity('L2', quality: 'quarantine'), 1000);
    expect(
      (await engine.stock('main', 'p', quality: 'quarantine'))['value'],
      30000,
    );
  });

  test(
    'Split transfer rolls back if the second lot is short, then moves both',
    () async {
      await catalog('lot');
      await receive(split(5000, {'L1': 3000, 'L2': 2000}));
      Future<Map<String, dynamic>> transfer(Map<String, dynamic> l) =>
          run(Operation.transfer, 'transfer', {
            'fromWarehouse': 'main',
            'toWarehouse': 'other',
            'lines': [l],
          });
      await expectLater(
        transfer(split(4000, {'L1': 1000, 'L2': 3000})),
        lotError,
      );
      expect(await lotQuantity('L1'), 3000);
      expect(await lotQuantity('L1', warehouse: 'other'), isNull);
      await transfer(split(3000, {'L1': 1000, 'L2': 2000}));
      expect(await lotQuantity('L1', warehouse: 'other'), 1000);
      expect(await lotQuantity('L2', warehouse: 'other'), 2000);
      expect((await engine.stock('main', 'p'))['value'], 20000);
      expect((await engine.stock('other', 'p'))['value'], 30000);
    },
  );

  test(
    'Partial reservation uses the approved quantities of available lots',
    () async {
      await catalog('lot');
      await receive(split(5000, {'L1': 3000, 'L2': 2000}));
      await run(Operation.reservation, 'reserve', {
        'warehouse': 'main',
        'customerId': 'c',
        'discount': 0,
        'lines': [
          split(6000, {'L1': 4000, 'L2': 2000}),
        ],
      });
      await run(Operation.approveReservation, 'reserve', {
        'decision': 'partial',
        'reason': 'Giao phần có sẵn',
      }, 1);
      await run(Operation.fulfillReservation, 'reserve', {
        'saleId': 'sale',
        'partial': true,
      }, 2);
      final sale = await engine.read('sale', 'sale');
      expect((sale['lines'] as List).single['lotAllocations'], [
        {'lotId': 'L1', 'quantity': 3000, 'colorCode': ''},
        {'lotId': 'L2', 'quantity': 2000, 'colorCode': ''},
      ]);
      expect((await engine.stock('main', 'p'))['quantity'], 0);
    },
  );

  test('Serial transfer preserves valuation and warehouse ownership', () async {
    await catalog('serial');
    await receive(line(1000, serials: ['SN1']));
    await run(Operation.transfer, 'transfer', {
      'fromWarehouse': 'main',
      'toWarehouse': 'other',
      'lines': [
        line(1000, serials: ['SN1']),
      ],
    });
    expect((await engine.read('serial', 'SN1'))['warehouse'], 'other');
    expect((await engine.stock('main', 'p'))['value'], 0);
    expect((await engine.stock('other', 'p'))['value'], 10000);
    await expectLater(
      sell(line(1000, serials: ['SN1'])),
      throwsA(isA<BusinessException>()),
    );
  });
}
