import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../domain/operations.dart';
import 'database.dart';
import 'firebase_auth_rest.dart';
import 'firestore_rest.dart';

class SyncReceipt {
  final String commandId, status;
  final Map<String, dynamic> result;
  const SyncReceipt(this.commandId, this.status, this.result);
}

abstract interface class CommandTransport {
  Future<void> submit(BusinessCommand command, String actorUid);
  Future<SyncReceipt?> receipt(String commandId);
}

class FirestoreCommandTransport implements CommandTransport {
  final FirestoreRest firestore;
  final String storeId;
  final Future<AuthSession> Function() currentSession;
  FirestoreCommandTransport(this.firestore, this.storeId, this.currentSession) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(storeId)) {
      throw ArgumentError('Store ID không hợp lệ.');
    }
  }
  String _path(String collection, String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw ArgumentError('ID không hợp lệ.');
    }
    return 'stores/$storeId/$collection/$id';
  }

  @override
  Future<void> submit(BusinessCommand command, String actorUid) async {
    final session = await currentSession();
    if (session.uid != actorUid) {
      throw const AuthFailure('Giao dịch thuộc tài khoản khác.');
    }
    final path = _path('commands', command.id);
    final payload = {
      'commandId': command.id,
      'actorUid': actorUid,
      'operation': command.operation.name,
      'entityId': command.entityId,
      'expectedVersion': command.expectedVersion,
      'payload': command.payload,
    };
    final write = firestore.createWrite(path, payload);
    write['updateTransforms'] = [
      {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
    ];
    try {
      await firestore.commit(session, [write]);
    } on FirestoreFailure catch (e) {
      if (!{400, 409, 412}.contains(e.status)) rethrow;
      final existing = await firestore.get(path, session);
      if (existing == null) rethrow;
      final data = {...existing.data}..remove('createdAt');
      if (canonicalJson(data) != canonicalJson(payload)) {
        throw const BusinessException(
          'idempotency',
          'Mã giao dịch trên cloud có nội dung khác.',
        );
      }
    }
  }

  @override
  Future<SyncReceipt?> receipt(String commandId) async {
    final remote = await firestore.get(
      _path('receipts', commandId),
      await currentSession(),
    );
    if (remote == null) return null;
    final data = remote.data;
    if (data['commandId'] != commandId ||
        !{'confirmed', 'conflict', 'error'}.contains(data['status']) ||
        data['result'] is! Map<String, dynamic>) {
      throw const BusinessException(
        'receipt',
        'Phản hồi xác nhận không hợp lệ.',
      );
    }
    return SyncReceipt(
      commandId,
      data['status'] as String,
      data['result'] as Map<String, dynamic>,
    );
  }
}

class SyncEngine {
  final AppDatabase db;
  final CommandTransport transport;
  final DateTime Function() now;
  final Random random;
  bool _running = false;
  SyncEngine(
    this.db,
    this.transport, {
    DateTime Function()? now,
    Random? random,
  }) : now = now ?? DateTime.now,
       random = random ?? Random();
  Future<void> enqueue(BusinessCommand command, Actor actor) async {
    actor.require(command.operation);
    await db.transaction(() async {
      final existing = await (db.select(
        db.outbox,
      )..where((r) => r.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (existing.actorUid != actor.uid ||
            existing.operation != command.operation.name ||
            existing.aggregateId != command.entityId ||
            existing.expectedVersion != command.expectedVersion ||
            existing.payload != canonicalJson(command.payload)) {
          throw const BusinessException(
            'idempotency',
            'Mã giao dịch cục bộ bị trùng nội dung khác.',
          );
        }
        return;
      }
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: command.id,
              aggregateId: command.entityId,
              payload: canonicalJson(command.payload),
              actorUid: Value(actor.uid),
              operation: Value(command.operation.name),
              expectedVersion: Value(command.expectedVersion),
              createdAt: now(),
            ),
          );
      await db
          .into(db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              action: 'command.pending',
              entityId: command.entityId,
              createdAt: now(),
            ),
          );
    });
  }

  Future<void> pump(String actorUid, {int limit = 20}) async {
    if (_running) return;
    _running = true;
    try {
      // Fetch bounded batches. One engine per device; immutable command IDs also
      // make independent simultaneous uploader instances harmless remotely.
      final rows =
          await (db.select(db.outbox)
                ..where(
                  (r) =>
                      r.actorUid.equals(actorUid) &
                      r.status.isIn(['pending', 'syncing']),
                )
                ..orderBy([(r) => OrderingTerm.asc(r.createdAt)])
                ..limit(limit))
              .get();
      for (final row in rows) {
        if (row.nextAttemptAt != null && row.nextAttemptAt!.isAfter(now())) {
          continue;
        }
        if (row.operation == null) {
          continue; // Legacy drafts require explicit review.
        }
        final operation = Operation.values
            .where((v) => v.name == row.operation)
            .firstOrNull;
        if (operation == null) {
          await _state(row.id, 'error', error: 'operation');
          continue;
        }
        await _state(row.id, 'syncing');
        try {
          final command = BusinessCommand(
            id: row.id,
            entityId: row.aggregateId,
            operation: operation,
            payload: jsonDecode(row.payload) as Map<String, dynamic>,
            expectedVersion: row.expectedVersion,
          );
          // Receipt first makes a crash after remote commit recoverable.
          var receipt = await transport.receipt(row.id);
          if (receipt == null) {
            await transport.submit(command, actorUid);
            receipt = await transport.receipt(row.id);
          }
          if (receipt == null) {
            await _retry(row, 'awaiting_confirmation');
            continue;
          }
          if (receipt.commandId != row.id) {
            throw const BusinessException('receipt', 'Receipt sai giao dịch.');
          }
          if (!{'confirmed', 'conflict', 'error'}.contains(receipt.status)) {
            throw const BusinessException(
              'receipt',
              'Trạng thái xác nhận không hợp lệ.',
            );
          }
          final resolved = receipt;
          await db.transaction(() async {
            if (resolved.status == 'confirmed') {
              final previous = await (db.select(
                db.commandReceipts,
              )..where((r) => r.id.equals(row.id))).getSingleOrNull();
              if (previous != null &&
                  ((previous.fingerprint != command.fingerprint(actorUid) &&
                          previous.fingerprint !=
                              command.legacyFingerprint(actorUid)) ||
                      canonicalJson(
                            jsonDecode(previous.result) as Map<String, dynamic>,
                          ) !=
                          canonicalJson(resolved.result))) {
                throw const BusinessException(
                  'idempotency',
                  'Receipt cục bộ không khớp xác nhận trên cloud.',
                );
              }
              // Preserve the immutable server result separately from the draft.
              await db
                  .into(db.commandReceipts)
                  .insert(
                    CommandReceiptsCompanion.insert(
                      id: row.id,
                      fingerprint: command.fingerprint(actorUid),
                      result: jsonEncode(resolved.result),
                      confirmedAt: now(),
                    ),
                    mode: InsertMode.insertOrIgnore,
                  );
            }
            await _state(
              row.id,
              resolved.status,
              error: resolved.status == 'confirmed'
                  ? null
                  : resolved.result['message'] as String? ??
                        resolved.result['code'] as String? ??
                        'Cần đối chiếu chứng từ.',
            );
          });
        } on FirestoreFailure catch (e) {
          if (e.retryable) {
            await _retry(row, 'transport_${e.status}');
          } else {
            await _state(row.id, 'error', error: 'transport_${e.status}');
          }
        } on AuthFailure {
          await _state(row.id, 'error', error: 'authentication');
        } on BusinessException catch (e) {
          await _state(
            row.id,
            e.code == 'conflict' ? 'conflict' : 'error',
            error: e.code,
          );
        } catch (_) {
          await _retry(row, 'connection');
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _state(String id, String status, {String? error}) =>
      (db.update(db.outbox)..where((r) => r.id.equals(id)))
          .write(
            OutboxCompanion(status: Value(status), lastError: Value(error)),
          )
          .then((_) {});
  Future<void> _retry(OutboxData row, String reason) async {
    final attempts = row.attempts + 1;
    final seconds = min(300, 1 << min(attempts, 8)) + random.nextInt(4);
    await (db.update(db.outbox)..where((r) => r.id.equals(row.id))).write(
      OutboxCompanion(
        status: Value(attempts >= 30 ? 'error' : 'pending'),
        attempts: Value(attempts),
        lastError: Value(reason),
        nextAttemptAt: Value(now().add(Duration(seconds: seconds))),
      ),
    );
  }

  Future<void> applyEvent({
    required String storeId,
    required String eventId,
    required int sequence,
    required Map<String, dynamic> projections,
    Map<String, dynamic>? details,
    String? actorId,
    String? operation,
    DateTime? occurredAt,
  }) => db.transaction(() async {
    final checkpoint = await (db.select(
      db.syncCheckpoints,
    )..where((r) => r.storeId.equals(storeId))).getSingleOrNull();
    final previous = checkpoint?.sequence ?? 0;
    final duplicate = await (db.select(
      db.inboxEvents,
    )..where((r) => r.id.equals('$storeId:$eventId'))).getSingleOrNull();
    if (duplicate != null) {
      if (duplicate.sequence != sequence ||
          duplicate.payload != canonicalJson(projections)) {
        throw const BusinessException('event', 'Event bị thay đổi nội dung.');
      }
      return;
    }
    if (sequence != previous + 1) {
      throw const BusinessException(
        'checkpoint',
        'Thiếu event trung gian; cần tải lại theo checkpoint.',
      );
    }
    for (final entry in projections.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const BusinessException('event', 'Projection không hợp lệ.');
      }
      final data = entry.value as Map<String, dynamic>;
      final version = integerField(data, 'version', min: 1);
      final kind = textField(data, 'kind');
      final existing = await (db.select(
        db.businessRecords,
      )..where((r) => r.id.equals(entry.key))).getSingleOrNull();
      if (existing != null && existing.version >= version) {
        throw const BusinessException(
          'conflict',
          'Projection cũ hoặc ghi đè dữ liệu mới hơn.',
        );
      }
      await db
          .into(db.businessRecords)
          .insertOnConflictUpdate(
            BusinessRecordsCompanion.insert(
              id: entry.key,
              kind: kind,
              payload: canonicalJson(data),
              version: version,
            ),
          );
      if (kind == 'catalog') {
        final id = textField(data, 'id');
        await db
            .into(db.products)
            .insertOnConflictUpdate(
              ProductsCompanion.insert(
                id: id,
                sku: textField(data, 'sku'),
                name: textField(data, 'name'),
                unit: textField(data, 'unit'),
                price: integerField(data, 'price'),
              ),
            );
      }
    }
    await db
        .into(db.inboxEvents)
        .insert(
          InboxEventsCompanion.insert(
            id: '$storeId:$eventId',
            storeId: storeId,
            sequence: sequence,
            payload: canonicalJson(projections),
          ),
        );
    if (details != null && actorId != null && operation != null) {
      await db
          .into(db.businessEvents)
          .insert(
            BusinessEventsCompanion.insert(
              commandId: eventId,
              kind: operation,
              actorId: actorId,
              payload: canonicalJson(details),
              occurredAt: occurredAt ?? DateTime.now(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await db
        .into(db.syncCheckpoints)
        .insertOnConflictUpdate(
          SyncCheckpointsCompanion.insert(
            storeId: storeId,
            sequence: Value(sequence),
          ),
        );
  });
}
