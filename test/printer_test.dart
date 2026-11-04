import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/data/receipt_printer.dart';
import 'package:vlxd_bay_hai/domain/sale.dart';

class FakePrinter implements PrinterAdapter {
  int calls = 0;
  bool fail = false;
  @override
  Future<bool> send(Uint8List pdf) async {
    calls++;
    if (fail) throw StateError('Disconnected after submission');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('K80 receipt embeds Vietnamese font and renders PDF', () async {
    const line = SaleLine(
      productId: 'a',
      sku: 'A',
      name: 'Gạch lát nền Bảy Hải',
      unit: 'thùng',
      price: 200000,
      quantity: 2,
    );
    final bytes = await ReceiptRenderer().render(
      documentId: 'draft-1',
      lines: [line],
      customer: 'Nguyễn Thị Ánh',
      totals: SaleTotals([line]),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(5000));
  });
  test('Duplicate print ID invokes physical adapter only once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = FakePrinter();
    final printer = ReceiptPrinter(db, adapter);
    await printer.print(
      jobId: 'one',
      documentId: 'sale',
      bytes: Uint8List.fromList([1]),
    );
    await expectLater(
      printer.print(
        jobId: 'one',
        documentId: 'sale',
        bytes: Uint8List.fromList([1]),
      ),
      throwsStateError,
    );
    expect(adapter.calls, 1);
    expect(
      (await db.select(db.printJobs).get()).single.status,
      'sent_to_system',
    );
  });
  test(
    'Posted K80 renders decimal quantities and immutable snapshot amounts',
    () async {
      final bytes = await ReceiptRenderer().renderDocument(
        kind: 'sale',
        data: {
          'id': 'sale',
          'status': 'posted',
          'total': 15000,
          'discount': 0,
          'paid': 5000,
          'debt': 10000,
          'lines': [
            {
              'productId': 'p',
              'name': 'Cát vàng',
              'sku': 'CAT',
              'unit': 'm³',
              'quantity': 1500,
              'unitPrice': 10000,
              'total': 15000,
            },
          ],
        },
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(5000));
    },
  );
  test(
    'Ambiguous print failure is persisted and not automatically retried',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = FakePrinter()..fail = true;
      final printer = ReceiptPrinter(db, adapter);
      await expectLater(
        printer.print(
          jobId: 'one',
          documentId: 'sale',
          bytes: Uint8List.fromList([1]),
        ),
        throwsStateError,
      );
      expect((await db.select(db.printJobs).get()).single.status, 'unknown');
      await expectLater(
        printer.print(
          jobId: 'one',
          documentId: 'sale',
          bytes: Uint8List.fromList([1]),
        ),
        throwsStateError,
      );
      expect(adapter.calls, 1);
    },
  );
}
