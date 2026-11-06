import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/app.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/features/login_gate.dart';
import 'package:vlxd_bay_hai/features/bayhai_style.dart';

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
    for (final (type, name) in [
      ('customer', 'Khách mẫu'),
      ('supplier', 'NCC mẫu'),
    ]) {
      await db
          .into(db.businessRecords)
          .insert(
            BusinessRecord(
              id: 'party:$type',
              kind: 'party',
              version: 1,
              payload: jsonEncode({'id': type, 'type': type, 'name': name}),
            ),
          );
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: BayHaiStyle.theme,
          home: SessionScope(runtime: runtime, child: const Workspace()),
        ),
      ),
    );
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Nhà cung cấp'), findsOneWidget);
    expect(find.text('Khách hàng'), findsOneWidget);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      BayHaiStyle.navy,
    );
    final nav = find.byType(NavigationBar);
    await tester.tap(find.text('Khách hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Khách mẫu'), findsOneWidget);
    expect(find.text('NCC mẫu'), findsNothing);
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Trang chủ')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhà cung cấp'));
    await tester.pumpAndSettle();
    expect(find.text('NCC mẫu'), findsOneWidget);
    expect(find.text('Khách mẫu'), findsNothing);
    await tester.tap(find.descendant(of: nav, matching: find.text('Kho')));
    await tester.pump();
    expect(find.text('Tồn kho đã xác nhận'), findsOneWidget);
    await tester.tap(find.descendant(of: nav, matching: find.text('Thêm')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Nhân viên'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}
