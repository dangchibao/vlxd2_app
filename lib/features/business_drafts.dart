import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_runtime.dart';
import 'business_pages.dart';

class BusinessDraftsPage extends StatelessWidget {
  final AppRuntime runtime;
  const BusinessDraftsPage({super.key, required this.runtime});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đơn nháp cục bộ')),
    body: StreamBuilder(
      stream: runtime.db.watchDrafts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Không đọc được nháp.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!
            .where(
              (r) =>
                  r.status == 'draft' &&
                  {'sale', 'purchase', 'quote'}.contains(
                    (jsonDecode(r.payload) as Map<String, dynamic>)['kind'],
                  ),
            )
            .toList();
        if (rows.isEmpty) return const Center(child: Text('Chưa có đơn nháp.'));
        return ListView(
          children: [
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(
                    '${(jsonDecode(row.payload) as Map<String, dynamic>)['kind'] == 'purchase' ? 'Đơn mua' : 'Đơn bán'} • ${shortId(row.id)}',
                  ),
                  subtitle: Text(
                    'Lưu lúc ${DateFormat('dd/MM/yyyy HH:mm:ss').format(row.updatedAt)}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => OrderComposer(
                        runtime: runtime,
                        draft: row,
                        quote:
                            (jsonDecode(row.payload)
                                as Map<String, dynamic>)['kind'] ==
                            'quote',
                        purchase:
                            (jsonDecode(row.payload)
                                as Map<String, dynamic>)['kind'] ==
                            'purchase',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
