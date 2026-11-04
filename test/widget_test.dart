import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/app.dart';
import 'package:vlxd_bay_hai/data/database.dart';

const product = Product(
  id: '1',
  sku: 'XM01',
  name: 'Xi măng',
  unit: 'bao',
  price: 95000,
);
void main() {
  testWidgets('Catalog shows repository products', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsProvider.overrideWith((_) => Stream.value([product])),
        ],
        child: const MaterialApp(home: Scaffold(body: Catalog())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Xi măng'), findsOneWidget);
  });
  testWidgets('Sale recomputes before losing focus', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsProvider.overrideWith((_) => Stream.value([product])),
        ],
        child: const MaterialApp(home: Scaffold(body: SaleEditor())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Xi');
    await tester.pump();
    await tester.tap(find.text('Xi măng'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.pump();
    expect(find.text('Tổng tiền: 285.000 đ'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '');
    await tester.pump();
    expect(find.text('Tổng tiền: 285.000 đ'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
