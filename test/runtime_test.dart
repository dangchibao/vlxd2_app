import 'package:drift/drift.dart' show driftRuntimeOptions;

import 'dart:convert';

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
