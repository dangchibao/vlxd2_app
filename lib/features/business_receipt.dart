import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../data/receipt_printer.dart';
import '../domain/operations.dart';

String printStatusLabel(String status) => switch (status) {
  'queued' => 'Chờ trạm nhận',
  'claimed' => 'Trạm đã nhận',
  'prepared' => 'Đã chuẩn bị',
  'submitting' => 'Đang gửi hoặc bị gián đoạn',
  'sent_to_system' => 'Đã gửi tới hệ thống in',
  'cancelled' => 'Đã hủy',
  'unknown' => 'Cần đối chiếu bản giấy',
  _ => status,
};

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
  bool busy = false, attempted = false, resultQueued = false;
  bool copy = false;
  PrintJob? existingJob;
  String? message;
  bool get isTest => widget.kind == 'printerTest';
  PdfPageFormat get pageFormat => switch (widget.kind) {
    'printerTest' => k80TestFormat,
    'barcodeLabel' => barcodeLabelFormat,
    _ => PdfPageFormat.roll80,
  };
  late final String? owner;
  @override
  void initState() {
    super.initState();
    owner = widget.runtime?.actor?.uid;
  }

  String get documentId => '${widget.kind}:${widget.data['id']}';
  Future<Uint8List> prepare() async {
    if (isTest) return ReceiptRenderer().renderPrinterTest();
    final db = widget.database;
    final existing = await (db.select(
      db.printJobs,
    )..where((row) => row.id.equals(jobId))).getSingleOrNull();
    if (existing != null) {
      if (mounted) {
        setState(() {
          attempted = true;
          existingJob = existing;
          message =
              '${printStatusLabel(existing.status)}. Đối chiếu bản giấy nếu cần.';
        });
      }
      return existing.pdfBytes;
    }
    copy =
        await (db.select(db.printJobs)
              ..where((row) => row.documentId.equals(documentId))
              ..limit(1))
            .getSingleOrNull() !=
        null;
    return ReceiptRenderer().renderDocument(
      kind: widget.kind,
      data: widget.data,
      copy: copy,
    );
  }

  Future<void> queueResult(String status) async {
    final runtime = widget.runtime!;
    final db = widget.database;
    if (owner == null || runtime.actor?.uid != owner) {
      throw StateError('Phiên đăng nhập đã thay đổi.');
    }
    final alreadyQueued =
        await (db.select(db.outbox)
              ..where((row) => row.aggregateId.equals(jobId))
              ..where((row) => row.operation.equals(Operation.printResult.name))
              ..where((row) => row.actorUid.equals(owner!))
              ..where(
                (row) => row.expectedVersion.equals(widget.requestVersion!),
              )
              ..where(
                (row) => row.status.isIn(['pending', 'syncing', 'confirmed']),
              )
              ..limit(1))
            .getSingleOrNull();
    if (runtime.actor?.uid != owner) {
      throw StateError('Phiên đăng nhập đã thay đổi.');
    }
    if (alreadyQueued == null) {
      await runtime.enqueue(Operation.printResult, jobId, {
        'claimToken': widget.claimToken,
        'status': status,
        'note': 'Kết quả ghi trong nhật ký của máy Windows.',
      }, expectedVersion: widget.requestVersion!);
    }
    resultQueued = true;
  }

  Future<void> resendResult() async {
    final job = existingJob;
    if (busy || resultQueued || job == null) return;
    setState(() => busy = true);
    try {
      await queueResult(job.status);
      message = 'Đã lưu kết quả để đồng bộ về hàng đợi.';
    } catch (_) {
      message = 'Chưa lưu được kết quả. Có thể thử gửi lại từ nhật ký lệnh.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> printDocument() async {
    if (busy || attempted) return;
    setState(() => busy = true);
    final db = widget.database;
    try {
      final bytes = await pdf;
      if (!mounted || attempted) return;
      if (copy && widget.requestId == null) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('In thêm một bản?'),
            content: const Text(
              'Phiếu này có trong nhật ký in. Hãy đối chiếu bản giấy trước khi tiếp tục.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('In thêm'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      attempted = true;
      final status = await ReceiptPrinter(
        db,
        WindowsPrinterAdapter(format: pageFormat),
      ).print(jobId: jobId, documentId: documentId, bytes: bytes);
      message = status == 'sent_to_system'
          ? 'Đã gửi tới hệ thống in. Hãy kiểm tra giấy thực tế.'
          : 'Đã hủy hộp thoại in.';
      if (widget.requestId != null) {
        try {
          await queueResult(status);
        } catch (_) {
          message =
              '${printStatusLabel(status)}. Kết quả chưa được lưu để đồng bộ.';
        }
      }
    } catch (_) {
      message = attempted
          ? 'Không rõ kết quả in. Hãy kiểm tra bản giấy.'
          : 'Không tạo được phiếu để gửi in.';
    } finally {
      if (mounted && attempted && widget.requestId != null) {
        try {
          existingJob = await (db.select(
            db.printJobs,
          )..where((row) => row.id.equals(jobId))).getSingleOrNull();
        } catch (_) {
          message = 'Chưa đọc được nhật ký in của máy.';
        }
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendToStation() async {
    if (busy || attempted) return;
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
      title: Text(switch (widget.kind) {
        'barcodeLabel' => 'Tem mã vạch 60 × 40 mm',
        'printerTest' => 'Phiếu thử máy in K80',
        _ => 'Phiếu K80',
      }),
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
        if (widget.requestId != null &&
            !resultQueued &&
            {
              'sent_to_system',
              'cancelled',
              'unknown',
            }.contains(existingJob?.status))
          TextButton.icon(
            onPressed: busy ? null : resendResult,
            icon: const Icon(Icons.sync),
            label: const Text('Đồng bộ kết quả đã lưu'),
          ),
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
                allowSharing: true,
                initialPageFormat: pageFormat,
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
