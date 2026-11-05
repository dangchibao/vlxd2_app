import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../data/backup_service.dart';
import '../data/xlsx_catalog.dart';
import '../data/xlsx_parties.dart';
import '../data/database.dart';
import '../domain/operations.dart';
import 'business_pages.dart';

class DataToolsPage extends StatefulWidget {
  final AppRuntime runtime;
  const DataToolsPage({super.key, required this.runtime});
  @override
  State<DataToolsPage> createState() => _DataToolsPageState();
}

class _DataToolsPageState extends State<DataToolsPage> {
  bool busy = false;
  String message = '';
  List<CatalogImportRow> rows = [];
  List<PartyImportRow> partyRows = [];
  late final owner = widget.runtime.actor!.uid;
  final password = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  bool get manager =>
      {StaffRole.admin, StaffRole.manager}.contains(widget.runtime.actor?.role);
  Future<void> action(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message
              : e is BusinessException
              ? e.message
              : 'Không thực hiện được. Kiểm tra file hoặc quyền truy cập.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export({bool template = false}) async {
    final products = template
        ? <dynamic>[]
        : await widget.runtime.db.select(widget.runtime.db.products).get();
    final bytes = template
        ? XlsxCatalog().table(XlsxCatalog.headers, [])
        : XlsxCatalog().export(products.cast());
    final saved = await FilePicker.saveFile(
      fileName: template ? 'mau-hang-hoa.xlsx' : 'hang-hoa.xlsx',
      bytes: bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (mounted) {
      setState(
        () => message = saved == null
            ? 'Đã đóng hộp thoại lưu.'
            : 'Đã xuất file Excel.',
      );
    }
  }

  Future<void> pickExcel() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (file == null) return;
    final length = await file.length();
    if (length != null && length > 10 * 1024 * 1024) {
      throw const FormatException('File vượt 10 MB.');
    }
    final products = await widget.runtime.db
        .select(widget.runtime.db.products)
        .get();
    final pending = await widget.runtime.db
        .select(widget.runtime.db.outbox)
        .get();
    final known = {
      ...products.map((p) => p.sku),
      for (final p in pending)
        if (p.operation == 'catalog' && p.status != 'error')
          ((jsonDecode(p.payload) as Map<String, dynamic>)['sku'] as String)
              .trim()
              .toUpperCase(),
    };
    final preview = XlsxCatalog().preview(
      await file.readAsBytes(),
      existingSkus: known,
    );
    if (mounted) {
      setState(() {
        rows = preview;
        message =
            '${rows.length} dòng • ${rows.where((r) => r.errors.isNotEmpty).length} dòng có lỗi. Chưa ghi dữ liệu.';
      });
    }
  }

  Future<void> exportParties({bool template = false}) async {
    final records = template
        ? <BusinessRecord>[]
        : await (widget.runtime.db.select(
            widget.runtime.db.businessRecords,
          )..where((r) => r.kind.equals('party'))).get();
    await FilePicker.saveFile(
      fileName: template ? 'mau-doi-tac.xlsx' : 'doi-tac.xlsx',
      bytes: XlsxParties().export(records.map(recordData).toList()),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> pickParties() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (file == null) return;
    if ((await file.length() ?? 0) > 10 * 1024 * 1024) {
      throw const FormatException('File vượt 10 MB.');
    }
    if (widget.runtime.actor?.uid != owner) {
      throw const BusinessException('permission', 'Phiên đã thay đổi.');
    }
    final db = widget.runtime.db;
    final known = <String>{};
    for (final row in await (db.select(
      db.businessRecords,
    )..where((r) => r.kind.equals('party'))).get()) {
      known.add((recordData(row)['code'] as String? ?? '').toUpperCase());
    }
    for (final row in await db.select(db.outbox).get()) {
      if (row.operation == 'party' && row.status != 'error') {
        known.add(
          ((jsonDecode(row.payload) as Map<String, dynamic>)['code']
                      as String? ??
                  '')
              .toUpperCase(),
        );
      }
    }
    final preview = XlsxParties().preview(await file.readAsBytes(), known);
    if (mounted) {
      setState(() {
        partyRows = preview;
        message =
            '${preview.length} đối tác • ${preview.where((r) => r.errors.isNotEmpty).length} dòng lỗi. Chưa ghi dữ liệu.';
      });
    }
  }

  Future<void> importParties() async {
    if (!manager ||
        widget.runtime.actor?.uid != owner ||
        partyRows.isEmpty ||
        partyRows.any((r) => r.errors.isNotEmpty)) {
      throw const BusinessException(
        'permission',
        'Cần quản lý và bảng dữ liệu hợp lệ.',
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nhập đối tác'),
        content: Text(
          'Tạo ${partyRows.length} đối tác mới; không ghi đè đối tác đã có.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận nhập'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.runtime.actor?.uid != owner) {
      throw const BusinessException('permission', 'Phiên đã thay đổi.');
    }
    await widget.runtime.db.transaction(() async {
      for (final row in partyRows) {
        await widget.runtime.enqueue(
          Operation.party,
          const Uuid().v4(),
          row.payload,
          syncNow: false,
        );
      }
    });
    if (mounted) {
      setState(() {
        message = 'Đã đưa ${partyRows.length} đối tác vào hàng đợi.';
        partyRows = [];
      });
    }
    await widget.runtime.tick();
  }

  Future<void> importRows() async {
    if (!allowed(widget.runtime, Operation.catalog) ||
        rows.isEmpty ||
        rows.any((r) => r.errors.isNotEmpty)) {
      throw const BusinessException(
        'validation',
        'Chưa có dữ liệu hợp lệ để nhập.',
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận nhập hàng hóa'),
        content: Text(
          'Tạo ${rows.length} hàng hóa mới vào hàng đợi. Không ghi đè hàng hóa đã có.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận nhập'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.runtime.db.transaction(() async {
      for (final row in rows) {
        await widget.runtime.enqueue(
          Operation.catalog,
          const Uuid().v4(),
          row.payload,
          syncNow: false,
        );
      }
    });
    if (mounted) {
      setState(() {
        message = 'Đã lưu ${rows.length} hàng hóa vào hàng đợi.';
        rows = [];
      });
    }
    await widget.runtime.tick();
  }

  BackupService get backup => BackupService(
    widget.runtime.db,
    storeId: widget.runtime.config.storeId,
    projectId: widget.runtime.config.projectId,
    userId: widget.runtime.actor!.uid,
  );
  Future<void> createBackup() async {
    if (!manager) {
      throw const BusinessException(
        'permission',
        'Chỉ quản lý được sao lưu dữ liệu.',
      );
    }
    final secret = password.text;
    password.clear();
    final bytes = await backup.create(secret);
    final saved = await FilePicker.saveFile(
      fileName: 'bayhai-${DateTime.now().millisecondsSinceEpoch}.bhbackup',
      bytes: bytes,
    );
    if (saved != null) {
      await widget.runtime.db
          .into(widget.runtime.db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              action: 'backup_created',
              entityId: saved.toString(),
              createdAt: DateTime.now(),
            ),
          );
    }
    if (mounted) {
      setState(
        () => message = saved == null
            ? 'Đã đóng hộp thoại lưu.'
            : 'Đã lưu bản sao mã hóa. Giữ mật khẩu riêng với file.',
      );
    }
  }

  Future<void> restoreBackup() async {
    if (!manager) {
      throw const BusinessException(
        'permission',
        'Chỉ quản lý được khôi phục dữ liệu.',
      );
    }
    if (widget.runtime.syncing) {
      throw const BusinessException(
        'busy',
        'Đang đồng bộ. Đợi hoàn tất rồi thử lại.',
      );
    }
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['bhbackup'],
    );
    if (file == null) return;
    final length = await file.length();
    if (length != null && length > 100 * 1024 * 1024) {
      throw const FormatException('Bản sao vượt 100 MB.');
    }
    final secret = password.text;
    password.clear();
    final preview = await backup.preview(await file.readAsBytes(), secret);
    if (!mounted) return;
    bool acknowledge = false;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Khôi phục dữ liệu cục bộ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bản sao đúng cửa hàng và tài khoản, ${preview.rows} dòng dữ liệu. Dữ liệu hiện tại trên thiết bị sẽ được thay bằng bản sao. Cloud không bị ghi đè.',
              ),
              CheckboxListTile(
                value: acknowledge,
                onChanged: (v) => update(() => acknowledge = v ?? false),
                title: const Text(
                  'Tôi đã lưu bản sao hiện tại và đồng ý khôi phục.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: acknowledge
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Khôi phục'),
            ),
          ],
        ),
      ),
    );
    if (approved != true) return;
    if (widget.runtime.syncing) {
      throw const BusinessException(
        'busy',
        'Đồng bộ vừa bắt đầu. Hãy xem trước lại.',
      );
    }
    widget.runtime.maintenance = true;
    try {
      await backup.restore(preview, acknowledged: true);
      await widget.runtime.db
          .into(widget.runtime.db.auditEvents)
          .insert(
            AuditEventsCompanion.insert(
              action: 'backup_restored',
              entityId: 'local:${preview.rows}',
              createdAt: DateTime.now(),
            ),
          );
    } finally {
      widget.runtime.maintenance = false;
    }
    if (mounted) {
      setState(
        () => message = 'Đã khôi phục cục bộ. Đồng bộ sẽ đối chiếu receipt, không đẩy snapshot ghi đè cloud.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text(
        'Excel và sao lưu',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => action(() => export(template: true)),
            child: const Text('Tải mẫu hàng hóa'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => action(export),
            child: const Text('Xuất hàng hóa'),
          ),
          if (allowed(widget.runtime, Operation.catalog))
            FilledButton(
              onPressed: busy ? null : () => action(pickExcel),
              child: const Text('Chọn Excel để xem trước'),
            ),
        ],
      ),
      if (message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(message),
        ),
      if (busy) const LinearProgressIndicator(),
      if (rows.isNotEmpty) ...[
        for (final row in rows.take(100))
          Card(
            child: ListTile(
              title: Text('Dòng ${row.line} • ${row.sku} • ${row.name}'),
              subtitle: Text(
                row.errors.isEmpty
                    ? '${row.unit} • ${row.price} đ'
                    : row.errors.join('\n'),
              ),
              leading: Icon(
                row.errors.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: row.errors.isEmpty ? Colors.green : Colors.red,
              ),
            ),
          ),
        FilledButton(
          onPressed: busy || rows.any((r) => r.errors.isNotEmpty)
              ? null
              : () => action(importRows),
          child: Text('Nhập ${rows.length} dòng đã kiểm tra'),
        ),
      ],
      if (manager) ...[
        const Divider(height: 40),
        const Text(
          'Khách hàng / Nhà cung cấp',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => action(() => exportParties(template: true)),
              child: const Text('Tải mẫu đối tác'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => action(exportParties),
              child: const Text('Xuất đối tác'),
            ),
            FilledButton(
              onPressed: busy ? null : () => action(pickParties),
              child: const Text('Xem trước Excel đối tác'),
            ),
          ],
        ),
        for (final row in partyRows.take(100))
          ListTile(
            title: Text(
              'Dòng ${row.line} • ${row.payload['code']} • ${row.payload['name']}',
            ),
            subtitle: Text(
              row.errors.isEmpty ? 'Hợp lệ' : row.errors.join('\n'),
            ),
          ),
        if (partyRows.isNotEmpty)
          FilledButton(
            onPressed: busy || partyRows.any((r) => r.errors.isNotEmpty)
                ? null
                : () => action(importParties),
            child: const Text('Nhập đối tác đã kiểm tra'),
          ),
        const Divider(height: 40),
        const Text(
          'Sao lưu có mã hóa',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Mật khẩu ít nhất 10 ký tự. Bản sao chứa dữ liệu cục bộ, không phải dịch vụ đồng bộ và không chứa mật khẩu đăng nhập.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: password,
          obscureText: true,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Mật khẩu bản sao'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: busy ? null : () => action(createBackup),
              child: const Text('Tạo bản sao'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => action(restoreBackup),
              child: const Text('Xem trước và khôi phục'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Lịch sử sao lưu / khôi phục'),
        StreamBuilder(
          stream: widget.runtime.db
              .select(widget.runtime.db.auditEvents)
              .watch(),
          builder: (context, snapshot) => Column(
            children: [
              for (final row
                  in (snapshot.data ?? []).reversed
                      .where((r) => r.action.startsWith('backup_'))
                      .take(20))
                ListTile(
                  title: Text(
                    row.action == 'backup_created'
                        ? 'Đã lưu bản sao'
                        : 'Đã khôi phục cục bộ',
                  ),
                  subtitle: Text('${row.createdAt.toLocal()}'),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}
