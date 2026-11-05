import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/authority_engine.dart';
import 'package:vlxd_bay_hai/data/authority_store.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/receipt_printer.dart';
import 'package:vlxd_bay_hai/domain/financial_report.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/domain/stock_period.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Collection allocates atomically and counts cash once across two sales',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftAuthorityStore(db);
      final engine = AuthorityEngine.withStore(store);
      Future<void> seed(String kind, String id, Map<String, dynamic> data) =>
          store.writeRecord(
            BusinessRecord(
              id: '$kind:$id',
              kind: kind,
              version: 1,
              payload: jsonEncode({...data, 'version': 1}),
            ),
          );
      await seed('sale', 'a', {'customerId': 'kh', 'paid': 0, 'debt': 80});
      await seed('sale', 'b', {'customerId': 'kh', 'paid': 5, 'debt': 70});
      await seed('receivable', 'kh', {'balance': 150});
      final a = {'documentId': 'a', 'amount': 60, 'version': 1};
      final b = {'documentId': 'b', 'amount': 40, 'version': 1};
      Future<Map<String, dynamic>> collect(
        String command,
        List<Map<String, dynamic>> allocations,
      ) => engine.execute(
        BusinessCommand(
          id: command,
          entityId: 'kh',
          operation: Operation.debtCollection,
          expectedVersion: 1,
          payload: {
            'shiftId': 'ca',
            'amount': 100,
            'method': 'cash',
            'allocations': allocations,
          },
        ),
        const Actor('manager', StaffRole.manager),
      );
      await expectLater(
        collect('bad', [
          a,
          {...b, 'version': 2},
        ]),
        throwsA(isA<BusinessException>()),
      );
      expect((await engine.read('sale', 'a'))['debt'], 80);
      expect(await engine.read('shiftTotals', 'ca'), isEmpty);
      final posted = await collect('ok', [a, b]);
      expect(await collect('ok', [a, b]), posted);
      expect((await engine.read('sale', 'a'))['debt'], 20);
      expect((await engine.read('sale', 'b'))['paid'], 45);
      expect((await engine.read('receivable', 'kh'))['balance'], 50);
      expect((await engine.read('shiftTotals', 'ca'))['cashNet'], 100);
      final report = FinancialReport.fromEvents(
        await db.select(db.businessEvents).get(),
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(report.cashNet, BigInt.from(100));
      expect(report.revenue, BigInt.zero);
    },
  );

  test('Supplier allocation respects legacy aggregate balance and records receipt payment', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DriftAuthorityStore(db);
    final engine = AuthorityEngine.withStore(store);
    Future<void> seed(String kind, String id, Map<String, dynamic> data) =>
        store.writeRecord(
          BusinessRecord(
            id: '$kind:$id',
            kind: kind,
            version: 1,
            payload: jsonEncode({...data, 'version': 1}),
          ),
        );
    await seed('payable', 'ncc', {'balance': 50});
    await seed('purchaseReceipt', 'r', {'supplierId': 'ncc', 'total': 100});
    Future<Map<String, dynamic>> pay(String key, int amount) => engine.execute(
      BusinessCommand(
        id: key,
        entityId: 'ncc',
        operation: Operation.supplierPayment,
        expectedVersion: 1,
        payload: {
          'shiftId': 'ca',
          'amount': amount,
          'method': 'bank',
          'allocations': [
            {'documentId': 'r', 'amount': amount, 'version': 1},
          ],
        },
      ),
      const Actor('manager', StaffRole.manager),
    );
    await expectLater(pay('excess', 60), throwsA(isA<BusinessException>()));
    await pay('pay', 45);
    expect((await engine.read('purchaseReceipt', 'r'))['paid'], 45);
    expect((await engine.read('payable', 'ncc'))['balance'], 5);
    expect((await engine.read('shiftTotals', 'ca'))['bankNet'], -45);
  });

  test('Stock report reconstructs opening, movements and closing with period boundaries', () {
    final start = DateTime.utc(2026, 11, 1), end = DateTime.utc(2026, 12, 1);
    final timestamps = [start.subtract(const Duration(days: 1)), start, end];
    final inbox = [
      for (var i = 0; i < 3; i++)
        InboxEvent(
          id: 'shop:c$i',
          storeId: 'shop',
          sequence: i + 1,
          payload: jsonEncode({
            'stock:p': {
              'kind': 'stock',
              'warehouse': 'main',
              'productId': 'p',
              'quality': 'good',
              'quantity': [4000, 2500, 5500][i],
              'value': [120, 75, 165][i],
              'version': i + 1,
            },
          }),
        ),
    ];
    final events = [
      for (var i = 0; i < 3; i++)
        BusinessEvent(
          sequence: i + 1,
          commandId: 'c$i',
          kind: 'test',
          actorId: 'manager',
          payload: '{}',
          occurredAt: timestamps[i],
        ),
    ];
    final report = StockPeriod.fromLedger(inbox, events, start, end);
    final stock = report.balances.single;
    expect(stock.opening, BigInt.from(4000));
    expect(stock.outgoing, BigInt.from(1500));
    expect(stock.closing, BigInt.from(2500));
    expect(stock.closingValue, BigInt.from(75));
    expect(report.movements.single.commandId, 'c1');
    expect(
      StockPeriod.fromLedger(
        inbox.skip(1).toList(),
        events,
        start,
        end,
      ).missingHistory,
      1,
    );
  });

  test(
    'Label PDF renders Vietnamese text and rejects oversized labels',
    () async {
      final data = {
        'name': 'Gạch vân đá',
        'unit': 'm²',
        'labelCode': '8930123456789',
        'price': 240000,
        'copies': 2,
      };
      final renderer = ReceiptRenderer();
      final bytes = await renderer.renderDocument(
        kind: 'barcodeLabel',
        data: data,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      await expectLater(
        renderer.renderLabel({...data, 'copies': 101}),
        throwsA(isA<BusinessException>()),
      );
    },
  );
}
