import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../domain/store_alerts.dart';
import 'business_pages.dart';
import 'reports_search.dart';

class AlertsPage extends StatelessWidget {
  final AppRuntime runtime;
  const AlertsPage({super.key, required this.runtime});
  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: runtime.db.select(runtime.db.businessRecords).watch(),
    builder: (context, records) => StreamBuilder(
      stream: runtime.db.watchQueue(),
      builder: (context, queue) {
        if (records.hasError || queue.hasError) {
          return const Center(child: Text('Không tải được cảnh báo.'));
        }
        if (!records.hasData || !queue.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final alerts = StoreAlerts.derive(
          records.data!,
          queue.data!,
          DateTime.now(),
        );
        return ListView(
          children: [
            const Text(
              'Cảnh báo cần xử lý',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Chưa có cảnh báo từ dữ liệu đã lưu.'),
              ),
            for (final alert in alerts)
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: Colors.orange,
                  ),
                  title: Text(alert.title),
                  subtitle: Text(alert.detail),
                  onTap: () {
                    final row = records.data!
                        .where((r) => r.id == alert.recordId)
                        .firstOrNull;
                    if (row == null) {
                      feedback(context, 'Mở Đồng bộ để xem và xử lý hàng đợi.');
                      return;
                    }
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(alert.title),
                        content: SingleChildScrollView(
                          child: RecordDetails(data: recordData(row)),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Đóng'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
