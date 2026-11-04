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
