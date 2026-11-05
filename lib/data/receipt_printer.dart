import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/sale.dart';
import '../domain/operations.dart';
import 'database.dart';

class ReceiptRenderer {
  /// Uses immutable posted line snapshots, never the current catalog prices.
  Future<Uint8List> renderDocument({
    required String kind,
    required Map<String, dynamic> data,
    bool copy = false,
  }) async {
    final title = switch (kind) {
      'sale' => 'PHIẾU BÁN HÀNG',
      'quote' => 'BÁO GIÁ',
      'purchase' => 'ĐƠN MUA HÀNG',
      'delivery' => 'PHIẾU GIAO HÀNG',
      'shiftClose' => 'PHIẾU CHỐT CA',
      'expense' => 'PHIẾU CHI',
      'payment' => 'PHIẾU THU',
      'deposit' => 'PHIẾU THU ĐẶT CỌC',
      'reservationRefund' => 'PHIẾU HOÀN ĐẶT CỌC',
      'supplierPayment' => 'PHIẾU CHI NHÀ CUNG CẤP',
      'refund' => 'PHIẾU HOÀN TIỀN',
      'purchaseReceipt' => 'PHIẾU NHẬP KHO',
      'transfer' => 'PHIẾU CHUYỂN KHO',
      'returnReceipt' => 'PHIẾU NHẬN HÀNG TRẢ',
      'inventoryCount' => 'PHIẾU KIỂM KÊ',
      'warranty' => 'PHIẾU TIẾP NHẬN BẢO HÀNH',
      _ => throw const FormatException('Loại phiếu không hỗ trợ.'),
    };
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    String money(int value) =>
        '${NumberFormat.decimalPattern('vi').format(value)} đ';
    String quantity(int value) {
      final raw = (value % 1000)
          .toString()
          .padLeft(3, '0')
          .replaceFirst(RegExp(r'0+$'), '');
      return '${value ~/ 1000}${raw.isEmpty ? '' : ',$raw'}';
    }

    final lines = (data['lines'] as List? ?? []).cast<Map<String, dynamic>>();
    final rows = <pw.Widget>[
      pw.Center(
        child: pw.Text(
          ((data['storeSnapshot'] as Map?)?['name'] as String? ??
                  'VLXD BẢY HẢI')
              .toUpperCase(),
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Center(child: pw.Text(title, style: const pw.TextStyle(fontSize: 11))),
      if ((data['storeSnapshot'] as Map?)?['address'] != null)
        pw.Center(
          child: pw.Text(
            '${(data['storeSnapshot'] as Map)['address']}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      if ((data['storeSnapshot'] as Map?)?['phone'] != null)
        pw.Center(
          child: pw.Text(
            '${(data['storeSnapshot'] as Map)['phone']}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      if (copy) pw.Center(child: pw.Text('BẢN IN LẠI')),
      pw.SizedBox(height: 8),
      pw.Text(
        'Mã: ${textField(data, 'id')}',
        style: const pw.TextStyle(fontSize: 8),
      ),
      if (data['createdAt'] != null)
        pw.Text(
          'Ngày: ${data['createdAt']}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      if (data['customerId'] != null)
        pw.Text('Khách: ${data['customerName'] ?? data['customerId']}'),
      if (data['supplierId'] != null)
        pw.Text('NCC: ${data['supplierName'] ?? data['supplierId']}'),
      if (kind == 'quote') pw.Text('Phiên bản ${data['version']}'),
      if (data['warehouse'] != null) pw.Text('Kho: ${data['warehouse']}'),
      if (data['vehicleId'] != null) pw.Text('Xe: ${data['vehicleId']}'),
      for (final field in const {
        'saleId': 'Đơn bán',
        'purchaseId': 'Đơn mua',
        'shiftId': 'Ca',
        'reason': 'Lý do',
        'condition': 'Tình trạng',
        'accessories': 'Phụ kiện',
        'serial': 'Serial',
        'fromWarehouse': 'Kho nguồn',
        'toWarehouse': 'Kho đích',
      }.entries)
        if (data[field.key] != null)
          pw.Text(
            '${field.value}: ${data[field.key]}',
            style: const pw.TextStyle(fontSize: 9),
          ),
      pw.Divider(),
    ];
    var subtotal = 0;
    for (final line in lines) {
      final q = integerField(line, 'quantity', min: 1);
      final amount = kind == 'purchase'
          ? roundedRatio(integerField(line, 'unitCost'), q, 1000)
          : (line['total'] as int? ?? 0);
      subtotal += amount;
      rows.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${line['name'] ?? line['productId']}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              '${line['sku'] ?? ''} • ${quantity(q)} ${line['unit'] ?? ''}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            if (kind == 'delivery')
              pw.Text(
                'Đã giao lũy kế: ${quantity(line['delivered'] as int? ?? 0)}',
              ),
            if (kind == 'purchase')
              pw.Text('Đã nhận: ${quantity(line['received'] as int? ?? 0)}'),
            if ({'sale', 'quote', 'purchase', 'returnReceipt'}.contains(kind))
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    money((line['unitPrice'] ?? line['unitCost'] ?? 0) as int),
                  ),
                  pw.Text(money(amount)),
                ],
              ),
            if (line['lotId'] != null && (line['lotId'] as String).isNotEmpty)
              pw.Text(
                'Lô: ${line['lotId']}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            if (line['serials'] is List && (line['serials'] as List).isNotEmpty)
              pw.Text(
                'Serial: ${(line['serials'] as List).join(', ')}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            if ((line['returned'] as int? ?? 0) > 0)
              pw.Text('Đã trả: ${quantity(line['returned'] as int)}'),
            pw.SizedBox(height: 7),
          ],
        ),
      );
    }
    rows.add(pw.Divider());
    if ({'sale', 'quote', 'purchase', 'returnReceipt'}.contains(kind)) {
      rows.addAll([
        pw.Text('Tiền hàng: ${money(subtotal)}'),
        if (kind == 'sale' || kind == 'quote')
          pw.Text('Chiết khấu: ${money(data['discount'] as int? ?? 0)}'),
        if (kind == 'sale' || kind == 'quote')
          pw.Text('Phụ thu: ${money(data['surcharge'] as int? ?? 0)}'),
        pw.Text(
          'Tổng: ${money(data['total'] as int? ?? subtotal)}',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ]);
    }
    if (kind == 'sale') {
      rows.addAll([
        pw.Text('Đã thu: ${money(integerField(data, 'paid'))}'),
        pw.Text('Còn nợ: ${money(integerField(data, 'debt'))}'),
        if (data['returnedValue'] != null)
          pw.Text('Giá trị hàng trả: ${money(data['returnedValue'] as int)}'),
        if (data['refunded'] != null)
          pw.Text('Đã hoàn tiền: ${money(data['refunded'] as int)}'),
      ]);
    }
    if (kind == 'shiftClose') {
      rows.addAll([
        pw.Text('Ca: ${data['shiftId']}'),
        pw.Text(
          'Dự kiến: ${money(integerField(data, 'expected', min: -9000000000000))}',
        ),
        pw.Text('Thực đếm: ${money(integerField(data, 'counted'))}'),
        pw.Text(
          'Chênh lệch: ${money(integerField(data, 'difference', min: -9000000000000))}',
        ),
        pw.Text('Giải trình: ${data['explanation'] ?? ''}'),
      ]);
    }
    if ({
      'expense',
      'payment',
      'supplierPayment',
      'refund',
      'deposit',
      'reservationRefund',
    }.contains(kind)) {
      rows.addAll([
        pw.Text('Số tiền: ${money(integerField(data, 'amount'))}'),
        pw.Text('Nội dung: ${data['reason']}'),
      ]);
    }
    if (kind == 'inventoryCount') {
      rows.addAll([
        pw.Text('Hàng: ${data['productId']}'),
        pw.Text(
          'Theo sổ: ${NumberFormat('0.###', 'vi').format((data['previous'] as int) / 1000)}',
        ),
        pw.Text(
          'Thực đếm: ${NumberFormat('0.###', 'vi').format((data['counted'] as int) / 1000)}',
        ),
        pw.Text(
          'Lệch: ${NumberFormat('0.###', 'vi').format((data['difference'] as int) / 1000)}',
        ),
      ]);
    }
    if (kind == 'purchaseReceipt') {
      rows.add(pw.Text('Giá trị nhập: ${money(integerField(data, 'total'))}'));
    }
    rows.addAll([
      pw.SizedBox(height: 12),
      pw.Text(
        'Phiếu này không phải hóa đơn điện tử.',
        style: const pw.TextStyle(fontSize: 8),
      ),
    ]);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          250 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (_) => rows,
      ),
    );
    return document.save();
  }

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
