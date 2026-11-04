import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/sale.dart';

void main() {
  test('Money stays exact and rejects overpayment', () {
    const line = SaleLine(
      productId: '1',
      sku: 'A',
      name: 'A',
      unit: 'bao',
      price: 95000,
      quantity: 3,
    );
    final t = SaleTotals([line], discount: 5000, paid: 100000);
    expect(t.total, 280000);
    expect(t.debt, 180000);
    expect(() => SaleTotals([line], paid: 300000), throwsArgumentError);
  });
  test('Unique SKU and journal transaction', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.addProduct(' a ', 'A', 'bao', 100);
    await expectLater(db.addProduct('A', 'B', 'bao', 200), throwsA(anything));
    expect((await db.select(db.products).get()).length, 1);
    expect((await db.select(db.auditEvents).get()).length, 1);
  });
  test('Concurrent submit creates one outbox and locks the draft', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final results = await Future.wait(
      List.generate(2, (_) async {
        try {
          await db.saveDraft('order', {'lines': []}, submit: true);
          return true;
        } catch (_) {
          return false;
        }
      }),
    );
    expect(results.where((v) => v).length, 1);
    expect((await db.select(db.outbox).get()).length, 1);
    expect((await db.select(db.drafts).get()).single.status, 'pending');
    await expectLater(db.saveDraft('order', {}), throwsStateError);
  });
  test('Data and pending command survive database restart', () async {
    final directory = await Directory.systemTemp.createTemp('bayhai_test_');
    final file = File('${directory.path}/local.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    await db.saveDraft('order', {'customer': 'Khách A'}, submit: true);
    await db.close();
    final reopened = AppDatabase(NativeDatabase(file));
    expect(
      (await reopened.select(reopened.drafts).get()).single.payload,
      contains('Khách A'),
    );
    expect((await reopened.select(reopened.outbox).get()).length, 1);
    await reopened.close();
    await directory.delete(recursive: true);
  });
}
