import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import 'business_pages.dart';
import 'brand_mark.dart';

class SettingsPage extends StatefulWidget {
  final AppRuntime runtime;
  const SettingsPage({super.key, required this.runtime});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final password = TextEditingController(), confirm = TextEditingController();
  bool busy = false;
  String message = '';
  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> editStore() async {
    final db = widget.runtime.db;
    final row = await (db.select(
      db.businessRecords,
    )..where((r) => r.id.equals('settings:store'))).getSingleOrNull();
    if (!mounted) return;
    final data = row == null ? <String, dynamic>{} : recordData(row);
    await commandDialog(
      context,
      widget.runtime,
      title: 'Thông tin cửa hàng',
      operation: Operation.settings,
      entityId: 'store',
      version: row?.version ?? 0,
      fields: [
        InputField(
          'name',
          'Tên cửa hàng',
          initial: data['name'] as String? ?? 'VLXD Bảy Hải',
        ),
        InputField(
          'address',
          'Địa chỉ',
          initial: data['address'] as String? ?? '',
          optional: true,
        ),
        InputField(
          'phone',
          'Điện thoại',
          initial: data['phone'] as String? ?? '',
          optional: true,
        ),
        InputField(
          'taxCode',
          'Mã số thuế (nếu có)',
          initial: data['taxCode'] as String? ?? '',
          optional: true,
        ),
      ],
    );
  }

  Future<void> changePassword() async {
    if (password.text != confirm.text || password.text.length < 10) {
      setState(
        () => message = 'Hai mật khẩu phải giống nhau và ít nhất 10 ký tự.',
      );
      return;
    }
    final value = password.text;
    password.clear();
    confirm.clear();
    setState(() => busy = true);
    await widget.runtime.changePassword(value);
    if (mounted) {
      setState(() {
        busy = false;
        message = widget.runtime.error ?? 'Đã đổi mật khẩu.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text(
        'Thiết lập cửa hàng',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const Card(
        child: ListTile(
          leading: BrandMark(size: 48),
          title: Text('VLXD Bảy Hải'),
          subtitle: Text('Gò Dầu · Tây Ninh'),
        ),
      ),
      ListTile(
        title: const Text('Kết nối'),
        subtitle: Text(
          '${widget.runtime.config.projectId} • Cửa hàng ${widget.runtime.config.storeId}',
        ),
      ),
      if (allowed(widget.runtime, Operation.settings))
        OutlinedButton(
          onPressed: editStore,
          child: const Text('Sửa thông tin cửa hàng'),
        ),
      const Divider(height: 40),
      const Text(
        'Đổi mật khẩu',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: confirm,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới'),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: busy ? null : changePassword,
        child: const Text('Đổi mật khẩu'),
      ),
      if (message.isNotEmpty) Text(message),
      const Divider(height: 40),
      const Text(
        'Máy in K80: chọn máy in trong hộp thoại Windows khi gửi phiếu. Nhật ký gửi in nằm ở mục Yêu cầu / Nhật ký in.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Hóa đơn điện tử: chỉ chuẩn bị dữ liệu, không tự phát hành hoặc áp thuế suất mặc định.',
      ),
    ],
  );
}
