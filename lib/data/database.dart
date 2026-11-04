import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
part 'database.g.dart';

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get sku => text().unique()();
  TextColumn get name => text()();
  TextColumn get unit => text()();
  IntColumn get price =>
      integer().customConstraint('NOT NULL CHECK (price >= 0)')();
  @override
  Set<Column> get primaryKey => {id};
}

class Drafts extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Outbox extends Table {
  TextColumn get id => text()();
  TextColumn get aggregateId => text()();
  TextColumn get payload => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class AuditEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get action => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Products, Drafts, Outbox, AuditEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'bayhai_v1',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.dart.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
  Stream<List<Product>> watchProducts() =>
      (select(products)..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
  Stream<List<Draft>> watchDrafts() => (select(
    drafts,
  )..orderBy([(d) => OrderingTerm.desc(d.updatedAt)])).watch();
  Stream<List<OutboxData>> watchQueue() => select(outbox).watch();
  Future<void> addProduct(
    String sku,
    String name,
    String unit,
    int price,
  ) async {
    if (sku.trim().isEmpty ||
        name.trim().isEmpty ||
        unit.trim().isEmpty ||
        price < 0 ||
        price > 1000000000000) {
      throw ArgumentError('Thông tin hàng hóa không hợp lệ');
    }
    await transaction(() async {
      final id = const Uuid().v4();
      await into(products).insert(
        ProductsCompanion.insert(
          id: id,
          sku: sku.trim().toUpperCase(),
          name: name.trim(),
          unit: unit.trim(),
          price: price,
        ),
      );
      await into(auditEvents).insert(
        AuditEventsCompanion.insert(
          action: 'product.local_created',
          entityId: id,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> saveDraft(
    String id,
    Map<String, dynamic> payload, {
    bool submit = false,
  }) => transaction(() async {
    final existing = await (select(
      drafts,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.status != 'draft') {
      throw StateError('Đơn đã gửi; không được sửa trực tiếp.');
    }
    final encoded = jsonEncode(payload);
    await into(drafts).insertOnConflictUpdate(
      DraftsCompanion.insert(
        id: id,
        payload: encoded,
        status: Value(submit ? 'pending' : 'draft'),
        version: Value((existing?.version ?? 0) + 1),
        updatedAt: DateTime.now(),
      ),
    );
    if (submit) {
      await into(outbox).insert(
        OutboxCompanion.insert(
          id: const Uuid().v4(),
          aggregateId: id,
          payload: encoded,
          createdAt: DateTime.now(),
        ),
      );
    }
    await into(auditEvents).insert(
      AuditEventsCompanion.insert(
        action: submit ? 'sale.pending' : 'sale.draft_saved',
        entityId: id,
        createdAt: DateTime.now(),
      ),
    );
  });
}
