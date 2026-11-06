import 'package:drift/drift.dart' show driftRuntimeOptions, Value;

import 'dart:convert';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/firebase_auth_rest.dart';
import 'package:vlxd_bay_hai/data/firestore_rest.dart';
import 'package:vlxd_bay_hai/data/session_vault.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

class MemoryVault extends SessionVault {
  AuthSession? value;
  final data = <String, Map<String, dynamic>>{};
  MemoryVault() : super('fixture');
  @override
  Future<AuthSession?> read() async => value;
  @override
  Future<void> write(AuthSession v) async {
    value = v;
  }

  @override
  Future<Map<String, dynamic>?> readData(String key) async => data[key];
  @override
  Future<void> writeData(String key, Map<String, dynamic> v) async {
    data[key] = Map.from(v);
  }

  @override
  Future<void> clear() async {
    value = null;
    data.remove('profile');
  }
}

void main() {
  test(
    'Debt balances resolve and search synced customer and supplier names',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final runtime = AppRuntime(
        db,
        const AppConnection(
          projectId: 'demo-vlxd-bayhai',
          storeId: 'shop',
          apiKey: 'fixture',
        ),
      );
      addTearDown(() async {
        runtime.dispose();
        await db.close();
      });
      Future<void> add(String kind, String id, Map<String, dynamic> data) => db
          .into(db.businessRecords)
          .insert(
            BusinessRecord(
              id: '$kind:$id',
              kind: kind,
              version: 1,
              payload: jsonEncode({'id': id, ...data}),
            ),
          );
      await add('party', 'kh:01', {'name': 'Khách Hà', 'phone': '0901234567'});
      await add('party', 'ncc', {'name': 'NCC Sơn'});
      await add('receivable', 'kh:01', {'balance': 100});
      await add('receivable', 'missing', {'balance': 200});
      await add('payable', 'ncc', {'balance': 300});

      final customers = await runtime
          .records('receivable', search: 'Khách Hà')
          .first;
      expect(customers.single.id, 'receivable:kh:01');
      expect(jsonDecode(customers.single.payload)['partyName'], 'Khách Hà');
      expect(
        (await runtime.records('receivable', search: '0901234567').first)
            .single
            .id,
        customers.single.id,
      );
      final suppliers = await runtime
          .records('payable', search: 'NCC Sơn')
          .first;
      expect(jsonDecode(suppliers.single.payload)['partyName'], 'NCC Sơn');
      expect(
        await runtime.records('receivable', search: 'NCC Sơn').first,
        isEmpty,
      );
      expect(
        (await runtime.records('receivable', recordId: 'missing').first)
            .single
            .id,
        'receivable:missing',
      );
    },
  );

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  const config = AppConnection(
    projectId: 'demo-vlxd-bayhai',
    apiKey: 'fixture-key',
    storeId: 'shop',
  );
  test('Username mapping is deterministic and refuses ambiguous names', () {
    expect(config.emailFor(' ADMIN '), 'admin+shop@bayhai.invalid');
    expect(
      () => config.emailFor('admin@example.com'),
      throwsA(isA<AuthFailure>()),
    );
  });
  test(
    'Recovery copies only a server-rejected order into a new draft',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var serverStatus = 'confirmed';
      final runtime = AppRuntime(
        db,
        config,
        client: MockClient((request) async {
          expect(request.url.path, endsWith('/receipts/order-command'));
          return http.Response(
            jsonEncode({
              'name': 'receipt',
              'fields': FirestoreRest.encodeFields({
                'commandId': 'order-command',
                'status': serverStatus,
                'result': {'code': 'oversell'},
              }),
            }),
            200,
          );
        }),
        vault: MemoryVault(),
        stationVault: MemoryVault(),
      );
      addTearDown(runtime.dispose);
      const user = Actor('seller', StaffRole.sales);
      runtime.actor = user;
      runtime.session = AuthSession(
        uid: user.uid,
        idToken: 'fixture-token',
        refreshToken: 'fixture-refresh',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
      await runtime.sync.enqueue(
        BusinessCommand(
          id: 'order-command',
          entityId: 'old-order',
          operation: Operation.sale,
          payload: {
            'warehouse': 'main',
            'customerId': 'customer',
            'lines': [
              {'productId': 'pipe', 'quantity': 2500, 'saleUnit': 'm'},
            ],
          },
        ),
        user,
      );
      await db
          .update(db.outbox)
          .write(const OutboxCompanion(status: Value('conflict')));
      await expectLater(
        runtime.recoverRejected('order-command'),
        throwsA(isA<BusinessException>()),
      );
      expect(await db.select(db.drafts).get(), isEmpty);

      serverStatus = 'conflict';
      final draft = await runtime.recoverRejected('order-command');
      final data = jsonDecode(draft.payload) as Map<String, dynamic>;
      expect(draft.id, isNot('old-order'));
      expect(data['recoveredFrom'], 'order-command');
      expect(data['reserveOrder'], true);
      expect(data['items'].single['quantity'], '2,5');
      expect((await db.select(db.outbox).get()).single.id, 'order-command');
    },
  );
  test(
    'Runtime authenticates member and isolates databases when switching users',
    () async {
      final bootstrap = AppDatabase(NativeDatabase.memory());
      addTearDown(bootstrap.close);
      final vault = MemoryVault();
      final client = MockClient((request) async {
        if (request.url.path.contains('signInWithPassword')) {
          final body = jsonDecode(request.body);
          final uid = (body['email'] as String).startsWith('alice')
              ? 'user-alice'
              : 'user-bob';
          return http.Response(
            jsonEncode({
              'localId': uid,
              'idToken': 'fixture-token',
              'refreshToken': 'fixture-refresh',
              'expiresIn': '3600',
            }),
            200,
          );
        }
        if (request.url.path.contains('/members/')) {
          return http.Response(
            jsonEncode({
              'name': 'member',
              'fields': FirestoreRest.encodeFields({
                'role': 'manager',
                'active': true,
                'mustChangePassword': false,
              }),
            }),
            200,
          );
        }
        if (request.url.path.endsWith(':runQuery')) {
          return http.Response('[]', 200);
        }
        return http.Response('{}', 200);
      });
      final runtime = AppRuntime(
        bootstrap,
        config,
        client: client,
        vault: vault,
        stationVault: MemoryVault(),
        databaseFactory: (_) => AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(runtime.dispose);
      await runtime.signIn('alice', 'fixture-password');
      expect(runtime.actor!.uid, 'user-alice');
      while (runtime.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final first = runtime.db;
      await first.addProduct('A', 'Private cache', 'bao', 100);
      await runtime.logout();
      await runtime.signIn('bob', 'fixture-password');
      while (runtime.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(runtime.actor!.uid, 'user-bob');
      expect(identical(first, runtime.db), false);
      expect(await runtime.db.select(runtime.db.products).get(), isEmpty);
    },
  );
  test('Cached verified session permits pending offline commands but expires after 12 hours', () async {
    final bootstrap = AppDatabase(NativeDatabase.memory());
    addTearDown(bootstrap.close);
    final vault = MemoryVault();
    vault.value = AuthSession(
      uid: 'user-one',
      idToken: 'fixture',
      refreshToken: 'fixture',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    vault.data['profile'] = {
      'uid': 'user-one',
      'role': 'sales',
      'active': true,
      'mustChangePassword': false,
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final runtime = AppRuntime(
      bootstrap,
      config,
      client: MockClient((_) async => throw http.ClientException('offline')),
      vault: vault,
      stationVault: MemoryVault(),
      databaseFactory: (_) => AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(runtime.dispose);
    await runtime.restore();
    while (runtime.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(runtime.offline, true);
    expect(runtime.actor!.uid, 'user-one');
    await runtime.enqueue(Operation.sale, 'draft', {
      'lines': [],
    }, syncNow: false);
    expect(
      (await runtime.db.select(runtime.db.outbox).get()).single.status,
      'pending',
    );
  });
  test(
    'Disabled and first-password accounts cannot enqueue business commands',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final runtime = AppRuntime(
        db,
        config,
        client: MockClient((request) async {
          if (request.url.path.contains('signInWithPassword')) {
            return http.Response(
              jsonEncode({
                'localId': 'u',
                'idToken': 'fixture',
                'refreshToken': 'fixture',
                'expiresIn': '3600',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'name': 'member',
              'fields': FirestoreRest.encodeFields({
                'role': 'admin',
                'active': true,
                'mustChangePassword': true,
              }),
            }),
            200,
          );
        }),
        vault: MemoryVault(),
        stationVault: MemoryVault(),
      );
      addTearDown(runtime.dispose);
      await runtime.signIn('admin', 'fixture-password');
      expect(runtime.actor!.mustChangePassword, true);
      await expectLater(
        runtime.enqueue(Operation.sale, 'sale', {}),
        throwsA(isA<BusinessException>()),
      );
    },
  );
  test('Expired token can restore verified offline cache when refresh has no network', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final vault = MemoryVault()
      ..value = AuthSession(
        uid: 'u',
        idToken: 'fixture',
        refreshToken: 'fixture',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
    vault.data['profile'] = {
      'uid': 'u',
      'role': 'sales',
      'active': true,
      'mustChangePassword': false,
      'verifiedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final runtime = AppRuntime(
      db,
      config,
      client: MockClient((_) async => throw http.ClientException('offline')),
      vault: vault,
      stationVault: MemoryVault(),
      databaseFactory: (_) => AppDatabase(NativeDatabase.memory()),
    );
    addTearDown(runtime.dispose);
    await runtime.restore();
    expect(runtime.actor?.uid, 'u');
    expect(runtime.offline, true);
    while (runtime.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await runtime.enqueue(Operation.sale, 'offline', {
      'lines': [],
    }, syncNow: false);
    expect(
      (await runtime.db.select(runtime.db.outbox).get()).single.status,
      'pending',
    );
  });
  test('A delayed old token refresh cannot replace a new user session after logout', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final started = Completer<void>(), response = Completer<http.Response>();
    final runtime = AppRuntime(
      db,
      config,
      client: MockClient((_) async {
        started.complete();
        return response.future;
      }),
      vault: MemoryVault(),
      stationVault: MemoryVault(),
    );
    addTearDown(runtime.dispose);
    runtime.session = AuthSession(
      uid: 'old',
      idToken: 'old-fixture',
      refreshToken: 'old-fixture',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    );
    final refresh = runtime.currentSession();
    await started.future;
    await runtime.logout();
    runtime.session = AuthSession(
      uid: 'new',
      idToken: 'new-fixture',
      refreshToken: 'new-fixture',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final check = expectLater(refresh, throwsA(isA<AuthFailure>()));
    response.complete(
      http.Response(
        jsonEncode({
          'user_id': 'old',
          'id_token': 'refreshed-old',
          'refresh_token': 'old-fixture',
          'expires_in': '3600',
        }),
        200,
      ),
    );
    await check;
    expect(runtime.session?.uid, 'new');
  });
  for (final offset in [const Duration(hours: -13), const Duration(hours: 1)]) {
    test(
      'Offline cache refuses expired or future verification time $offset',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final vault = MemoryVault()
          ..value = AuthSession(
            uid: 'u',
            idToken: 'fixture',
            refreshToken: 'fixture',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          );
        vault.data['profile'] = {
          'uid': 'u',
          'role': 'sales',
          'active': true,
          'mustChangePassword': false,
          'verifiedAt': DateTime.now().toUtc().add(offset).toIso8601String(),
        };
        final runtime = AppRuntime(
          db,
          config,
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
          vault: vault,
          stationVault: MemoryVault(),
          databaseFactory: (_) => AppDatabase(NativeDatabase.memory()),
        );
        addTearDown(runtime.dispose);
        await runtime.restore();
        expect(runtime.actor, isNull);
        expect(runtime.session, isNull);
      },
    );
  }
}
