import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/features/catalog_art.dart';

void main() {
  testWidgets('Bundled sample catalog shows and filters the reference SKUs', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: SampleCatalog()));
      await rootBundle.loadString('$catalogArt/samples.json');
    });
    await tester.pumpAndSettle();
    expect(find.text('PR0606VD'), findsOneWidget);
    expect(find.byType(ProductPhoto), findsNWidgets(5));

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.enterText(find.byType(TextField), 'VC6060XM');
    await tester.pumpAndSettle();
    expect(find.text('Viglacera xám nhạt'), findsOneWidget);
    expect(find.byType(ProductPhoto), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
