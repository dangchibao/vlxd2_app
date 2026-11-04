import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/sync_engine.dart';
import 'package:vlxd_bay_hai/data/firestore_rest.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

class FakeTransport implements CommandTransport {
  int submissions = 0;
  bool offline = false;
  SyncReceipt? response;
  @override
  Future<void> submit(BusinessCommand command, String actorUid) async {
    submissions++;
    if (offline) throw const FirestoreFailure(503);
  }

  @override
  Future<SyncReceipt?> receipt(String id) async {
    if (offline) throw const FirestoreFailure(503);
    return response;
  }
}

void main() {
  late AppDatabase db;
  late SyncEngine sync;
  late FakeTransport transport;
  late DateTime now;
  final command = BusinessCommand(
    id: 'cmd',
    entityId: 'sale',
    operation: Operation.sale,
    payload: {'x': 1},
  );
  const actor = Actor('seller', StaffRole.sales);
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    transport = FakeTransport();
    now = DateTime.utc(2026, 11, 5);
    sync = SyncEngine(db, transport, now: () => now, random: Random(1));
  });
  tearDown(() => db.close());
  test('Offline command is durable and uses controlled backoff', () async {
    await sync.enqueue(command, actor);
    transport.offline = true;
    await sync.pump('seller');
    final row = (await db.select(db.outbox).get()).single;
    expect(row.status, 'pending');
    expect(row.attempts, 1);
    expect(row.nextAttemptAt!.isAfter(now), true);
    final before = transport.submissions;
    await sync.pump('seller');
    expect(transport.submissions, before);
  });
  test('Receipt after crash prevents duplicate submit', () async {
    await sync.enqueue(command, actor);
    transport.response = const SyncReceipt('cmd', 'confirmed', {'id': 'sale'});
    await sync.pump('seller');
    expect(transport.submissions, 0);
    expect((await db.select(db.outbox).get()).single.status, 'confirmed');
    expect((await db.select(db.commandReceipts).get()).length, 1);
  });
  test('Conflicts stop retry and never create confirmed receipt', () async {
    await sync.enqueue(command, actor);
    transport.response = const SyncReceipt('cmd', 'conflict', {
      'code': 'version',
    });
    await sync.pump('seller');
    expect((await db.select(db.outbox).get()).single.status, 'conflict');
    expect(await db.select(db.commandReceipts).get(), isEmpty);
  });
  test('Another user cannot upload queued command', () async {
    await sync.enqueue(command, actor);
    await sync.pump('different');
    expect(transport.submissions, 0);
    expect((await db.select(db.outbox).get()).single.status, 'pending');
  });
  test('Replay event is idempotent; checkpoint gaps roll back', () async {
    final projection = {
      'stock:one': {'kind': 'stock', 'version': 1, 'quantity': 1000},
    };
    await sync.applyEvent(
      storeId: 'shop',
      eventId: 'one',
      sequence: 1,
      projections: projection,
    );
    await sync.applyEvent(
      storeId: 'shop',
      eventId: 'one',
      sequence: 1,
      projections: projection,
    );
    expect((await db.select(db.businessRecords).get()).length, 1);
    await expectLater(
      sync.applyEvent(
        storeId: 'shop',
        eventId: 'three',
        sequence: 3,
        projections: {},
      ),
      throwsA(isA<BusinessException>()),
    );
    expect((await db.select(db.syncCheckpoints).get()).single.sequence, 1);
  });
  test(
    'Changed event and local idempotency key collision are rejected',
    () async {
      await sync.enqueue(command, actor);
      await sync.enqueue(command, actor);
      expect((await db.select(db.outbox).get()).length, 1);
      await expectLater(
        sync.enqueue(
          BusinessCommand(
            id: 'cmd',
            entityId: 'sale',
            operation: Operation.sale,
            payload: {'x': 2},
          ),
          actor,
        ),
        throwsA(isA<BusinessException>()),
      );
      await sync.applyEvent(
        storeId: 'shop',
        eventId: 'one',
        sequence: 1,
        projections: {},
      );
      await expectLater(
        sync.applyEvent(
          storeId: 'shop',
          eventId: 'one',
          sequence: 1,
          projections: {
            'changed': {'kind': 'stock', 'version': 1},
          },
        ),
        throwsA(isA<BusinessException>()),
      );
    },
  );
}
