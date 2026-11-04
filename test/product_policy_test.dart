import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/domain/product_policy.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

void main() {
  final catalog = <String, dynamic>{
    'unit': 'viên',
    'units': {'thùng': 12000},
    'priceLists': {'Đại lý': 18000},
    'quantityTiers': [
      {'priceList': 'Đại lý', 'minimum': 20000, 'price': 17000},
      {'priceList': '', 'minimum': 10000, 'price': 19000},
    ],
  };
  test('Conversion and quantity tiers use exact base quantities', () {
    ProductPolicy.validate(catalog);
    final q = ProductPolicy.baseQuantity(catalog, 'viên', 'thùng', 2000);
    expect(q, 24000);
    expect(ProductPolicy.price(catalog, 20000, 'Đại lý', q), 17000);
    expect(ProductPolicy.price(catalog, 20000, '', q), 19000);
    expect(ProductPolicy.price(catalog, 20000, 'Đại lý', 1000), 18000);
    expect(ProductPolicy.price(catalog, 20000, '', 1000), 20000);
  });
  test('Unknown units and precision loss never silently round stock', () {
    expect(
      () => ProductPolicy.baseQuantity(catalog, 'viên', 'pallet', 1000),
      throwsA(isA<BusinessException>()),
    );
    expect(
      () => ProductPolicy.baseQuantity(
        {
          'units': {'lẻ': 333},
        },
        'viên',
        'lẻ',
        1,
      ),
      throwsA(isA<BusinessException>()),
    );
    expect(
      () => ProductPolicy.price({'active': false}, 100, '', 1000),
      throwsA(isA<BusinessException>()),
    );
    expect(
      () => ProductPolicy.validate({
        'unit': 'viên',
        'units': {'viên': 2000},
      }),
      throwsA(isA<BusinessException>()),
    );
  });
}
