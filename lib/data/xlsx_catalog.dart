import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'database.dart';

class CatalogImportRow {
  final int line;
  final String sku, name, unit;
  final int? price;
  final List<String> errors;
  const CatalogImportRow(
    this.line,
    this.sku,
    this.name,
    this.unit,
    this.price,
    this.errors,
  );
  Map<String, dynamic> get payload => {
    'sku': sku,
    'name': name,
    'unit': unit,
    'price': price,
  };
}

class SheetImportRow {
  final int line;
  final List<String> values, errors;
  const SheetImportRow(this.line, this.values, this.errors);
}

class XlsxCatalog {
  static const headers = ['SKU', 'Tên hàng', 'Đơn vị', 'Giá bán'];
  Uint8List export(List<Product> products) => table(headers, [
    for (final p in products) [p.sku, p.name, p.unit, p.price],
  ]);
  Uint8List table(List<String> headers, List<List<Object?>> rows) {
    if (rows.length > 20000) {
      throw const FormatException('Tối đa 20.000 dòng mỗi file.');
    }
    String escaped(Object? s) => XmlText('${s ?? ''}').toXmlString();
    String column(int n) {
      var value = n + 1, result = '';
      while (value > 0) {
        value--;
        result = String.fromCharCode(65 + value % 26) + result;
        value ~/= 26;
      }
      return result;
    }

    final sheet = StringBuffer(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
    );
    final all = <List<Object?>>[headers, ...rows];
    for (var r = 0; r < all.length; r++) {
      sheet.write('<row r="${r + 1}">');
      for (var c = 0; c < all[r].length; c++) {
        final value = all[r][c], ref = '${column(c)}${r + 1}';
        if (value is int) {
          sheet.write('<c r="$ref"><v>$value</v></c>');
        } else {
          sheet.write(
            '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${escaped(value)}</t></is></c>',
          );
        }
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData></worksheet>');
    final files = {
      '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
      '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml': '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="DuLieu" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml': sheet.toString(),
    };
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.string(entry.key, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  void _preflight(Uint8List bytes) {
    if (bytes.length > 10 * 1024 * 1024 || bytes.length < 22) {
      throw const FormatException('File XLSX rỗng hoặc vượt 10 MB.');
    }
    final data = ByteData.sublistView(bytes);
    var end = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (data.getUint32(i, Endian.little) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException('File không phải XLSX hợp lệ.');
    final count = data.getUint16(end + 10, Endian.little);
    var pos = data.getUint32(end + 16, Endian.little), total = 0;
    if (count > 1000 || count == 65535) {
      throw const FormatException('File có quá nhiều thành phần.');
    }
    for (var i = 0; i < count; i++) {
      if (pos + 46 > bytes.length ||
          data.getUint32(pos, Endian.little) != 0x02014b50) {
        throw const FormatException('Cấu trúc file hỏng.');
      }
      final size = data.getUint32(pos + 24, Endian.little);
      total += size;
      if (size > 25 * 1024 * 1024 || total > 50 * 1024 * 1024) {
        throw const FormatException('Nội dung giải nén vượt giới hạn.');
      }
      if (data.getUint16(pos + 8, Endian.little) & 1 != 0) {
        throw const FormatException('Không nhận file ZIP mã hóa.');
      }
      pos +=
          46 +
          data.getUint16(pos + 28, Endian.little) +
          data.getUint16(pos + 30, Endian.little) +
          data.getUint16(pos + 32, Endian.little);
    }
  }

  List<SheetImportRow> readTable(
    Uint8List bytes,
    List<String> expectedHeaders,
  ) {
    _preflight(bytes);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    XmlDocument xml(String path) {
      final file = archive.findFile(path);
      if (file == null) throw FormatException('Thiếu $path');
      final text = utf8.decode(file.content);
      if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
        throw const FormatException('Không hỗ trợ XML có khai báo ngoài.');
      }
      return XmlDocument.parse(text);
    }

    final workbook = xml('xl/workbook.xml');
    final sheets = workbook.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'sheet',
    );
    if (sheets.isEmpty) throw const FormatException('Workbook không có sheet.');
    final id = sheets.first.getAttribute(
      'id',
      namespaceUri:
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    );
    final relationships = xml('xl/_rels/workbook.xml.rels');
    final relationship = relationships.descendants
        .whereType<XmlElement>()
        .where(
          (e) => e.name.local == 'Relationship' && e.getAttribute('Id') == id,
        )
        .firstOrNull;
    final target = relationship?.getAttribute('Target');
    if (target == null ||
        target.contains('..') ||
        relationship?.getAttribute('TargetMode') == 'External') {
      throw const FormatException('Liên kết sheet không hợp lệ.');
    }
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final shared = <String>[];
    if (archive.findFile('xl/sharedStrings.xml') != null) {
      for (final si
          in xml('xl/sharedStrings.xml').descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'si')) {
        shared.add(
          si.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join(),
        );
      }
    }
    final source = xml(path).descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'row')
        .toList();
    if (source.length > 20001) {
      throw const FormatException('Tối đa 20.000 dòng mỗi lần nhập.');
    }
    final rows = <SheetImportRow>[];
    bool header = false;
    for (final row in source) {
      final values = List<String>.filled(expectedHeaders.length, '');
      final errors = <String>[];
      for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
        final ref = cell.getAttribute('r') ?? '';
        final match = RegExp(r'^([A-Z]+)').firstMatch(ref);
        if (match == null) throw const FormatException('Ô thiếu địa chỉ.');
        var index = 0;
        for (final letter in match[1]!.codeUnits) {
          index = index * 26 + letter - 64;
        }
        index--;
        if (cell.childElements.any((e) => e.name.local == 'f')) {
          errors.add('Không nhận công thức Excel.');
        }
        if (index < 0 || index >= expectedHeaders.length) continue;
        final type = cell.getAttribute('t'),
            value =
                cell.childElements
                    .where((e) => e.name.local == 'v')
                    .firstOrNull
                    ?.innerText ??
                '';
        values[index] = type == 'inlineStr'
            ? cell.descendants
                  .whereType<XmlElement>()
                  .where((e) => e.name.local == 't')
                  .map((e) => e.innerText)
                  .join()
            : type == 's'
            ? shared[int.parse(value)]
            : value;
      }
      if (values.every((v) => v.trim().isEmpty) && errors.isEmpty) continue;
      if (!header) {
        if (List.generate(
          expectedHeaders.length,
          (i) => values[i].trim() == expectedHeaders[i],
        ).contains(false)) {
          throw const FormatException(
            'Sai tiêu đề. Hãy sử dụng file mẫu tương ứng.',
          );
        }
        header = true;
        continue;
      }
      rows.add(
        SheetImportRow(
          int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 2,
          values,
          errors,
        ),
      );
    }
    return rows;
  }

  List<CatalogImportRow> preview(
    Uint8List bytes, {
    Set<String> existingSkus = const {},
  }) {
    final seen = <String>{}, result = <CatalogImportRow>[];
    for (final row in readTable(bytes, headers)) {
      final values = row.values, errors = [...row.errors];
      final sku = values[0].trim().toUpperCase(),
          name = values[1].trim(),
          unit = values[2].trim(),
          price = int.tryParse(values[3]);
      if (sku.isEmpty || sku.length > 128) {
        errors.add('SKU trống hoặc quá dài.');
      }
      if (name.isEmpty || name.length > 300) {
        errors.add('Tên hàng trống hoặc quá dài.');
      }
      if (unit.isEmpty || unit.length > 30) {
        errors.add('Đơn vị trống hoặc quá dài.');
      }
      if (price == null || price < 0 || price > 1000000000000) {
        errors.add('Giá phải là số nguyên không âm trong giới hạn.');
      }
      if (existingSkus.contains(sku) || !seen.add(sku)) {
        errors.add('Trùng mã SKU; không tự ghi đè.');
      }
      result.add(CatalogImportRow(row.line, sku, name, unit, price, errors));
    }
    return result;
  }
}
