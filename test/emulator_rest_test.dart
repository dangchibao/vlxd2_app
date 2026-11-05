import 'package:drift/native.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';

import 'runtime_test.dart' show MemoryVault;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vlxd_bay_hai/data/firebase_auth_rest.dart';
import 'package:vlxd_bay_hai/data/firestore_rest.dart';
import 'package:vlxd_bay_hai/data/firestore_authority_store.dart';
import 'package:vlxd_bay_hai/data/sync_engine.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/domain/stock_period.dart';

const enabled = bool.fromEnvironment('BAYHAI_EMULATOR_TESTS');
void main() {
  test(
    'Windows-compatible REST Auth + Firestore transaction round trip',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      const project = 'demo-vlxd-bayhai';
      final email =
          'station-${DateTime.now().microsecondsSinceEpoch}@example.test';
      // Ephemeral fixture credentials are never used outside the localhost emulator.
      final password = 'fixture-${DateTime.now().microsecondsSinceEpoch}';
      final signup = await client.post(
        Uri.parse(
          'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      expect(signup.statusCode, 200);
      final uid = jsonDecode(signup.body)['localId'] as String;
      final member = await client.patch(
        Uri.parse(
          'http://127.0.0.1:8080/v1/projects/$project/databases/(default)/documents/stores/shop/members/$uid',
        ),
        headers: {
          'Authorization': 'Bearer owner',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fields': FirestoreRest.encodeFields({
            'role': 'station',
            'active': true,
            'mustChangePassword': false,
          }),
        }),
      );
      expect(member.statusCode, 200);
      final auth = FirebaseAuthRest(
        client: client,
        apiKey: 'demo-key',
        emulator: Uri.parse('http://127.0.0.1:9099'),
      );
      var session = await auth.signIn(email, password);
      expect(session.uid, uid);
      session = await auth.refresh(session);
      session = await auth.changePassword(session, '$password-changed');
      final store = FirestoreRest(
        client: client,
        projectId: project,
        emulator: Uri.parse('http://127.0.0.1:8080'),
      );
      final path = 'stores/shop/balances/$uid';
      await store.commit(session, [
        store.createWrite(path, {'quantity': 1000, 'value': 20000}),
      ]);
      final first = (await store.get(path, session))!;
      expect(first.data['quantity'], 1000);
      final transaction = await store.begin(session);
      final snapshot = (await store.get(
        path,
        session,
        transaction: transaction,
      ))!;
      await store.commit(session, [
        store.updateWrite(snapshot, {'quantity': 0, 'value': 0}),
      ], transaction: transaction);
      expect((await store.get(path, session))!.data['quantity'], 0);
      await expectLater(
        store.commit(session, [
          store.updateWrite(first, {'quantity': 999, 'value': 999}),
        ]),
        throwsA(isA<FirestoreFailure>()),
      );
      final managerEmail = 'manager-$uid@example.test';
      final managerSignup = await client.post(
        Uri.parse(
          'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': managerEmail,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      expect(managerSignup.statusCode, 200);
      final managerUid = jsonDecode(managerSignup.body)['localId'] as String;
      await client.patch(
        Uri.parse(
          'http://127.0.0.1:8080/v1/projects/$project/databases/(default)/documents/stores/shop/members/$managerUid',
        ),
        headers: {
          'Authorization': 'Bearer owner',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fields': FirestoreRest.encodeFields({
            'role': 'manager',
            'active': true,
            'mustChangePassword': false,
          }),
        }),
      );
      final manager = await auth.signIn(managerEmail, password);
      final productId = 'product-$uid';
      final transport = FirestoreCommandTransport(
        store,
        'shop',
        () async => manager,
      );
      RemoteAuthorityProcessor processor() => RemoteAuthorityProcessor(
        FirestoreAuthorityStore(store, 'shop', () async => session),
      );
      final catalog = BusinessCommand(
        id: 'catalog-$uid',
        entityId: productId,
        operation: Operation.catalog,
        payload: {
          'sku': 'A-$uid',
          'name': 'Gạch',
          'unit': 'viên',
          'price': 20000,
          'tracking': 'lot',
        },
      );
      await transport.submit(catalog, manager.uid);
      expect((await processor().process(catalog.id))['tracking'], 'lot');
      const allocations = [
        {'lotId': 'A', 'quantity': 600, 'colorCode': 'BE'},
        {'lotId': 'B', 'quantity': 400, 'colorCode': 'BE'},
      ];
      final purchase = BusinessCommand(
        id: 'purchase-$uid',
        entityId: 'po-$uid',
        operation: Operation.purchase,
        payload: {
          'warehouse': 'main',
          'supplierId': 'supplier',
          'lines': [
            {'productId': productId, 'quantity': 1000, 'unitCost': 10000},
          ],
        },
      );
      await transport.submit(purchase, manager.uid);
      final firstResult = await processor().process(purchase.id);
      expect(firstResult['status'], 'ordered');
      expect(await processor().process(purchase.id), firstResult);
      final receive = BusinessCommand(
        id: 'receive-$uid',
        entityId: 'po-$uid',
        operation: Operation.receive,
        expectedVersion: 1,
        payload: {
          'lines': [
            {
              'productId': productId,
              'quantity': 1000,
              'lotAllocations': allocations,
            },
          ],
        },
      );
      await transport.submit(receive, manager.uid);
      await processor().process(receive.id);
      final sales = [
        for (var i = 0; i < 2; i++)
          BusinessCommand(
            id: 'sale-$i-$uid',
            entityId: 'sale-$i-$uid',
            operation: Operation.sale,
            payload: {
              'warehouse': 'main',
              'customerId': 'customer',
              'discount': 0,
              'lines': [
                {
                  'productId': productId,
                  'quantity': 1000,
                  'expectedPrice': 20000,
                  'lotAllocations': allocations,
                },
              ],
            },
          ),
      ];
      for (final sale in sales) {
        await transport.submit(sale, manager.uid);
      }
      await Future.wait(sales.map((sale) => processor().process(sale.id)));
      final receipts = await Future.wait(
        sales.map((sale) => transport.receipt(sale.id)),
      );
      expect(receipts.where((r) => r?.status == 'confirmed').length, 1);
      expect(
        (receipts.singleWhere((r) => r?.status == 'confirmed')!.result['lines']
                as List)
            .single['lotAllocations'],
        allocations,
      );
      expect(receipts.where((r) => r?.status == 'error').length, 1);
      final authority = FirestoreAuthorityStore(
        store,
        'shop',
        () async => session,
      );
      final stock = await authority.transaction(
        () =>
            authority.record('stock', jsonEncode(['main', productId, 'good'])),
      );
      expect(jsonDecode(stock!.payload)['quantity'], 0);
      final base = AppDatabase(NativeDatabase.memory());
      final userVault = MemoryVault();
      await userVault.write(manager);
      final stationVault = MemoryVault();
      await stationVault.write(session);
      final runtime = AppRuntime(
        base,
        AppConnection(
          projectId: project,
          apiKey: 'demo-key',
          storeId: 'shop',
          authEmulator: Uri.parse('http://127.0.0.1:9099'),
          firestoreEmulator: Uri.parse('http://127.0.0.1:8080'),
        ),
        vault: userVault,
        stationVault: stationVault,
        databaseFactory: (_) => AppDatabase(NativeDatabase.memory()),
      );
      addTearDown(() async {
        runtime.dispose();
        await base.close();
      });
      await runtime.restore();
      while (runtime.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final paidSale =
          sales[receipts.indexWhere((r) => r?.status == 'confirmed')];
      final paymentId = await runtime.enqueue(
        Operation.debtCollection,
        'customer',
        {
          'amount': 5000,
          'method': 'cash',
          'shiftId': 'fixture-shift',
          'allocations': [
            {'documentId': paidSale.entityId, 'amount': 5000, 'version': 1},
          ],
        },
        expectedVersion: 1,
      );
      while (runtime.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect((await transport.receipt(paymentId))?.status, 'confirmed');
      final paid =
          await (runtime.db.select(runtime.db.businessRecords)
                ..where((row) => row.id.equals('sale:${paidSale.entityId}')))
              .getSingle();
      expect(jsonDecode(paid.payload)['debt'], 15000);
      final period = StockPeriod.fromLedger(
        await runtime.db.select(runtime.db.inboxEvents).get(),
        await runtime.db.select(runtime.db.businessEvents).get(),
        DateTime.now().subtract(const Duration(days: 1)),
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(period.missingHistory, 0);
      final periodStock = period.balances.singleWhere(
        (row) => row.item.position.$2 == productId,
      );
      expect(periodStock.incoming, BigInt.from(1000));
      expect(periodStock.outgoing, BigInt.from(1000));
      expect(periodStock.closing, BigInt.zero);

      Future<Map<String, dynamic>> confirmAssemblyFixture(
        Operation operation,
        String entityId,
        Map<String, dynamic> payload, {
        int version = 0,
      }) async {
        final id = await runtime.enqueue(
          operation,
          entityId,
          payload,
          expectedVersion: version,
        );
        while (runtime.syncing) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final result = await transport.receipt(id);
        expect(result?.status, 'confirmed', reason: '${result?.result}');
        return result!.result;
      }

      final replenishmentId = 'replenishment-$uid';
      await confirmAssemblyFixture(Operation.purchase, replenishmentId, {
        'warehouse': 'main',
        'supplierId': 'supplier',
        'lines': [
          {'productId': productId, 'quantity': 1000, 'unitCost': 10000},
        ],
      });
      await confirmAssemblyFixture(Operation.receive, replenishmentId, {
        'lines': [
          {
            'productId': productId,
            'quantity': 1000,
            'lotAllocations': allocations,
          },
        ],
      }, version: 1);
      final kitId = 'kit-$uid';
      await confirmAssemblyFixture(Operation.catalog, kitId, {
        'sku': 'KIT-$uid',
        'name': 'Bộ thử',
        'unit': 'bộ',
        'price': 30000,
        'tracking': 'serial',
        'components': {'A-${uid.toUpperCase()}': 1000},
      });
      final assemblyId = 'assembly-$uid';
      final serial = 'KIT-${uid.toUpperCase()}';
      final assembled = await confirmAssemblyFixture(
        Operation.assemble,
        assemblyId,
        {
          'warehouse': 'main',
          'productId': kitId,
          'kits': 1,
          'catalogVersion': 1,
          'componentTracking': [
            {'sku': 'A-$uid', 'lotAllocations': allocations},
          ],
          'outputTracking': {
            'serials': [serial],
          },
        },
      );
      expect(assembled['value'], 10000);
      final cachedSerial = await (runtime.db.select(
        runtime.db.businessRecords,
      )..where((r) => r.id.equals('serial:$serial'))).getSingle();
      expect(jsonDecode(cachedSerial.payload)['assemblyId'], assemblyId);
      final catalogId = 'catalog-$uid';
      final commandId = await runtime.enqueue(Operation.catalog, catalogId, {
        'sku': 'SYNC-$uid',
        'name': 'Đồng bộ hoàn chỉnh',
        'unit': 'bao',
        'price': 15000,
      });
      while (runtime.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await runtime.retry(commandId);
      final cached = await (runtime.db.select(
        runtime.db.products,
      )..where((p) => p.id.equals(catalogId))).getSingleOrNull();
      expect(cached!.name, 'Đồng bộ hoàn chỉnh');
      expect(
        (await (runtime.db.select(
          runtime.db.outbox,
        )..where((o) => o.id.equals(commandId))).getSingle()).status,
        'confirmed',
      );
      // Direct malformed payloads must receive a rejection and not poison the
      // station cursor or block a valid command submitted afterwards.
      for (var i = 0; i < 4; i++) {
        final badId = 'malformed-$uid-$i';
        final write = store.createWrite('stores/shop/commands/$badId', {
          'commandId': badId,
          'actorUid': managerUid,
          'operation': i == 3 ? 'unknownOperation' : 'party',
          'entityId': 'invalid-party-$uid-$i',
          'expectedVersion': 0,
          'payload': {
            'name': 'Malformed fixture',
            'type': 'customer',
            'phone': i == 0
                ? 123
                : i == 1
                ? DateTime.now().toUtc()
                : 'fixture',
          },
        });
        if (i == 2) {
          final fields =
              (write['update'] as Map<String, dynamic>)['fields']
                  as Map<String, dynamic>;
          final payload =
              ((fields['payload'] as Map<String, dynamic>)['mapValue']
                      as Map<String, dynamic>)['fields']
                  as Map<String, dynamic>;
          payload['unsupported'] = {
            'geoPointValue': {'latitude': 10.0, 'longitude': 106.0},
          };
        }
        write['updateTransforms'] = [
          {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
        ];
        await store.commit(manager, [write]);
      }
      final goodAfterId = 'after-malformed-$uid';
      await runtime.enqueue(Operation.catalog, goodAfterId, {
        'sku': 'AFTER-$uid',
        'name': 'Valid after malformed queue',
        'unit': 'bao',
        'price': 100,
      });
      while (runtime.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await runtime.tick();
      for (var i = 0; i < 4; i++) {
        final rejection = await store.get(
          'stores/shop/receipts/malformed-$uid-$i',
          manager,
        );
        expect(rejection?.data['status'], 'error');
        expect(
          (rejection!.data['fingerprint'] as String).length,
          lessThan(100),
        );
      }
      expect(
        await (runtime.db.select(
          runtime.db.products,
        )..where((p) => p.id.equals(goodAfterId))).getSingleOrNull(),
        isNotNull,
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
