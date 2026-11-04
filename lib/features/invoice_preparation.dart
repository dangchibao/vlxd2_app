import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../domain/electronic_invoice.dart';
import 'business_pages.dart';

Future<void> prepareInvoice(
  BuildContext context,
  AppRuntime runtime,
  Map<String, dynamic> sale,
) async {
  try {
    final buyer = Map<String, dynamic>.from(
      sale['buyerSnapshot'] as Map? ?? {},
    );
    buyer['name'] ??= sale['customerName'];
    final draft = ElectronicInvoiceDraft.fromSale(
      sale,
      buyer: buyer,
      taxByProduct: {},
    );
    if (!context.mounted) return;
    final export = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chuẩn bị dữ liệu hóa đơn điện tử'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Người mua: ${buyer['name'] ?? 'Chưa đủ thông tin'}'),
              Text('Tổng chứng từ: ${vnd(draft.total)}'),
              Text(
                draft.readyForProviderValidation
                    ? 'Có dữ liệu phân loại thuế để nhà cung cấp kiểm tra tiếp.'
                    : 'Còn thiếu thông tin người mua hoặc cấu hình thuế. Dữ liệu được đánh dấu chưa sẵn sàng.',
              ),
              if ((sale['returnedValue'] as int? ?? 0) > 0)
                const Text(
                  'Đơn đã có trả hàng: cần nhà cung cấp xử lý quy trình điều chỉnh phù hợp.',
                ),
              const SizedBox(height: 12),
              const Text(
                'Chỉ xuất dữ liệu chuẩn bị. Chưa tính hoặc kiểm tra đầy đủ thuế theo API nhà cung cấp; không phát hành hóa đơn.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xuất JSON chuẩn bị'),
          ),
        ],
      ),
    );
    if (export == true) {
      await FilePicker.saveFile(
        fileName: 'chuan-bi-hoa-don-${sale['id']}.json',
        bytes: Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ').convert({
              ...draft.toJson(),
              'readyForProviderValidation': draft.readyForProviderValidation,
              'hasReturns': (sale['returnedValue'] as int? ?? 0) > 0,
            }),
          ),
        ),
        mimeType: 'application/json',
      );
    }
  } catch (_) {
    if (context.mounted) {
      feedback(context, 'Không chuẩn bị được dữ liệu từ chứng từ này.');
    }
  }
}
