import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import 'business_pages.dart';
import 'business_receipt.dart';

class PrintJobsPage extends StatefulWidget {
  final AppRuntime runtime;
  const PrintJobsPage({super.key, required this.runtime});
  @override
  State<PrintJobsPage> createState() => _PrintJobsPageState();
}

class _PrintJobsPageState extends State<PrintJobsPage> {
  AppRuntime get runtime => widget.runtime;
  final claiming = <String>{};
  bool get windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> claim(
    BuildContext context,
    Map<String, dynamic> data,
    int version,
  ) async {
    final id = data['id'] as String;
    final owner = runtime.actor?.uid;
    if (owner == null || !claiming.add(id)) return;
    setState(() {});
    try {
      final key = 'printClaim.$id';
      final saved = await runtime.vault.readData(key);
      final token = saved?['token'] as String? ?? const Uuid().v4();
      if (saved?['token'] == null) {
        await runtime.vault.writeData(key, {'token': token});
      }
      if (runtime.actor?.uid != owner) return;
      await runtime.enqueue(Operation.printClaim, id, {
        'claimToken': token,
      }, expectedVersion: version);
      if (context.mounted) {
        feedback(
          context,
          'Đã gửi nhận lệnh. Chờ xác nhận trước khi mở phiếu in.',
        );
      }
    } catch (_) {
      if (context.mounted) feedback(context, 'Chưa nhận được lệnh.');
    } finally {
      claiming.remove(id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Yêu cầu từ thiết bị'),
            Tab(text: 'Nhật ký trên máy này'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              RecordList(
                runtime: runtime,
                kind: 'printRequest',
                title: 'Hàng đợi in Windows',
                item: (context, row, data) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${data['documentKind']} • ${data['documentId']}'),
                        Text(printStatusLabel(data['status'] as String)),
                        if (data['note'] is String)
                          Text(data['note'] as String),
                        if (windows &&
                            runtime.stationSession != null &&
                            allowed(runtime, Operation.printClaim)) ...[
                          if (data['status'] == 'queued')
                            OutlinedButton(
                              onPressed: claiming.contains(data['id'])
                                  ? null
                                  : () => claim(context, data, row.version),
                              child: const Text('Nhận lệnh tại trạm này'),
                            ),
                          if (data['status'] == 'claimed' &&
                              data['claimedBy'] == runtime.actor?.uid)
                            FutureBuilder(
                              future: runtime.vault.readData(
                                'printClaim.${data['id']}',
                              ),
                              builder: (context, claim) {
                                final token = claim.data?['token'];
                                if (token == null ||
                                    token != data['claimToken']) {
                                  return const Text(
                                    'Lệnh đang được giữ bởi thiết bị khác.',
                                  );
                                }
                                return Wrap(
                                  spacing: 12,
                                  children: [
                                    FilledButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => BusinessReceipt(
                                            database: runtime.db,
                                            kind:
                                                data['documentKind'] as String,
                                            data:
                                                data['snapshot']
                                                    as Map<String, dynamic>,
                                            runtime: runtime,
                                            requestId: data['id'] as String,
                                            requestVersion: row.version,
                                            claimToken: token as String,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Mở phiếu / Gửi in một lần',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => commandDialog(
                                        context,
                                        runtime,
                                        title: 'Đối chiếu lệnh đã nhận',
                                        operation: Operation.printResult,
                                        entityId: data['id'] as String,
                                        version: row.version,
                                        fixed: {'claimToken': token},
                                        fields: const [
                                          InputField(
                                            'status',
                                            'Kết quả đối chiếu',
                                            choices: [
                                              (
                                                'unknown',
                                                'Chưa rõ kết quả • không tự in lại',
                                              ),
                                              (
                                                'cancelled',
                                                'Đã hủy / không in',
                                              ),
                                              (
                                                'sent_to_system',
                                                'Đã gửi hệ thống in',
                                              ),
                                            ],
                                          ),
                                          InputField(
                                            'note',
                                            'Ghi chú đối chiếu',
                                          ),
                                        ],
                                      ),
                                      child: const Text('Đối chiếu thủ công'),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ] else
                          const Text(
                            'Nhận và xử lý tại trạm Windows đã kết nối tài khoản trạm.',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  if (windows)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('In phiếu thử K80'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => BusinessReceipt(
                              database: runtime.db,
                              kind: 'printerTest',
                              data: const {'id': 'k80'},
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder(
                      stream:
                          (runtime.db.select(runtime.db.printJobs)
                                ..orderBy([
                                  (row) => OrderingTerm.desc(row.createdAt),
                                ])
                                ..limit(100))
                              .watch(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text('Không đọc được nhật ký.'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text('Máy này chưa có nhật ký in.'),
                          );
                        }
                        return ListView(
                          children: [
                            for (final row in snapshot.data!)
                              ListTile(
                                title: Text(row.documentId),
                                subtitle: Text(
                                  '${row.createdAt.toLocal()} • ${printStatusLabel(row.status)}',
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: const Text('Bản phiếu đã gửi'),
                                      ),
                                      body: PdfPreview(
                                        build: (_) async => row.pdfBytes,
                                        allowPrinting: false,
                                        allowSharing: false,
                                        canChangeOrientation: false,
                                        canChangePageFormat: false,
                                        canDebug: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
