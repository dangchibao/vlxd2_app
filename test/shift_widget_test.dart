import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';
import 'package:vlxd_bay_hai/features/business_pages.dart';
import 'package:vlxd_bay_hai/features/shift_close.dart';

void main() {
  testWidgets('Cash count difference updates while typing without blur', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final runtime = AppRuntime(
      db,
      const AppConnection(projectId: '', apiKey: ''),
    )..actor = const Actor('u', StaffRole.manager);
    addTearDown(runtime.dispose);
    await db
        .into(db.businessRecords)
        .insert(
          BusinessRecordsCompanion.insert(
            version: 1,
            id: 'shiftTotals:${currentShift(runtime)}',
            kind: 'shiftTotals',
            payload: jsonEncode({'cashNet': 80000, 'bankNet': 300000}),
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftCloseDialog(runtime: runtime)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tiền mặt dự kiến: 80.000 đ'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Tiền đầu ca (VND)'),
      '20000',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tiền thực đếm (VND)'),
      '95000',
    );
    await tester.pumpAndSettle();
    expect(find.text('Tiền mặt dự kiến: 100.000 đ'), findsOneWidget);
    expect(find.text('Chênh lệch: -5.000 đ'), findsOneWidget);
    expect(find.text('Chuyển khoản đối soát riêng: 300.000 đ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
