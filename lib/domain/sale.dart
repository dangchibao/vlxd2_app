class SaleLine {
  final String productId, sku, name, unit;
  final int price, quantity;
  const SaleLine({
    required this.productId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.price,
    this.quantity = 1,
  });
  int get total => price * quantity;
  SaleLine withQuantity(int value) {
    if (value < 1 || value > 1000000) {
      throw ArgumentError('Số lượng từ 1 đến 1.000.000');
    }
    return SaleLine(
      productId: productId,
      sku: sku,
      name: name,
      unit: unit,
      price: price,
      quantity: value,
    );
  }

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'sku': sku,
    'name': name,
    'unit': unit,
    'price': price,
    'quantity': quantity,
  };
  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
    productId: j['productId'] as String,
    sku: j['sku'] as String,
    name: j['name'] as String,
    unit: j['unit'] as String,
    price: j['price'] as int,
    quantity: j['quantity'] as int,
  );
}

class SaleTotals {
  final List<SaleLine> lines;
  final int discount, paid;
  SaleTotals(this.lines, {this.discount = 0, this.paid = 0}) {
    if (discount < 0 ||
        paid < 0 ||
        discount > subtotal ||
        paid > total ||
        subtotal > 9000000000000) {
      throw ArgumentError('Tiền thanh toán hoặc chiết khấu không hợp lệ');
    }
  }
  int get subtotal => lines.fold(0, (s, l) => s + l.total);
  int get total => subtotal - discount;
  int get debt => total - paid;
}
