import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../data/xlsx_catalog.dart';
import '../domain/operations.dart';
import '../domain/product_policy.dart';
import 'business_pages.dart';
import 'material_calculator.dart';

class PriceExcelTools extends StatelessWidget {
  final AppRuntime runtime;
  final bool disabled;
  const PriceExcelTools({
    super.key,
    required this.runtime,
    this.disabled = false,
  });

  static const headers = ['SKU', 'Bảng giá', 'Số lượng từ', 'Giá bán'];
  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<List<BusinessRecord>> records() => (runtime.db.select(
    runtime.db.businessRecords,
  )..where((r) => r.kind.equals('catalog'))).get();

  Future<void> export(BuildContext context, {required bool template}) async {
    try {
      final data = template
          ? const <Map<String, dynamic>>[]
          : (await records()).map(recordData);
      await FilePicker.saveFile(
        fileName: template ? 'mau-bang-gia.xlsx' : 'bang-gia.xlsx',
        bytes: XlsxCatalog().table(headers, [
          for (final item in data) ...[
            [item['sku'], '', '', item['price']],
            for (final entry in (item['priceLists'] as Map? ?? {}).entries)
              [item['sku'], entry.key, '', entry.value],
            for (final tier in item['quantityTiers'] as List? ?? [])
              [
                item['sku'],
                tier['priceList'],
                qty(tier['minimum'] as int),
                tier['price'],
              ],
          ],
        ]),
        mimeType: mimeType,
      );
    } catch (e) {
      if (context.mounted) {
        feedback(
          context,
          e is FormatException ? e.message : 'Không xuất được bảng giá.',
        );
      }
    }
  }

  Future<Set<String>> pendingCatalog(AppDatabase db) async {
    final rows =
        await (db.select(db.outbox)
              ..where((row) => row.operation.equals('catalog'))
              ..where((row) => row.status.isIn(['pending', 'syncing'])))
            .get();
    return rows.map((row) => row.aggregateId).toSet();
  }

  Future<void> importFile(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (file == null) return;
      if ((await file.length() ?? 0) > 10 * 1024 * 1024) {
        throw const FormatException('File vượt 10 MB.');
      }
      final rows = XlsxCatalog().readTable(await file.readAsBytes(), headers);
      if (rows.isEmpty || rows.length > 1000) {
        throw const FormatException('File cần từ 1 đến 1.000 dòng giá.');
      }
      final db = runtime.db;
      final owner = runtime.actor?.uid;
      final catalog = {
        for (final row in await records())
          (recordData(row)['sku'] as String).toUpperCase(): row,
      };
      final pending = await pendingCatalog(db);
      final seen = <String>{}, messages = <String>[], errors = <String>[];
      final changes = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final [skuText, list, minimumText, priceText] = row.values
            .map((v) => v.trim())
            .toList();
        final sku = skuText.toUpperCase(), record = catalog[sku];
        try {
          if (row.errors.isNotEmpty) {
            throw FormatException(row.errors.join(' '));
          }
          if (record == null) throw const FormatException('SKU chưa đồng bộ.');
          final original = recordData(record);
          if (pending.contains(original['id'])) {
            throw const FormatException('SKU có thay đổi đang chờ đồng bộ.');
          }
          if (list.length > 64) {
            throw const FormatException('Tên bảng giá quá dài.');
          }
          final minimum = minimumText.isEmpty ? 0 : parseFixed(minimumText, 3);
          if (minimumText.isNotEmpty && minimum == 0) {
            throw const FormatException('Số lượng từ phải lớn hơn 0.');
          }
          final price = integerField(
            {'price': int.tryParse(priceText)},
            'price',
            max: 1000000000000,
          );
          if (!seen.add(jsonEncode([sku, list, minimum]))) {
            throw const FormatException('Trùng SKU, bảng giá và mức số lượng.');
          }
          final previous = changes[sku] ?? original;
          final lists = Map<String, dynamic>.from(
            previous['priceLists'] as Map? ?? {},
          );
          final tiers = (previous['quantityTiers'] as List? ?? [])
              .cast<Map<String, dynamic>>()
              .toList();
          final data = {
            'sku': sku,
            'name': original['name'],
            'unit': original['unit'],
            'price': previous['price'],
            'priceLists': lists,
            'quantityTiers': tiers,
          };
          int? oldPrice;
          if (minimum > 0) {
            final index = tiers.indexWhere(
              (tier) =>
                  (tier['priceList'] ?? '') == list &&
                  tier['minimum'] == minimum,
            );
            final tier = {
              'priceList': list,
              'minimum': minimum,
              'price': price,
            };
            if (index < 0) {
              tiers.add(tier);
            } else {
              oldPrice = tiers[index]['price'] as int;
              tiers[index] = tier;
            }
          } else if (list.isEmpty) {
            oldPrice = data['price'] as int;
            data['price'] = price;
          } else {
            oldPrice = lists[list] as int?;
            lists[list] = price;
          }
          ProductPolicy.validate({...original, ...data});
          changes[sku] = data;
          messages.add(
            "Dòng ${row.line} • $sku • ${list.isEmpty ? 'Giá chung' : list}${minimum > 0 ? ' từ ${qty(minimum)}' : ''} • ${oldPrice == null ? 'Mới' : vnd(oldPrice)} → ${vnd(price)}",
          );
        } catch (e) {
          errors.add(
            'Dòng ${row.line} • $sku • ${switch (e) {
              FormatException() => e.message,
              BusinessException() => e.message,
              _ => 'Dòng không hợp lệ.',
            }}',
          );
        }
      }
      if (!context.mounted) return;
      final approve = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            errors.isEmpty
                ? 'Xác nhận cập nhật ${changes.length} mã hàng'
                : '${errors.length} dòng có lỗi',
          ),
          content: SizedBox(
            width: 560,
            height: 320,
            child: ListView(
              children: [
                if (errors.isEmpty)
                  const Text(
                    'Các giá hiển thị sẽ được cập nhật sau khi trạm xác nhận.',
                  ),
                for (final line in [...errors, ...messages])
                  ListTile(dense: true, title: Text(line)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Đóng'),
            ),
            if (errors.isEmpty)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Gửi cập nhật'),
              ),
          ],
        ),
      );
      if (approve != true ||
          !context.mounted ||
          runtime.actor?.uid != owner ||
          runtime.db != db) {
        return;
      }
      await db.transaction(() async {
        final pendingNow = await pendingCatalog(db);
        for (final entry in changes.entries) {
          final record = catalog[entry.key]!;
          final productId = recordData(record)['id'] as String;
          final current = await (db.select(
            db.businessRecords,
          )..where((row) => row.id.equals(record.id))).getSingleOrNull();
          if (!context.mounted ||
              runtime.actor?.uid != owner ||
              runtime.db != db) {
            throw const FormatException(
              'Phiên đăng nhập đã thay đổi. Mở lại bản xem trước.',
            );
          }
          if (current?.version != record.version ||
              pendingNow.contains(productId)) {
            throw FormatException(
              'Giá của ${entry.key} đã thay đổi. Mở lại bản xem trước.',
            );
          }
          await runtime.enqueue(
            Operation.catalog,
            productId,
            entry.value,
            expectedVersion: record.version,
            syncNow: false,
          );
        }
      });
      if (context.mounted) {
        feedback(context, 'Đã lưu ${changes.length} cập nhật giá chờ đồng bộ.');
      }
      await runtime.tick();
    } catch (e) {
      if (context.mounted) {
        feedback(
          context,
          e is FormatException ? e.message : 'Không nhập được bảng giá.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      OutlinedButton(
        onPressed: disabled ? null : () => export(context, template: true),
        child: const Text('Mẫu bảng giá'),
      ),
      OutlinedButton(
        onPressed: disabled ? null : () => export(context, template: false),
        child: const Text('Xuất bảng giá'),
      ),
      if ({StaffRole.admin, StaffRole.manager}.contains(runtime.actor?.role))
        FilledButton(
          onPressed: disabled ? null : () => importFile(context),
          child: const Text('Xem trước bảng giá'),
        ),
    ],
  );
}
