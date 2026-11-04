import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import 'business_pages.dart';
import 'business_receipt.dart';

class PrintJobsPage extends StatelessWidget {
  final AppRuntime runtime;
  const PrintJobsPage({super.key, required this.runtime});
  Future<void> claim(
    BuildContext context,
    Map<String, dynamic> data,
    int version,
  ) async {
    try {
      final id = data['id'] as String, token = const Uuid().v4();
      await runtime.vault.writeData('printClaim.$id', {'token': token});
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
                        Text('Trạng thái: ${data['status']}'),
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.windows &&
                            runtime.stationSession != null &&
                            allowed(runtime, Operation.printClaim)) ...[
                          if (data['status'] == 'queued')
                            OutlinedButton(
                              onPressed: () =>
                                  claim(context, data, row.version),
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
              StreamBuilder(
                stream: runtime.db.select(runtime.db.printJobs).watch(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Không đọc được nhật ký.'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    children: [
                      for (final row in snapshot.data!.reversed.take(100))
                        ListTile(
                          title: Text(row.documentId),
                          subtitle: Text(
                            '${row.createdAt.toLocal()} • ${row.status}',
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
            ],
          ),
        ),
      ],
    ),
  );
}
