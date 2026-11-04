import 'dart:convert';

import '../domain/operations.dart';
import 'authority_engine.dart';
import 'authority_store.dart';
import 'database.dart';
import 'firebase_auth_rest.dart';
import 'firestore_rest.dart';

/// Stages all business writes and commits them with receipt/event atomically.
/// No SQLite state is treated as confirmed before a cloud commit succeeds.
class FirestoreAuthorityStore implements AuthorityStore {
  final FirestoreRest firestore;
  final String storeId;
  final Future<AuthSession> Function() sessionProvider;
  final Map<String, RemoteDocument?> _reads = {};
  final Map<String, Map<String, dynamic>> _writes = {};
  AuthSession? _session;
  String? _transaction;
  bool _busy = false;
  FirestoreAuthorityStore(this.firestore, this.storeId, this.sessionProvider) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(storeId)) {
      throw ArgumentError('Store ID không hợp lệ.');
    }
  }
  String _path(String collection, String id) =>
      'stores/$storeId/$collection/$id';
  String _key(String id) {
    final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    if (encoded.length > 1400) {
      throw const BusinessException('validation', 'Định danh quá dài.');
    }
    return encoded;
  }

  String _recordPath(String kind, String id) =>
      _path('documents', _key('$kind:$id'));
  Future<Map<String, dynamic>?> _load(String path) async {
    if (_transaction == null || _session == null) {
      throw StateError('Outside authority transaction');
    }
    if (_writes.containsKey(path)) return _writes[path];
    if (!_reads.containsKey(path)) {
      _reads[path] = await firestore.get(
        path,
        _session!,
        transaction: _transaction,
      );
    }
    return _reads[path]?.data;
  }

  Future<void> _put(String path, Map<String, dynamic> data) async {
    await _load(path);
    _writes[path] = data;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError(
        'Use a separate authority context for concurrent commands',
      );
    }
    _busy = true;
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        _reads.clear();
        _writes.clear();
        _session = await sessionProvider();
        _transaction = await firestore.begin(_session!);
        try {
          final result = await action();
          if (_writes.length > 400) {
            throw const BusinessException(
              'limit',
              'Chứng từ vượt giới hạn ghi nguyên tử.',
            );
          }
          final writes = <Map<String, dynamic>>[];
          for (final entry in _writes.entries) {
            final old = _reads[entry.key];
            writes.add(
              old == null
                  ? firestore.createWrite(entry.key, entry.value)
                  : firestore.updateWrite(old, entry.value),
            );
          }
          await firestore.commit(_session!, writes, transaction: _transaction);
          return result;
        } catch (error) {
          try {
            await firestore.rollback(_session!, _transaction!);
          } catch (_) {
            /* May already be committed/aborted. */
          }
          if (error is FirestoreFailure && error.status == 409 && attempt < 4) {
            await Future<void>.delayed(
              Duration(milliseconds: 25 * (1 << attempt)),
            );
            continue;
          }
          rethrow;
        } finally {
          _transaction = null;
          _session = null;
        }
      }
      throw const FirestoreFailure(409);
    } finally {
      _busy = false;
    }
  }

  Future<Actor> actor(String uid) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(uid)) {
      throw const BusinessException('permission', 'UID không hợp lệ.');
    }
    final member = await _load(_path('members', uid));
    final role = StaffRole.values
        .where((r) => r.name == member?['role'])
        .firstOrNull;
    if (member == null || role == null) {
      throw const BusinessException(
        'permission',
        'Không có quyền tại cửa hàng.',
      );
    }
    return Actor(
      uid,
      role,
      active: member['active'] == true,
      mustChangePassword: member['mustChangePassword'] != false,
    );
  }

  @override
  Future<BusinessRecord?> record(String kind, String id) async {
    final data = await _load(_recordPath(kind, id));
    if (data == null) return null;
    return BusinessRecord(
      id: data['recordId'] as String,
      kind: data['kind'] as String,
      payload: canonicalJson(data['payload'] as Map<String, dynamic>),
      version: integerField(data, 'version', min: 1),
    );
  }

  @override
  Future<void> writeRecord(BusinessRecord record) async {
    final path = _path('documents', _key(record.id));
    await _put(path, {
      'recordId': record.id,
      'kind': record.kind,
      'version': record.version,
      'payload': jsonDecode(record.payload),
    });
  }

  @override
  Future<Product?> product(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const BusinessException('validation', 'Product ID không hợp lệ.');
    }
    final data = await _load(_path('catalog', id));
    if (data == null) return null;
    return Product(
      id: id,
      sku: textField(data, 'sku'),
      name: textField(data, 'name'),
      unit: textField(data, 'unit'),
      price: integerField(data, 'price'),
    );
  }

  @override
  Future<CommandReceipt?> receipt(String id) async {
    final data = await _load(_path('receipts', id));
    if (data == null) return null;
    if (data['status'] != 'confirmed') {
      throw BusinessException(
        data['status'] as String? ?? 'error',
        'Giao dịch đã được xử lý và cần xem lại.',
      );
    }
    return CommandReceipt(
      id: id,
      fingerprint: data['fingerprint'] as String,
      result: canonicalJson(data['result'] as Map<String, dynamic>),
      confirmedAt: data['confirmedAt'] as DateTime,
    );
  }

  @override
  Future<void> saveReceipt(
    String id,
    String fingerprint,
    Map<String, dynamic> result,
  ) => _put(_path('receipts', id), {
    'commandId': id,
    'status': 'confirmed',
    'fingerprint': fingerprint,
    'result': result,
    'confirmedAt': DateTime.now().toUtc(),
  });
  @override
  Future<void> appendEvent(
    BusinessCommand command,
    Actor actor,
    Map<String, dynamic> payload,
  ) async {
    final metaPath = _recordPath('system', 'eventSequence');
    final meta = await _load(metaPath);
    final next = (meta?['next'] as int? ?? 0) + 1;
    final projections = <String, dynamic>{};
    for (final entry in _writes.entries) {
      if (entry.key.contains('/documents/') &&
          entry.value['recordId'] is String) {
        projections[entry.value['recordId'] as String] = {
          ...(entry.value['payload'] as Map<String, dynamic>),
          'kind': entry.value['kind'],
          'version': entry.value['version'],
        };
      }
    }
    await _put(metaPath, {'next': next});
    await _put(_path('events', command.id), {
      'sequence': next,
      'commandId': command.id,
      'actorId': actor.uid,
      'operation': command.operation.name,
      'payload': payload,
      'projections': projections,
      'occurredAt': DateTime.now().toUtc(),
    });
  }
}

class RemoteAuthorityProcessor {
  final FirestoreAuthorityStore store;
  RemoteAuthorityProcessor(this.store);

  /// Called by the separately authenticated trusted station, never by sales UI.
  Future<Map<String, dynamic>> process(String commandId) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(commandId)) {
      throw ArgumentError('Command ID không hợp lệ.');
    }
    final remote = await store.firestore.get(
      'stores/${store.storeId}/commands/$commandId',
      await store.sessionProvider(),
    );
    if (remote == null) {
      throw const BusinessException('missing', 'Không tìm thấy command.');
    }
    final data = remote.data;
    if (data['commandId'] != commandId) {
      throw const BusinessException('validation', 'Command ID không khớp.');
    }
    final operation = Operation.values
        .where((o) => o.name == data['operation'])
        .firstOrNull;
    if (operation == null || data['payload'] is! Map<String, dynamic>) {
      throw const BusinessException('validation', 'Command không hợp lệ.');
    }
    final command = BusinessCommand(
      id: commandId,
      entityId: textField(data, 'entityId'),
      operation: operation,
      payload: data['payload'] as Map<String, dynamic>,
      expectedVersion: integerField(data, 'expectedVersion'),
    );
    final actorUid = textField(data, 'actorUid');
    try {
      return await AuthorityEngine.withStore(store)
          .executeAuthenticated(command, () => store.actor(actorUid));
    } on BusinessException catch (error) {
      return store.transaction(() async {
        final path = store._path('receipts', commandId);
        final existing = await store._load(path);
        if (existing != null) return existing['result'] as Map<String, dynamic>;
        final status = error.code == 'conflict' ? 'conflict' : 'error';
        final result = {'code': error.code, 'message': error.message};
        await store._put(path, {
          'commandId': commandId,
          'status': status,
          'fingerprint': command.fingerprint(actorUid),
          'result': result,
          'confirmedAt': DateTime.now().toUtc(),
        });
        return result;
      });
    }
  }
}
