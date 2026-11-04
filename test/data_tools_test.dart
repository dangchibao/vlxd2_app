import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/backup_service.dart';
import 'package:vlxd_bay_hai/data/xlsx_catalog.dart';
import 'package:vlxd_bay_hai/domain/operations.dart';

void main() {
  test('XLSX Unicode round trip and duplicate preview', () {
    const p = Product(
      id: 'a',
      sku: 'G01',
      name: 'Gạch Bảy Hải & <đẹp>',
      unit: 'thùng',
      price: 235000,
    );
    final bytes = XlsxCatalog().export([p]);
    final rows = XlsxCatalog().preview(bytes);
    expect(rows.single.name, p.name);
    expect(rows.single.price, 235000);
    expect(rows.single.errors, isEmpty);
    expect(
      XlsxCatalog().preview(bytes, existingSkus: {'G01'}).single.errors,
      contains('Trùng mã SKU; không tự ghi đè.'),
    );
  });
  test('XLSX rejects formulas before catalog import', () {
    const p = Product(id: 'a', sku: 'A', name: 'A', unit: 'bao', price: 100);
    final archive = ZipDecoder().decodeBytes(XlsxCatalog().export([p]));
    final modified = Archive();
    for (final file in archive) {
      modified.addFile(
        file.name == 'xl/worksheets/sheet1.xml'
            ? ArchiveFile.string(
                file.name,
                utf8
                    .decode(file.content)
                    .replaceFirst('<v>100</v>', '<f>1+2</f><v>100</v>'),
              )
            : ArchiveFile(file.name, file.size, file.content),
      );
    }
    final rows = XlsxCatalog().preview(
      Uint8List.fromList(ZipEncoder().encode(modified)),
    );
    expect(rows.single.errors, contains('Không nhận công thức Excel.'));
  });
  test('XLSX blocks invalid input and excessive decompressed sizes', () {
    expect(
      () => XlsxCatalog().preview(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final bytes = XlsxCatalog().table(XlsxCatalog.headers, []);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 46; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint32(i + 24, 0x7fffffff, Endian.little);
        break;
      }
    }
    expect(() => XlsxCatalog().preview(bytes), throwsFormatException);
  });
  test('Encrypted backup restores local state and detects wrong password and tampering', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = BackupService(db, storeId: 'shop', userId: 'manager');
    await db.addProduct('A', 'Hàng A', 'bao', 1000);
    await db.saveDraft('draft', {'customer': 'Khách A'});
    final bytes = await service.create('fixture-backup-password');
    expect(utf8.decode(bytes), isNot(contains('Khách A')));
    await expectLater(
      service.preview(bytes, 'wrong-password'),
      throwsFormatException,
    );
    await db.addProduct('B', 'Hàng B', 'bao', 2000);
    final preview = await service.preview(bytes, 'fixture-backup-password');
    await expectLater(
      service.restore(preview, acknowledged: false),
      throwsA(isA<BusinessException>()),
    );
    await service.restore(preview, acknowledged: true);
    expect((await db.select(db.products).get()).single.sku, 'A');
    expect((await db.select(db.drafts).get()).single.id, 'draft');
    await expectLater(
      BackupService(
        db,
        storeId: 'other',
        userId: 'manager',
      ).preview(bytes, 'fixture-backup-password'),
      throwsFormatException,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'Restore rejects stale or mutated preview before deleting local rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = BackupService(db, storeId: 'shop', userId: 'manager');
      await db.addProduct('A', 'A', 'bao', 1);
      final bytes = await service.create('fixture-backup-password');
      final preview = await service.preview(bytes, 'fixture-backup-password');
      await db.addProduct('B', 'B', 'bao', 2);
      await expectLater(
        service.restore(preview, acknowledged: true),
        throwsA(isA<BusinessException>()),
      );
      expect((await db.select(db.products).get()).length, 2);
      final mutated = await service.preview(bytes, 'fixture-backup-password');
      mutated.snapshot['tables'] = {};
      await expectLater(
        service.restore(mutated, acknowledged: true),
        throwsFormatException,
      );
      expect((await db.select(db.products).get()).length, 2);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
