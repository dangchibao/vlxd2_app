import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/receipt_printer.dart';
import '../domain/sale.dart';

class ReceiptPreview extends StatefulWidget {
  final AppDatabase database;
  final String documentId, customer;
  final List<SaleLine> lines;
  final SaleTotals totals;
  const ReceiptPreview({
    super.key,
    required this.database,
    required this.documentId,
    required this.customer,
    required this.lines,
    required this.totals,
  });
  @override
  State<ReceiptPreview> createState() => _ReceiptPreviewState();
}

class _ReceiptPreviewState extends State<ReceiptPreview> {
  late final Future<Uint8List> bytes;
  final jobId = const Uuid().v4();
  bool busy = false, attempted = false;
  String? message;
  @override
  void initState() {
    super.initState();
    bytes = _prepare();
  }

  Future<Uint8List> _prepare() async {
    final previous = await (widget.database.select(
      widget.database.printJobs,
    )..where((j) => j.documentId.equals(widget.documentId))).get();
    if (previous.isNotEmpty && mounted) {
      setState(
        () => message = 'Đã có lệnh in cho phiếu này. Kiểm tra giấy trước khi in lại; bản tiếp theo sẽ có dấu BẢN IN LẠI.',
      );
    }
    return ReceiptRenderer().render(
      documentId: widget.documentId,
      lines: widget.lines,
      customer: widget.customer,
      totals: widget.totals,
      copy: previous.isNotEmpty,
    );
  }

  Future<void> printReceipt() async {
    setState(() => busy = true);
    try {
      final pdf = await bytes;
      if (!mounted) return;
      final status = await ReceiptPrinter(
        widget.database,
        WindowsPrinterAdapter(),
      ).print(jobId: jobId, documentId: widget.documentId, bytes: pdf);
      if (mounted) {
        setState(() {
          attempted = true;
          message = status == 'sent_to_system'
              ? 'Đã gửi tới hệ thống in. Hãy kiểm tra giấy thực tế.'
              : 'Đã hủy hộp thoại in.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          attempted = true;
          message = 'Không rõ kết quả gửi in. Kiểm tra máy in và giấy trước khi tạo bản in lại.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Xem phiếu tạm K80'),
      actions: [
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
          IconButton(
            tooltip: 'In phiếu',
            onPressed: busy || attempted ? null : printReceipt,
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
            future: bytes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Không tạo được phiếu. Vui lòng kiểm tra dữ liệu.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return PdfPreview(
                build: (_) async => snapshot.data!,
                allowPrinting: false,
                allowSharing: false,
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
