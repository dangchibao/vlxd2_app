import 'dart:convert';

import '../domain/operations.dart';
import 'database.dart';

abstract interface class AuthorityStore {
  Future<T> transaction<T>(Future<T> Function() action);
  Future<BusinessRecord?> record(String kind, String id);
  Future<void> writeRecord(BusinessRecord record);
  Future<CommandReceipt?> receipt(String id);
  Future<void> saveReceipt(
    String id,
    String fingerprint,
    Map<String, dynamic> result,
  );
  Future<void> appendEvent(
    BusinessCommand command,
    Actor actor,
    Map<String, dynamic> payload,
  );
  Future<Product?> product(String id);
}

class DriftAuthorityStore implements AuthorityStore {
  final AppDatabase db;
  DriftAuthorityStore(this.db);
  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      db.transaction(action);
  @override
  Future<BusinessRecord?> record(String kind, String id) => (db.select(
    db.businessRecords,
  )..where((r) => r.id.equals('$kind:$id'))).getSingleOrNull();
  @override
  Future<void> writeRecord(BusinessRecord record) => db
      .into(db.businessRecords)
      .insertOnConflictUpdate(
        BusinessRecordsCompanion.insert(
          id: record.id,
          kind: record.kind,
          payload: record.payload,
          version: record.version,
        ),
      )
      .then((_) {});
  @override
  Future<CommandReceipt?> receipt(String id) => (db.select(
    db.commandReceipts,
  )..where((r) => r.id.equals(id))).getSingleOrNull();
  @override
  Future<void> saveReceipt(
    String id,
    String fingerprint,
    Map<String, dynamic> result,
  ) => db
      .into(db.commandReceipts)
      .insert(
        CommandReceiptsCompanion.insert(
          id: id,
          fingerprint: fingerprint,
          result: jsonEncode(result),
          confirmedAt: DateTime.now(),
        ),
      )
      .then((_) {});
  @override
  Future<void> appendEvent(
    BusinessCommand command,
    Actor actor,
    Map<String, dynamic> payload,
  ) => db
      .into(db.businessEvents)
      .insert(
        BusinessEventsCompanion.insert(
          commandId: command.id,
          kind: command.operation.name,
          actorId: actor.uid,
          payload: jsonEncode(payload),
          occurredAt: DateTime.now(),
        ),
      )
      .then((_) {});
  @override
  Future<Product?> product(String id) =>
      (db.select(db.products)..where((r) => r.id.equals(id))).getSingleOrNull();
}
