import 'operations.dart';

class ProductPolicy {
  static void validate(Map<String, dynamic> data) {
    for (final key in [
      'group',
      'barcode',
      'brand',
      'model',
      'variantOf',
      'imageUrl',
    ]) {
      final value = data[key];
      if (value != null && (value is! String || value.length > 1000)) {
        throw BusinessException('validation', 'Thông tin $key không hợp lệ.');
      }
    }
    if (data['active'] != null && data['active'] is! bool) {
      throw const BusinessException(
        'validation',
        'Trạng thái kinh doanh không hợp lệ.',
      );
    }
    if (data['minimumStock'] != null) integerField(data, 'minimumStock');
    if (data['tax'] != null) {
      final tax = data['tax'];
      if (tax is! Map<String, dynamic> ||
          !{'rate', 'exempt', 'outsideScope'}.contains(tax['treatment'])) {
        throw const BusinessException(
          'validation',
          'Phân loại thuế chưa hợp lệ.',
        );
      }
      if (tax['treatment'] == 'rate') {
        integerField(tax, 'rateBasisPoints', max: 10000);
      }
    }
    final attributes = data['attributes'] ?? <String, dynamic>{};
    if (attributes is! Map ||
        attributes.length > 50 ||
        attributes.entries.any(
          (e) =>
              e.key is! String ||
              (e.key as String).length > 100 ||
              e.value is! String ||
              (e.value as String).length > 1000,
        )) {
      throw const BusinessException(
        'validation',
        'Thuộc tính tối đa 50 dòng văn bản.',
      );
    }
    final units = data['units'] ?? <String, dynamic>{};
    if (units is! Map || units.length > 20) {
      throw const BusinessException(
        'validation',
        'Danh sách đơn vị không hợp lệ.',
      );
    }
    for (final entry in units.entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          (entry.key as String).length > 30 ||
          entry.value is! int ||
          (entry.value as int) <= 0 ||
          (entry.value as int) > 1000000000) {
        throw const BusinessException(
          'validation',
          'Quy đổi đơn vị phải dương và tối đa 3 số lẻ.',
        );
      }
      if (entry.key == data['unit'] && entry.value != 1000) {
        throw const BusinessException(
          'validation',
          'Đơn vị gốc luôn có hệ số 1.',
        );
      }
    }
    final prices = data['priceLists'] ?? <String, dynamic>{};
    if (prices is! Map || prices.length > 20) {
      throw const BusinessException('validation', 'Bảng giá không hợp lệ.');
    }
    for (final entry in prices.entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          (entry.key as String).length > 64) {
        throw const BusinessException(
          'validation',
          'Tên bảng giá không hợp lệ.',
        );
      }
      integerField({'price': entry.value}, 'price', max: 1000000000000);
    }
    final tiers = data['quantityTiers'] ?? <dynamic>[];
    if (tiers is! List || tiers.length > 50) {
      throw const BusinessException(
        'validation',
        'Tối đa 50 mức giá số lượng.',
      );
    }
    final seen = <String>{};
    for (final tier in tiers) {
      if (tier is! Map<String, dynamic>) {
        throw const BusinessException(
          'validation',
          'Mức giá số lượng không hợp lệ.',
        );
      }
      integerField(tier, 'minimum', min: 1);
      integerField(tier, 'price', max: 1000000000000);
      final list = tier['priceList'] as String? ?? '';
      if (!seen.add('$list:${tier['minimum']}')) {
        throw const BusinessException(
          'duplicate',
          'Mức giá số lượng bị trùng.',
        );
      }
    }
  }

  static int baseQuantity(
    Map<String, dynamic> catalog,
    String baseUnit,
    String selectedUnit,
    int quantity,
  ) {
    if (selectedUnit == baseUnit) return quantity;
    final factor = (catalog['units'] as Map?)?[selectedUnit];
    if (factor is! int || factor <= 0) {
      throw const BusinessException(
        'unit',
        'Đơn vị chưa được cấu hình quy đổi.',
      );
    }
    final raw = BigInt.from(quantity) * BigInt.from(factor);
    if (raw % BigInt.from(1000) != BigInt.zero) {
      throw const BusinessException(
        'unit',
        'Số lượng quy đổi nhỏ hơn độ chính xác hỗ trợ.',
      );
    }
    final result = raw ~/ BigInt.from(1000);
    if (result > BigInt.from(1000000000) || result <= BigInt.zero) {
      throw const BusinessException('unit', 'Số lượng quy đổi vượt giới hạn.');
    }
    return result.toInt();
  }

  static int price(
    Map<String, dynamic> catalog,
    int defaultPrice,
    String priceList,
    int baseQuantity,
  ) {
    if (catalog['active'] == false) {
      throw const BusinessException(
        'inactive',
        'Hàng hóa đã ngừng kinh doanh.',
      );
    }
    var price =
        (catalog['priceLists'] as Map?)?[priceList] as int? ?? defaultPrice;
    var threshold = 0;
    for (final tier in catalog['quantityTiers'] as List? ?? []) {
      final minimum = tier['minimum'] as int;
      if ((tier['priceList'] ?? '') == priceList &&
          minimum <= baseQuantity &&
          minimum > threshold) {
        threshold = minimum;
        price = tier['price'] as int;
      }
    }
    return price;
  }
}
