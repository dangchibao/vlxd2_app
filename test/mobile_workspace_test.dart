import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/app.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/features/login_gate.dart';

void main() {
  testWidgets('Authenticated mobile navigation opens stock and the full menu', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final runtime = AppRuntime(
      db,
      const AppConnection(
        projectId: 'demo-vlxd-bayhai',
        storeId: 'shop',
        apiKey: 'fixture-key',
      ),
    )..actor = const Actor('admin', StaffRole.admin);
    addTearDown(runtime.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SessionScope(runtime: runtime, child: const Workspace()),
        ),
      ),
    );
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    final nav = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: nav, matching: find.text('Kho')));
    await tester.pump();
    expect(find.text('Tồn kho đã xác nhận'), findsOneWidget);
    await tester.tap(find.descendant(of: nav, matching: find.text('Thêm')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
