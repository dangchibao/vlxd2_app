import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/authority_engine.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/domain/financial_report.dart';

void main() {
  late AppDatabase db;
  late AuthorityEngine engine;
  var sequence = 0;
  const manager = Actor('m', StaffRole.manager),
      sales = Actor('s', StaffRole.sales);
  Map<String, dynamic> line(int q) => {
    'productId': 'p',
    'quantity': q,
    'expectedPrice': 100,
    'unitCost': 60,
  };
  Map<String, dynamic> order(int q) => {
    'warehouse': 'main',
    'customerId': 'c',
    'discount': 0,
    'lines': [line(q)],
  };
  Future<Map<String, dynamic>> run(
    Operation op,
    String id,
    Map<String, dynamic> p, {
    int version = 0,
    Actor actor = manager,
  }) => engine.execute(
    BusinessCommand(
      id: 'c${sequence++}',
      entityId: id,
      operation: op,
      payload: p,
      expectedVersion: version,
    ),
    actor,
  );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    engine = AuthorityEngine(db);
    sequence = 0;
    await run(Operation.catalog, 'p', {
      'sku': 'P',
      'name': 'Gạch',
      'unit': 'viên',
      'price': 100,
    });
    await run(Operation.purchase, 'po', {
      'warehouse': 'main',
      'supplierId': 'ncc',
      'lines': [line(5000)],
    });
    await run(Operation.receive, 'po', {
      'lines': [line(5000)],
    }, version: 1);
  });
  tearDown(() => db.close());
  test('Deposits apply once on sale conversion without counting revenue or cash twice', () async {
    await run(Operation.reservation, 'r', order(4000), actor: sales);
    await run(
      Operation.deposit,
      'r',
      {'amount': 100, 'method': 'cash', 'shiftId': 'shift'},
      version: 1,
      actor: sales,
    );
    await run(
      Operation.deposit,
      'r',
      {'amount': 50, 'method': 'bank', 'shiftId': 'shift'},
      version: 2,
      actor: sales,
    );
    expect((await engine.read('customerDeposit', 'c'))['balance'], 150);
    await run(
      Operation.fulfillReservation,
      'r',
      {'saleId': 's'},
      version: 3,
      actor: sales,
    );
    final sale = await engine.read('sale', 's');
    expect(sale['total'], 400);
    expect(sale['paid'], 150);
    expect(sale['debt'], 250);
    expect((await engine.read('customerDeposit', 'c'))['balance'], 0);
    final report = FinancialReport.fromEvents(
      await db.select(db.businessEvents).get(),
      DateTime(2020),
      DateTime(2100),
    );
    expect(report.revenue, BigInt.from(400));
    expect(report.cashNet, BigInt.from(100));
    expect(report.bankNet, BigInt.from(50));
    final close = await run(Operation.shiftClose, 'close', {
      'shiftId': 'shift',
      'opening': 0,
      'counted': 100,
      'explanation': '',
    });
    expect(close['difference'], 0);
  });
  test(
    'Cancelling a prepaid reservation leaves controlled refundable liability',
    () async {
      await run(Operation.reservation, 'r', order(4000), actor: sales);
      await run(
        Operation.deposit,
        'r',
        {'amount': 200, 'method': 'cash', 'shiftId': 'shift'},
        version: 1,
        actor: sales,
      );
      await run(
        Operation.cancelReservation,
        'r',
        {'reason': 'Khách hủy'},
        version: 2,
        actor: sales,
      );
      expect((await engine.read('reservation', 'r'))['depositRefundDue'], 200);
      await run(Operation.reservationRefund, 'r', {
        'amount': 150,
        'method': 'cash',
        'shiftId': 'shift',
        'reason': 'Hoàn cọc',
      }, version: 3);
      await expectLater(
        run(Operation.reservationRefund, 'r', {
          'amount': 51,
          'method': 'cash',
          'shiftId': 'shift',
          'reason': 'Vượt',
        }, version: 4),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.read('customerDeposit', 'c'))['balance'], 50);
      expect((await engine.read('shiftTotals', 'shift'))['cashNet'], 50);
    },
  );
  test('Partial fulfillment applies available deposit and keeps the excess refundable', () async {
    await run(Operation.reservation, 'r', order(8000), actor: sales);
    await expectLater(
      run(
        Operation.deposit,
        'r',
        {'amount': 700, 'method': 'cash', 'shiftId': 'shift'},
        version: 1,
        actor: sales,
      ),
      throwsA(isA<BusinessException>()),
    );
    await run(Operation.approveReservation, 'r', {
      'decision': 'partial',
      'reason': 'Giao trước',
    }, version: 1);
    await run(
      Operation.deposit,
      'r',
      {'amount': 700, 'method': 'cash', 'shiftId': 'shift'},
      version: 2,
      actor: sales,
    );
    final result = await run(
      Operation.fulfillReservation,
      'r',
      {'saleId': 's', 'partial': true},
      version: 3,
      actor: sales,
    );
    expect(result['depositRefundDue'], 200);
    expect((await engine.read('sale', 's'))['paid'], 500);
    expect((await engine.read('sale', 's'))['debt'], 0);
    expect((await engine.read('customerDeposit', 'c'))['balance'], 200);
  });
  test(
    'Held stock prevents other sales; cancellation releases exactly once',
    () async {
      final r = await run(
        Operation.reservation,
        'r',
        order(4000),
        actor: sales,
      );
      expect(r['status'], 'reserved');
      await expectLater(
        run(Operation.sale, 's', order(2000)),
        throwsA(isA<BusinessException>()),
      );
      await run(
        Operation.cancelReservation,
        'r',
        {'reason': 'Khách hủy'},
        version: 1,
        actor: sales,
      );
      await expectLater(
        run(Operation.cancelReservation, 'r', {}, version: 2, actor: sales),
        throwsA(isA<BusinessException>()),
      );
      await run(Operation.sale, 's', order(5000));
      expect((await engine.stock('main', 'p'))['quantity'], 0);
    },
  );
  test('Oversell requires manager approval and posts only approved available quantity', () async {
    final r = await run(Operation.reservation, 'r', order(8000), actor: sales);
    expect(r['status'], 'pendingApproval');
    await expectLater(
      run(
        Operation.approveReservation,
        'r',
        {'decision': 'partial', 'reason': 'Giao trước'},
        version: 1,
        actor: sales,
      ),
      throwsA(isA<BusinessException>()),
    );
    await expectLater(
      run(
        Operation.fulfillReservation,
        'r',
        {'saleId': 's'},
        version: 1,
        actor: sales,
      ),
      throwsA(isA<BusinessException>()),
    );
    await run(Operation.approveReservation, 'r', {
      'decision': 'partial',
      'reason': 'Giao trước',
    }, version: 1);
    final result = await run(
      Operation.fulfillReservation,
      'r',
      {'saleId': 's', 'partial': true},
      version: 2,
      actor: sales,
    );
    expect((await engine.read('sale', 's'))['total'], 500);
    expect((result['unfulfilledLines'] as List).single['quantity'], 3000);
    expect((await engine.stock('main', 'p'))['quantity'], 0);
    await expectLater(
      run(Operation.fulfillReservation, 'r', {'saleId': 's2'}, version: 3),
      throwsA(isA<BusinessException>()),
    );
  });
  test(
    'Failed full conversion keeps reservation and stock unchanged',
    () async {
      await run(Operation.reservation, 'r', order(8000), actor: sales);
      await run(Operation.approveReservation, 'r', {
        'decision': 'partial',
        'reason': 'Giao trước',
      }, version: 1);
      await expectLater(
        run(Operation.fulfillReservation, 'r', {'saleId': 's'}, version: 2),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.read('reservation', 'r'))['status'], 'partial');
      await expectLater(
        run(Operation.sale, 'another', order(1000)),
        throwsA(isA<BusinessException>()),
      );
    },
  );
}
