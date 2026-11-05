import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/features/business_receipt.dart';

class RecoveryRuntime extends AppRuntime {
  RecoveryRuntime(AppDatabase database)
    : super(
        database,
        const AppConnection(
          projectId: 'demo-vlxd-bayhai',
          storeId: 'shop',
          apiKey: 'fixture-key',
        ),
      ) {
    actor = const Actor('manager', StaffRole.manager);
  }

  final reports = <Map<String, dynamic>>[];

  @override
  Future<String> enqueue(
    Operation operation,
    String entityId,
    Map<String, dynamic> payload, {
    int expectedVersion = 0,
    bool syncNow = true,
  }) async {
    reports.add({
      'operation': operation,
      'entityId': entityId,
      'version': expectedVersion,
      ...payload,
    });
    return 'fixture-command';
  }
}

void main() {
  testWidgets(
    'A saved Windows result can sync without submitting another print',
    (tester) async {
      const channel = MethodChannel('net.nfet.printing');
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        platformCalls.add(call.method);
        return <String, dynamic>{};
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final db = AppDatabase(NativeDatabase.memory());
      final runtime = RecoveryRuntime(db);
      addTearDown(runtime.dispose);
      await db
          .into(db.printJobs)
          .insert(
            PrintJobsCompanion.insert(
              id: 'request-1',
              documentId: 'assemble:assembly-1',
              pdfBytes: Uint8List.fromList([37, 80, 68, 70]),
              status: const Value('sent_to_system'),
              createdAt: DateTime(2026, 11, 6),
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessReceipt(
            database: db,
            kind: 'assemble',
            data: const {'id': 'assembly-1'},
            runtime: runtime,
            requestId: 'request-1',
            requestVersion: 2,
            claimToken: 'local-token',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final print = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'In phiếu',
        ),
      );
      expect(print.onPressed, isNull);
      final report = find.text('Đồng bộ kết quả đã lưu');
      await tester.tap(report);
      await tester.pumpAndSettle();

      expect(runtime.reports, [
        {
          'operation': Operation.printResult,
          'entityId': 'request-1',
          'version': 2,
          'claimToken': 'local-token',
          'status': 'sent_to_system',
          'note': 'Kết quả ghi trong nhật ký của máy Windows.',
        },
      ]);
      expect(
        find.text('Đã lưu kết quả để đồng bộ về hàng đợi.'),
        findsOneWidget,
      );
      expect(platformCalls, isNot(contains('printPdf')));
      expect((await db.select(db.printJobs).get()).length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
}
