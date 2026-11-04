import 'operations.dart';

/// Provider-neutral preparation only. No issuance method or assumed tax rate.
class ElectronicInvoiceDraft {
  final Map<String, dynamic> buyer;
  final List<Map<String, dynamic>> lines;
  final String saleId;
  final int total;
  const ElectronicInvoiceDraft(this.saleId, this.buyer, this.lines, this.total);
  factory ElectronicInvoiceDraft.fromSale(
    Map<String, dynamic> sale, {
    required Map<String, dynamic> buyer,
    required Map<String, Map<String, dynamic>> taxByProduct,
  }) {
    if (sale['status'] != 'posted') {
      throw const BusinessException(
        'invoice',
        'Chỉ chuẩn bị từ đơn đã ghi sổ.',
      );
    }
    final items = <Map<String, dynamic>>[];
    for (final line in sale['lines'] as List) {
      items.add({
        'productId': line['productId'],
        'sku': line['sku'],
        'name': line['name'],
        'unit': line['unit'],
        'quantityScaled': line['quantity'],
        'quantityScale': 1000,
        'unitPriceVnd': line['unitPrice'],
        'netAmountVnd': line['netTotal'],
        'taxConfiguration':
            line['taxConfiguration'] ?? taxByProduct[line['productId']],
      });
    }
    if ((sale['surcharge'] as int? ?? 0) > 0) {
      items.add({
        'productId': 'delivery-surcharge',
        'name': 'Phụ thu theo đơn',
        'quantityScaled': 1000,
        'quantityScale': 1000,
        'netAmountVnd': sale['surcharge'],
        'taxConfiguration': null,
      });
    }
    return ElectronicInvoiceDraft(
      textField(sale, 'id'),
      Map.unmodifiable(buyer),
      List.unmodifiable(items),
      integerField(sale, 'total'),
    );
  }
  bool get readyForProviderValidation =>
      buyer['name'] is String &&
      (buyer['name'] as String).trim().isNotEmpty &&
      lines.every((l) => l['taxConfiguration'] != null);
  Map<String, dynamic> toJson() => {
    'format': 'bayhai-einvoice-draft-v1',
    'saleId': saleId,
    'buyer': buyer,
    'lines': lines,
    'totalVnd': total,
    'status': 'preparationOnly',
  };
}

abstract interface class ElectronicInvoiceAdapter {
  String get providerName;
  Future<List<String>> validate(ElectronicInvoiceDraft draft);
}
