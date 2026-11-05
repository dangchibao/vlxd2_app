import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/authority_engine.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

void main() {
  late AppDatabase db;
  late AuthorityEngine engine;
  var sequence = 0;
  const manager = Actor('manager', StaffRole.manager);
  const warehouse = Actor('warehouse', StaffRole.warehouse);

  Future<Map<String, dynamic>> run(
    Operation operation,
    String entityId,
    Map<String, dynamic> payload, {
    int version = 0,
    String? commandId,
    Actor actor = manager,
  }) => engine.execute(
    BusinessCommand(
      id: commandId ?? 'test-${sequence++}',
      entityId: entityId,
      operation: operation,
      payload: payload,
      expectedVersion: version,
    ),
    actor,
  );
  Future<void> catalog(
    String sku, {
    String tracking = 'none',
    int days = 0,
    Map<String, int> components = const {},
  }) => run(Operation.catalog, sku, {
    'sku': sku,
    'name': sku,
    'unit': 'cái',
    'price': 20000,
    'tracking': tracking,
    'components': components,
    'warrantyDays': days,
  });
  Map<String, dynamic> line(
    String sku,
    int quantity, {
    List<String>? serials,
  }) => {
    'productId': sku,
    'quantity': quantity,
    'unitCost': 10000,
    'expectedPrice': 20000,
    'serials': ?serials,
  };
  Future<void> receive(List<Map<String, dynamic>> lines) async {
    await run(Operation.purchase, 'po', {
      'supplierId': 's',
      'warehouse': 'main',
      'lines': lines,
    });
    await run(Operation.receive, 'po', {'lines': lines}, version: 1);
  }

  Future<void> sell(String id, Map<String, dynamic> detail) =>
      run(Operation.sale, id, {
        'customerId': 'customer',
        'warehouse': 'main',
        'discount': 0,
        'lines': [detail],
      });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    engine = AuthorityEngine(db);
  });
  tearDown(() => db.close());

  test(
    'Assembly rolls back on a missing component and conserves stock value',
    () async {
      await catalog('A');
      await catalog('B');
      await catalog('KIT', components: {'A': 2000, 'B': 1000});
      await receive([line('A', 8000), line('B', 2000)]);
      final payload = {
        'productId': 'KIT',
        'warehouse': 'main',
        'catalogVersion': 1,
      };
      await expectLater(
        run(Operation.assemble, 'fail', {...payload, 'kits': 3}),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.stock('main', 'A'))['quantity'], 8000);
      expect(await engine.stock('main', 'KIT'), isEmpty);
      final command = {...payload, 'kits': 2};
      final posted = await run(
        Operation.assemble,
        'ok',
        command,
        commandId: 'kit-1',
      );
      expect(
        await run(Operation.assemble, 'ok', command, commandId: 'kit-1'),
        posted,
      );
      expect((await engine.stock('main', 'KIT'))['value'], 60000);
      expect((await engine.stock('main', 'A'))['value'], 40000);
      expect((await engine.stock('main', 'B'))['quantity'], 0);
    },
  );

  test('Assembly consumes exact lots and serials, rolls back on duplicate output, and keeps cost', () async {
    await catalog('TILE', tracking: 'lot');
    await catalog('DEVICE', tracking: 'serial');
    await catalog(
      'KIT',
      tracking: 'serial',
      components: {'TILE': 2000, 'DEVICE': 1000},
    );
    final lots = [
      {'lotId': 'A', 'quantity': 3000},
      {'lotId': 'B', 'quantity': 3000},
    ];
    await receive([
      {...line('TILE', 6000), 'lotAllocations': lots},
      line('DEVICE', 3000, serials: ['D1', 'D2', 'D3']),
    ]);
    final command = {
      'productId': 'KIT',
      'warehouse': 'main',
      'catalogVersion': 1,
      'kits': 2,
      'componentTracking': [
        {
          'sku': 'TILE',
          'lotAllocations': [
            {'lotId': 'A', 'quantity': 1000},
            {'lotId': 'B', 'quantity': 3000},
          ],
        },
        {
          'sku': 'DEVICE',
          'serials': ['d1', 'd2'],
        },
      ],
    };
    Future<int?> lotQuantity(String product, String lot) async =>
        (await engine.read(
              'lotStock',
              engine.tracking.positionId('main', product, lot, 'good'),
            ))['quantity']
            as int?;
    await expectLater(
      run(Operation.assemble, 'collision', {
        ...command,
        'outputTracking': {
          'serials': ['KIT-1', 'D3'],
        },
      }),
      throwsA(isA<BusinessException>().having((e) => e.code, 'code', 'serial')),
    );
    expect(await lotQuantity('TILE', 'A'), 3000);
    expect(await lotQuantity('TILE', 'B'), 3000);
    expect((await engine.read('serial', 'D1'))['status'], 'available');
    expect(await engine.read('serial', 'KIT-1'), isEmpty);
    expect(await engine.stock('main', 'KIT'), isEmpty);
    expect((await engine.stock('main', 'TILE'))['value'], 60000);
    final posted = await run(Operation.assemble, 'success', {
      ...command,
      'outputTracking': {
        'serials': ['kit-1', 'kit-2'],
      },
    });
    expect(posted['serials'], ['KIT-1', 'KIT-2']);
    expect(posted['value'], 60000);
    expect(await lotQuantity('TILE', 'A'), 2000);
    expect(await lotQuantity('TILE', 'B'), 0);
    final consumed = await engine.read('serial', 'D1');
    expect(consumed['status'], 'assembled');
    expect(consumed['consumedByAssemblyId'], 'success');
    expect((await engine.read('serial', 'KIT-1'))['assemblyId'], 'success');
    await expectLater(
      sell('old-part', line('DEVICE', 1000, serials: ['D1'])),
      throwsA(isA<BusinessException>()),
    );
    await sell('kit-sale', line('KIT', 1000, serials: ['KIT-1']));
    expect((await engine.stock('main', 'KIT'))['value'], 30000);
  });

  test(
    'Assembly creates sellable finished lots with their color and provenance',
    () async {
      await catalog('PART');
      await catalog('KIT', tracking: 'lot', components: {'PART': 1500});
      await receive([line('PART', 3000)]);
      final payload = {
        'productId': 'KIT',
        'warehouse': 'main',
        'catalogVersion': 1,
        'kits': 2,
      };
      await expectLater(
        run(Operation.assemble, 'missing-lot', payload),
        throwsA(isA<BusinessException>()),
      );
      final posted = await run(Operation.assemble, 'lot-assembly', {
        ...payload,
        'outputTracking': {'lotId': 'NEW', 'colorCode': 'XAM'},
      });
      expect(posted['lotAllocations'], [
        {'lotId': 'NEW', 'colorCode': 'XAM', 'quantity': 2000},
      ]);
      expect(
        (await engine.read('lot', '["KIT","NEW"]'))['assemblyId'],
        'lot-assembly',
      );
      await sell('kit-sale', {
        ...line('KIT', 1000),
        'lotId': 'NEW',
        'colorCode': 'XAM',
      });
      expect((await engine.stock('main', 'KIT'))['value'], 15000);
    },
  );

  test('Quality disposition tracks serials and rejects stale or unauthorized writes', () async {
    await catalog('SER', tracking: 'serial');
    await receive([
      line('SER', 1000, serials: ['ABC']),
    ]);
    final payload = {
      ...line('SER', 1000, serials: ['ABC']),
      'warehouse': 'main',
      'reason': 'Hư hỏng',
    };
    await run(Operation.quarantine, 'q', payload);
    final quarantined = await engine.stock(
      'main',
      'SER',
      quality: 'quarantine',
    );
    final damage = {
      ...payload,
      'quality': 'quarantine',
      'action': 'damage',
      'stockVersion': quarantined['version'],
    };
    await expectLater(
      run(Operation.qualityDisposition, 'denied', damage, actor: warehouse),
      throwsA(isA<BusinessException>()),
    );
    await run(Operation.qualityDisposition, 'damaged', damage);
    await expectLater(
      run(Operation.qualityDisposition, 'stale', damage),
      throwsA(isA<BusinessException>()),
    );
    final damaged = await engine.stock('main', 'SER', quality: 'damaged');
    expect(damaged['value'], 10000);
    await run(Operation.qualityDisposition, 'discarded', {
      ...payload,
      'quality': 'damaged',
      'action': 'discard',
      'stockVersion': damaged['version'],
    });
    expect(
      (await engine.stock('main', 'SER', quality: 'damaged'))['quantity'],
      0,
    );
    expect((await engine.read('serial', 'ABC'))['status'], 'discarded');
    expect((await engine.stock('main', 'SER'))['quantity'], 0);
  });

  test(
    'Warranty uses the sale term and links valid replacements once',
    () async {
      await catalog('ITEM', days: 30);
      await receive([line('ITEM', 4000)]);
      await sell('original', line('ITEM', 1000));
      final request = {
        'saleId': 'original',
        'customerId': 'customer',
        'productId': 'ITEM',
        'condition': 'Lỗi',
        'accessories': 'Đủ',
      };
      for (final id in ['w1', 'w2']) {
        final claim = await run(Operation.warranty, id, request);
        expect(claim['warrantyUntil'], isNotNull);
        await run(Operation.warrantyUpdate, id, {
          'status': 'checking',
          'cost': 0,
        }, version: 1);
      }
      await run(Operation.returnSale, 'original', {
        'reason': 'Đổi',
        'lines': [line('ITEM', 1000)],
      }, version: 1);
      await sell('new', line('ITEM', 1000));
      final replacement = {
        'status': 'replaced',
        'returnId': 'original:1',
        'replacementSaleId': 'new',
        'cost': 0,
      };
      await expectLater(
        run(
          Operation.warrantyUpdate,
          'w1',
          replacement,
          version: 2,
          actor: warehouse,
        ),
        throwsA(isA<BusinessException>()),
      );
      await run(Operation.warrantyUpdate, 'w1', replacement, version: 2);
      await expectLater(
        run(Operation.warrantyUpdate, 'w2', replacement, version: 2),
        throwsA(isA<BusinessException>()),
      );
      expect(
        (await engine.stock('main', 'ITEM', quality: 'quarantine'))['quantity'],
        1000,
      );
      expect((await engine.stock('main', 'ITEM'))['quantity'], 2000);
    },
  );
}
