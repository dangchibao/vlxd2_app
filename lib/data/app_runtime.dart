import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/operations.dart';
import 'database.dart';
import 'firebase_auth_rest.dart';
import 'firestore_rest.dart';
import 'firestore_authority_store.dart';
import 'session_vault.dart';
import 'sync_engine.dart';

class AppConnection {
  final String projectId, apiKey, storeId;
  final Uri? authEmulator, firestoreEmulator;
  const AppConnection({
    required this.projectId,
    required this.apiKey,
    this.storeId = 'shop',
    this.authEmulator,
    this.firestoreEmulator,
  });
  bool get configured => projectId.isNotEmpty && apiKey.isNotEmpty;
  factory AppConnection.environment() => AppConnection(
    projectId: const String.fromEnvironment('BAYHAI_PROJECT_ID'),
    apiKey: const String.fromEnvironment('BAYHAI_API_KEY'),
    storeId: const String.fromEnvironment(
      'BAYHAI_STORE_ID',
      defaultValue: 'shop',
    ),
    authEmulator: const String.fromEnvironment('BAYHAI_AUTH_EMULATOR').isEmpty
        ? null
        : Uri.parse(const String.fromEnvironment('BAYHAI_AUTH_EMULATOR')),
    firestoreEmulator:
        const String.fromEnvironment('BAYHAI_FIRESTORE_EMULATOR').isEmpty
        ? null
        : Uri.parse(const String.fromEnvironment('BAYHAI_FIRESTORE_EMULATOR')),
  );
  String emailFor(String username) {
    final user = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,64}$').hasMatch(user) ||
        !RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(storeId)) {
      throw const AuthFailure(
        'Tên đăng nhập dùng 3–64 ký tự chữ, số, chấm, gạch dưới hoặc gạch ngang.',
      );
    }
    return '$user+$storeId@bayhai.invalid';
  }
}

class AppRuntime extends ChangeNotifier {
  AppDatabase db;
  final AppDatabase Function(String uid)? databaseFactory;
  final Map<String, AppDatabase> _userDatabases = {};
  int _generation = 0;
  final AppConnection config;
  late final http.Client client;
  late final FirebaseAuthRest auth;
  late final FirestoreRest firestore;
  late final SessionVault vault, stationVault;
  late SyncEngine sync;
  AuthSession? session, stationSession;
  Actor? actor;
  bool loading = false, offline = false, syncing = false, _disposed = false;
  bool maintenance = false;
  String? error;
  DateTime? lastSync;
  DateTime? _membershipChecked;
  Timer? _timer;
  AppRuntime(
    this.db,
    this.config, {
    http.Client? client,
    SessionVault? vault,
    SessionVault? stationVault,
    this.databaseFactory,
  }) {
    this.client = client ?? http.Client();
    this.vault = vault ?? SessionVault('${config.projectId}.${config.storeId}');
    this.stationVault =
        stationVault ??
        SessionVault('${config.projectId}.${config.storeId}.station');
    if (!config.configured) return;
    auth = FirebaseAuthRest(
      client: this.client,
      apiKey: config.apiKey,
      emulator: config.authEmulator,
    );
    firestore = FirestoreRest(
      client: this.client,
      projectId: config.projectId,
      emulator: config.firestoreEmulator,
    );
    sync = SyncEngine(
      db,
      FirestoreCommandTransport(firestore, config.storeId, currentSession),
    );
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    if (!config.configured) return;
    loading = true;
    _notify();
    try {
      session = await vault.read();
      if (session != null) {
        try {
          await currentSession();
          await _membership();
        } on FirestoreFailure catch (e) {
          if (!e.retryable) rethrow;
          await _restoreOffline();
        } on AuthFailure catch (e) {
          if (!e.retryable) rethrow;
          await _restoreOffline();
        }
      }
      stationSession = await stationVault.read();
      if (actor != null && !actor!.mustChangePassword) _start();
    } catch (_) {
      session = null;
      actor = null;
      error = 'Không khôi phục được phiên. Vui lòng đăng nhập lại.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _restoreOffline() async {
    final cached = await vault.readData('profile');
    final verified = DateTime.tryParse(cached?['verifiedAt'] as String? ?? '');
    final age = verified == null
        ? null
        : DateTime.now().toUtc().difference(verified);
    if (cached == null ||
        cached['uid'] != session?.uid ||
        age == null ||
        age.isNegative ||
        age > const Duration(hours: 12)) {
      throw const AuthFailure('Cần mạng để xác minh lại tài khoản.');
    }
    final role = StaffRole.values
        .where((r) => r.name == cached['role'])
        .firstOrNull;
    if (role == null ||
        cached['active'] != true ||
        cached['mustChangePassword'] != false) {
      throw const AuthFailure('Phiên offline không được phép.');
    }
    actor = Actor(session!.uid, role);
    _membershipChecked = verified!.toLocal();
    offline = true;
  }

  Future<AuthSession> currentSession() async {
    var value = session;
    if (value == null) throw const AuthFailure('Vui lòng đăng nhập.');
    if (value.expiresAt.isBefore(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
    )) {
      value = await auth.refresh(value);
      session = value;
      await vault.write(value);
    }
    return value;
  }

  Future<void> _membership() async {
    final generation = _generation;
    final current = await currentSession();
    final member = await firestore.get(
      'stores/${config.storeId}/members/${current.uid}',
      current,
    );
    final data = member?.data;
    if (generation != _generation || session?.uid != current.uid) {
      throw const AuthFailure('Phiên đăng nhập đã thay đổi.');
    }
    final role = StaffRole.values
        .where((r) => r.name == data?['role'])
        .firstOrNull;
    if (data == null || role == null || data['active'] != true) {
      throw const AuthFailure('Tài khoản chưa được cấp quyền hoặc đã bị khóa.');
    }
    actor = Actor(
      current.uid,
      role,
      mustChangePassword: data['mustChangePassword'] != false,
    );
    await vault.writeData('profile', {
      'uid': current.uid,
      'role': role.name,
      'active': true,
      'mustChangePassword': actor!.mustChangePassword,
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    });
    offline = false;
    _membershipChecked = DateTime.now();
  }

  Future<void> signIn(String username, String password) async {
    _generation++;
    loading = true;
    error = null;
    _notify();
    try {
      session = await auth.signIn(config.emailFor(username), password);
      await _membership();
      await vault.write(session!);
      if (!actor!.mustChangePassword) _start();
    } catch (e) {
      session = null;
      actor = null;
      error = e is AuthFailure
          ? e.message
          : 'Không đăng nhập được. Kiểm tra kết nối và cấu hình cửa hàng.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> changePassword(String password) async {
    _generation++;
    loading = true;
    error = null;
    _notify();
    try {
      session = await auth.changePassword(await currentSession(), password);
      await vault.write(session!);
      await _membership();
      if (actor?.mustChangePassword == true) {
        error = 'Mật khẩu đã đổi. Quản trị cần xác nhận kích hoạt tài khoản.';
      } else {
        _start();
      }
    } catch (e) {
      error = e is AuthFailure ? e.message : 'Không đổi được mật khẩu.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> checkMembership() async {
    try {
      await _membership();
      if (actor?.mustChangePassword == false) _start();
      error = null;
    } catch (_) {
      error = 'Chưa xác minh được quyền. Kiểm tra mạng hoặc liên hệ quản trị.';
    }
    _notify();
  }

  Future<void> logout() async {
    _generation++;
    _timer?.cancel();
    session = null;
    actor = null;
    await vault.clear();
    error = null;
    _notify();
  }

  void _start() {
    final uid = sha256.convert(utf8.encode(actor!.uid)).toString();
    db = _userDatabases.putIfAbsent(
      actor!.uid,
      () =>
          databaseFactory?.call(actor!.uid) ??
          AppDatabase(
            null,
            'bayhai_${config.projectId}_${config.storeId}_$uid',
          ),
    );
    sync = SyncEngine(
      db,
      FirestoreCommandTransport(firestore, config.storeId, currentSession),
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    unawaited(tick());
  }

  Future<String> enqueue(
    Operation operation,
    String entityId,
    Map<String, dynamic> payload, {
    int expectedVersion = 0,
    bool syncNow = true,
  }) async {
    if (maintenance) {
      throw const BusinessException(
        'maintenance',
        'Đang khôi phục dữ liệu. Vui lòng đợi.',
      );
    }
    final user = actor;
    if (user == null) throw const AuthFailure('Cần đăng nhập để gửi chứng từ.');
    final age = _membershipChecked == null
        ? null
        : DateTime.now().difference(_membershipChecked!);
    if (age == null || age.isNegative || age > const Duration(hours: 12)) {
      throw const AuthFailure(
        'Cần kết nối mạng để xác minh lại quyền tài khoản.',
      );
    }
    final command = BusinessCommand(
      id: const Uuid().v4(),
      entityId: entityId,
      operation: operation,
      payload: payload,
      expectedVersion: expectedVersion,
    );
    await sync.enqueue(command, user);
    if (syncNow) unawaited(tick());
    return command.id;
  }

  Future<void> tick() async {
    if (syncing ||
        maintenance ||
        session == null ||
        actor == null ||
        actor!.mustChangePassword) {
      return;
    }
    syncing = true;
    final generation = _generation;
    _notify();
    try {
      if (_membershipChecked == null ||
          DateTime.now().difference(_membershipChecked!) >
              const Duration(minutes: 5)) {
        await _membership();
      }
      await sync.pump(actor!.uid);
      if (generation != _generation) return;
      if (stationSession != null) await _processStation();
      await pull();
      offline = false;
      lastSync = DateTime.now();
      error = null;
    } catch (e) {
      if (generation != _generation) return;
      if (e is AuthFailure && !e.retryable) {
        await logout();
        error = e.message;
        return;
      }
      offline = true;
      error = e is BusinessException
          ? e.message
          : 'Chưa đồng bộ được. Dữ liệu chờ vẫn được giữ trên thiết bị.';
    } finally {
      syncing = false;
      _notify();
    }
  }

  Future<void> pull() async {
    if (actor?.role == StaffRole.driver) {
      final docs = await firestore.query('stores/${config.storeId}', {
        'from': [
          {'collectionId': 'documents'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'kind'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'delivery'},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'payload.driverId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': actor!.uid},
                },
              },
            ],
          },
        },
        'limit': 100,
      }, await currentSession());
      for (final doc in docs) {
        final data = doc.data;
        await db
            .into(db.businessRecords)
            .insertOnConflictUpdate(
              BusinessRecordsCompanion.insert(
                id: data['recordId'] as String,
                kind: 'delivery',
                payload: jsonEncode(data['payload']),
                version: integerField(data, 'version', min: 1),
              ),
            );
      }
      return;
    }
    final cp = await (db.select(
      db.syncCheckpoints,
    )..where((c) => c.storeId.equals(config.storeId))).getSingleOrNull();
    final docs = await firestore.query('stores/${config.storeId}', {
      'from': [
        {'collectionId': 'events'},
      ],
      'where': {
        'fieldFilter': {
          'field': {'fieldPath': 'sequence'},
          'op': 'GREATER_THAN',
          'value': {'integerValue': '${cp?.sequence ?? 0}'},
        },
      },
      'orderBy': [
        {
          'field': {'fieldPath': 'sequence'},
          'direction': 'ASCENDING',
        },
      ],
      'limit': 50,
    }, await currentSession());
    for (final event in docs) {
      await sync.applyEvent(
        storeId: config.storeId,
        eventId: event.name.split('/').last,
        sequence: integerField(event.data, 'sequence', min: 1),
        projections: event.data['projections'] as Map<String, dynamic>,
        details: event.data['payload'] as Map<String, dynamic>?,
        actorId: event.data['actorId'] as String?,
        operation: event.data['operation'] as String?,
        occurredAt: event.data['occurredAt'] as DateTime?,
      );
    }
  }

  Future<void> connectStation(String email, String password) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      throw const AuthFailure('Trạm xác nhận chỉ chạy trên Windows.');
    }
    final candidate = await auth.signIn(email, password);
    final member = await firestore.get(
      'stores/${config.storeId}/members/${candidate.uid}',
      candidate,
    );
    if (member?.data['role'] != 'station' ||
        member?.data['active'] != true ||
        member?.data['mustChangePassword'] != false) {
      throw const AuthFailure('Tài khoản này không có quyền trạm xác nhận.');
    }
    stationSession = candidate;
    await stationVault.write(candidate);
    unawaited(tick());
    _notify();
  }

  Future<void> disconnectStation() async {
    stationSession = null;
    await stationVault.clear();
    _notify();
  }

  Future<AuthSession> _stationToken() async {
    var value = stationSession;
    if (value == null) throw const AuthFailure('Trạm chưa đăng nhập.');
    if (value.expiresAt.isBefore(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
    )) {
      value = await auth.refresh(value);
      stationSession = value;
      await stationVault.write(value);
    }
    return value;
  }

  Future<void> _processStation() async {
    final cursor = await stationVault.readData('cursor');
    final docs = await firestore.query('stores/${config.storeId}', {
      'from': [
        {'collectionId': 'commands'},
      ],
      'orderBy': [
        {
          'field': {'fieldPath': 'createdAt'},
          'direction': 'ASCENDING',
        },
        {
          'field': {'fieldPath': '__name__'},
          'direction': 'ASCENDING',
        },
      ],
      if (cursor != null)
        'startAt': {
          'values': [
            {'timestampValue': cursor['time']},
            {'referenceValue': cursor['name']},
          ],
          'before': false,
        },
      'limit': 20,
    }, await _stationToken());
    for (final doc in docs) {
      final processor = RemoteAuthorityProcessor(
        FirestoreAuthorityStore(firestore, config.storeId, _stationToken),
      );
      await processor.process(doc.name.split('/').last);
      await stationVault.writeData('cursor', {
        'time':
            (doc.rawFields['createdAt'] as Map?)?['timestampValue'] ??
            (doc.data['createdAt'] as DateTime).toUtc().toIso8601String(),
        'name': doc.name,
      });
    }
  }

  Future<void> retry(String commandId) async {
    final row = await (db.select(
      db.outbox,
    )..where((o) => o.id.equals(commandId))).getSingleOrNull();
    if (row == null ||
        row.actorUid != actor?.uid ||
        row.status == 'confirmed' ||
        row.status == 'conflict') {
      throw const BusinessException(
        'permission',
        'Không được gửi lại giao dịch này.',
      );
    }
    await (db.update(db.outbox)..where((o) => o.id.equals(commandId))).write(
      const OutboxCompanion(
        status: Value('pending'),
        attempts: Value(0),
        nextAttemptAt: Value(null),
        lastError: Value(null),
      ),
    );
    await tick();
  }

  Stream<List<BusinessRecord>> records(
    String kind, {
    int offset = 0,
    int limit = 100,
  }) =>
      (db.select(db.businessRecords)
            ..where((r) => r.kind.equals(kind))
            ..orderBy([(r) => OrderingTerm.asc(r.id)])
            ..limit(limit, offset: offset))
          .watch();
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    client.close();
    for (final database in _userDatabases.values) {
      unawaited(database.close());
    }
    super.dispose();
  }
}
