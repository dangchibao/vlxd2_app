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
  test(
    'Version 1 local data migrates to version 4 without losing pending drafts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bayhai_migration_',
      );
      final file = File('${directory.path}/legacy.sqlite');
      final legacy = AppDatabase(NativeDatabase(file));
      await legacy.addProduct('LEGACY', 'Hàng cũ', 'bao', 10000);
      await legacy.saveDraft('legacy-order', {
        'customer': 'Khách cũ',
      }, submit: true);
      // Only manipulate this freshly created temporary test fixture.
      for (final table in [
        'business_records',
        'command_receipts',
        'business_events',
        'sync_checkpoints',
        'inbox_events',
        'print_jobs',
      ]) {
        await legacy.customStatement('DROP TABLE $table');
      }
      await legacy.customStatement(
        'DROP INDEX IF EXISTS idx_queue_actor_status',
      );
      for (final column in [
        'actor_uid',
        'operation',
        'expected_version',
        'next_attempt_at',
        'last_error',
      ]) {
        await legacy.customStatement('ALTER TABLE outbox DROP COLUMN $column');
      }
      await legacy.customStatement('PRAGMA user_version = 1');
      await legacy.close();
      final upgraded = AppDatabase(NativeDatabase(file));
      expect(
        (await upgraded.select(upgraded.products).get()).single.sku,
        'LEGACY',
      );
      expect(
        (await upgraded.select(upgraded.outbox).get()).single.actorUid,
        isNull,
      );
      expect(
        (await upgraded.select(upgraded.drafts).get()).single.id,
        'legacy-order',
      );
      expect(await upgraded.select(upgraded.businessEvents).get(), isEmpty);
      await upgraded.close();
      await directory.delete(recursive: true);
    },
  );
}
