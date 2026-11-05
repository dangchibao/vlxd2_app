import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/app_runtime.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/features/login_gate.dart';

void main() {
  testWidgets('Login preserves usable form width next to the showroom', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final runtime = AppRuntime(
      database,
      const AppConnection(
        projectId: 'demo-vlxd-bayhai',
        apiKey: 'fixture-key',
        storeId: 'shop',
      ),
    );
    addTearDown(database.close);
    addTearDown(runtime.dispose);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginGate(runtime: runtime, child: const SizedBox()),
      ),
    );
    final form = find.byType(TextField).first;
    expect(tester.getSize(form).width, greaterThan(320));
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(tester.getSize(form).width, greaterThan(240));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
