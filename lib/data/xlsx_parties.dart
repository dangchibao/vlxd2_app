import 'dart:typed_data';

import 'xlsx_catalog.dart';

class PartyImportRow {
  final int line;
  final Map<String, dynamic> payload;
  final List<String> errors;
  const PartyImportRow(this.line, this.payload, this.errors);
}

class XlsxParties {
  static const headers = [
    'Mã đối tác',
    'Tên đối tác',
    'Loại',
    'Điện thoại',
    'Địa chỉ',
    'Bảng giá',
  ];
  Uint8List export(List<Map<String, dynamic>> rows) =>
      XlsxCatalog().table(headers, [
        for (final row in rows)
          [
            row['code'] ?? row['id'],
            row['name'],
            row['type'],
            row['phone'],
            row['address'],
            row['priceList'],
          ],
      ]);
  List<PartyImportRow> preview(Uint8List bytes, Set<String> known) {
    final result = <PartyImportRow>[], seen = <String>{};
    for (final row in XlsxCatalog().readTable(bytes, headers)) {
      final v = row.values.map((s) => s.trim()).toList(),
          errors = [...row.errors];
      final code = v[0].toUpperCase();
      if (code.isEmpty || code.length > 128) {
        errors.add('Mã đối tác trống hoặc quá dài.');
      }
      if (v[1].isEmpty || v[1].length > 300) {
        errors.add('Tên đối tác trống hoặc quá dài.');
      }
      if (!{'customer', 'supplier', 'both'}.contains(v[2])) {
        errors.add('Loại: customer (khách), supplier (NCC), both (cả hai).');
      }
      if (v[3].length > 50 || v[4].length > 1000 || v[5].length > 64) {
        errors.add('Điện thoại, địa chỉ hoặc tên bảng giá quá dài.');
      }
      if (known.contains(code) || !seen.add(code)) {
        errors.add('Trùng mã đối tác; không tự ghi đè.');
      }
      result.add(
        PartyImportRow(row.line, {
          'code': code,
          'name': v[1],
          'type': v[2],
          'phone': v[3],
          'address': v[4],
          'priceList': v[5],
        }, errors),
      );
    }
    return result;
  }
}
