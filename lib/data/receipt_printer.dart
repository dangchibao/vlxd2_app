import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/sale.dart';
import 'database.dart';

class ReceiptRenderer {
  Future<Uint8List> render({
    required String documentId,
    required List<SaleLine> lines,
    required String customer,
    required SaleTotals totals,
    bool confirmed = false,
    bool copy = false,
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    String amount(int n) => '${NumberFormat.decimalPattern('vi').format(n)} đ';
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          250 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (_) => [
          pw.Center(
            child: pw.Text(
              'VLXD BẢY HẢI',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Center(
            child: pw.Text(
              confirmed ? 'PHIẾU BÁN HÀNG' : 'PHIẾU TẠM — CHƯA GHI SỔ',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          if (copy) pw.Center(child: pw.Text('BẢN IN LẠI')),
          pw.SizedBox(height: 8),
          pw.Text('Mã: $documentId', style: const pw.TextStyle(fontSize: 8)),
          pw.Text(
            'Khách: ${customer.isEmpty ? 'Khách lẻ' : customer}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Divider(),
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(line.name, style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(
                    '${line.sku} • ${line.quantity} ${line.unit}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        amount(line.price),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        amount(line.total),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          pw.Divider(),
          pw.Text('Tiền hàng: ${amount(totals.subtotal)}'),
          pw.Text('Chiết khấu: ${amount(totals.discount)}'),
          pw.Text(
            'Tổng tiền: ${amount(totals.total)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Thanh toán tạm: ${amount(totals.paid)}'),
          pw.Text('Còn nợ tạm tính: ${amount(totals.debt)}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Phiếu này không phải hóa đơn điện tử.',
            style: const pw.TextStyle(fontSize: 8),
          ),
          if (!confirmed)
            pw.Text(
              'Chưa xác nhận tồn kho và công nợ.',
              style: const pw.TextStyle(fontSize: 8),
            ),
        ],
      ),
    );
    return document.save();
  }
}

abstract interface class PrinterAdapter {
  Future<bool> send(Uint8List pdf);
}

class WindowsPrinterAdapter implements PrinterAdapter {
  @override
  Future<bool> send(Uint8List pdf) => Printing.layoutPdf(
    name: 'Phiếu VLXD Bảy Hải',
    format: PdfPageFormat.roll80,
    onLayout: (_) async => pdf,
  );
}

class ReceiptPrinter {
  final AppDatabase db;
  final PrinterAdapter adapter;
  ReceiptPrinter(this.db, this.adapter);
  Future<String> print({
    required String jobId,
    required String documentId,
    required Uint8List bytes,
  }) async {
    // Claim is persisted before invoking any external side effect. A crash after
    // this point requires manual reconciliation, never automatic physical retry.
    await db.transaction(() async {
      final previous = await (db.select(
        db.printJobs,
      )..where((j) => j.id.equals(jobId))).getSingleOrNull();
      if (previous != null) {
        throw StateError(
          'Lệnh in đã tồn tại. Kiểm tra giấy thực tế trước khi tạo bản in lại.',
        );
      }
      await db
          .into(db.printJobs)
          .insert(
            PrintJobsCompanion.insert(
              id: jobId,
              documentId: documentId,
              pdfBytes: bytes,
              status: const Value('submitting'),
              createdAt: DateTime.now(),
            ),
          );
    });
    try {
      final accepted = await adapter.send(bytes);
      final status = accepted ? 'sent_to_system' : 'cancelled';
      await (db.update(db.printJobs)..where((j) => j.id.equals(jobId))).write(
        PrintJobsCompanion(status: Value(status)),
      );
      return status;
    } catch (_) {
      await (db.update(db.printJobs)..where((j) => j.id.equals(jobId))).write(
        const PrintJobsCompanion(status: Value('unknown')),
      );
      rethrow;
    }
  }
}
