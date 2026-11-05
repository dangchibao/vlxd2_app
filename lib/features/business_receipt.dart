import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../data/receipt_printer.dart';
import '../domain/operations.dart';

void openBusinessReceipt(
  BuildContext context,
  AppRuntime runtime,
  String kind,
  Map<String, dynamic> data,
) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => BusinessReceipt(
        database: runtime.db,
        kind: kind,
        data: data,
        runtime: runtime,
      ),
    ),
  );
}

class BusinessReceipt extends StatefulWidget {
  final AppDatabase database;
  final String kind;
  final Map<String, dynamic> data;
  final AppRuntime? runtime;
  final String? requestId, claimToken;
  final int? requestVersion;
  const BusinessReceipt({
    super.key,
    required this.database,
    required this.kind,
    required this.data,
    this.runtime,
    this.requestId,
    this.claimToken,
    this.requestVersion,
  });
  @override
  State<BusinessReceipt> createState() => _BusinessReceiptState();
}

class _BusinessReceiptState extends State<BusinessReceipt> {
  late final Future<Uint8List> pdf = prepare();
  late final jobId = widget.requestId ?? const Uuid().v4();
  bool busy = false, attempted = false;
  String? message;
  String get documentId => '${widget.kind}:${widget.data['id']}';
  Future<Uint8List> prepare() async {
    final previous = await (widget.database.select(
      widget.database.printJobs,
    )..where((r) => r.documentId.equals(documentId))).get();
    final existing = previous.where((r) => r.id == jobId).firstOrNull;
    if (existing != null) {
      if (mounted) {
        setState(() {
          attempted = true;
          message =
              'Lệnh đã được gửi trước đó (${existing.status}). Đối chiếu giấy thực tế; không gửi lại tự động.';
        });
      }
      return existing.pdfBytes;
    }
    return ReceiptRenderer().renderDocument(
      kind: widget.kind,
      data: widget.data,
      copy: previous.isNotEmpty,
    );
  }

  Future<void> printDocument() async {
    setState(() => busy = true);
    try {
      final bytes = await pdf;
      final status = await ReceiptPrinter(
        widget.database,
        WindowsPrinterAdapter(
          format: widget.kind == 'barcodeLabel'
              ? barcodeLabelFormat
              : PdfPageFormat.roll80,
        ),
      ).print(jobId: jobId, documentId: documentId, bytes: bytes);
      if (widget.requestId != null) {
        await widget.runtime!.enqueue(
          Operation.printResult,
          widget.requestId!,
          {
            'claimToken': widget.claimToken,
            'status': status,
            'note':
                'Kết quả hộp thoại hệ thống in; chưa xác minh giấy thực tế.',
          },
          expectedVersion: widget.requestVersion!,
        );
      }
      if (mounted) {
        setState(
          () => message = status == 'sent_to_system'
              ? 'Đã gửi tới hệ thống in. Hãy kiểm tra giấy thực tế.'
              : 'Đã hủy hộp thoại in.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Không rõ kết quả in. Kiểm tra giấy trước khi mở lại phiếu để in lại.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          attempted = true;
        });
      }
    }
  }

  Future<void> sendToStation() async {
    setState(() => busy = true);
    try {
      await widget.runtime!.enqueue(Operation.printRequest, const Uuid().v4(), {
        'documentKind': widget.kind,
        'documentId': widget.data['id'],
        'documentVersion': widget.data['version'],
      });
      if (mounted) {
        setState(() {
          attempted = true;
          message = 'Đã lưu yêu cầu gửi trạm Windows. Trạm phải nhận lệnh và người vận hành bấm in.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Chưa gửi được yêu cầu in.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.kind == 'barcodeLabel' ? 'Tem mã vạch 60 × 40 mm' : 'Phiếu K80',
      ),
      actions: [
        if (widget.runtime != null && widget.requestId == null)
          IconButton(
            onPressed: busy || attempted ? null : sendToStation,
            tooltip: 'Gửi yêu cầu tới trạm Windows',
            icon: const Icon(Icons.send_outlined),
          ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
          IconButton(
            onPressed: busy || attempted ? null : printDocument,
            tooltip: 'In phiếu',
            icon: const Icon(Icons.print_outlined),
          ),
      ],
    ),
    body: Column(
      children: [
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
        Expanded(
          child: FutureBuilder(
            future: pdf,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Không tạo được phiếu từ chứng từ này.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return PdfPreview(
                build: (_) async => snapshot.data!,
                allowPrinting: false,
                allowSharing: widget.kind == 'barcodeLabel',
                initialPageFormat: widget.kind == 'barcodeLabel'
                    ? barcodeLabelFormat
                    : PdfPageFormat.roll80,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
              );
            },
          ),
        ),
      ],
    ),
  );
}
