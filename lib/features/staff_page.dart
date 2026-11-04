import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import '../data/firestore_rest.dart';
import 'business_pages.dart';

class StaffPage extends StatefulWidget {
  final AppRuntime runtime;
  const StaffPage({super.key, required this.runtime});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  Future<List<RemoteDocument>>? users;
  Future<List<RemoteDocument>> load() async => widget.runtime.firestore.query(
    'stores/${widget.runtime.config.storeId}',
    {
      'from': [
        {'collectionId': 'members'},
      ],
      'limit': 100,
    },
    await widget.runtime.currentSession(),
  );
  @override
  void initState() {
    super.initState();
    if ({
      StaffRole.admin,
      StaffRole.manager,
    }.contains(widget.runtime.actor?.role)) {
      users = load();
    }
  }

  Future<void> edit(RemoteDocument row) async {
    final uid = row.name.split('/').last, data = row.data;
    final record = await (widget.runtime.db.select(
      widget.runtime.db.businessRecords,
    )..where((r) => r.id.equals('staff:$uid'))).getSingleOrNull();
    if (!mounted) return;
    await commandDialog(
      context,
      widget.runtime,
      title: 'Quyền nhân viên',
      operation: Operation.staff,
      entityId: uid,
      version: record?.version ?? 0,
      fields: [
        InputField(
          'displayName',
          'Tên hiển thị',
          initial: data['displayName'] as String? ?? uid,
        ),
        InputField(
          'role',
          'Vai trò',
          initial: data['role'] as String,
          choices: const [
            ('admin', 'Admin'),
            ('manager', 'Quản lý'),
            ('sales', 'Bán hàng'),
            ('warehouse', 'Kho'),
            ('driver', 'Giao hàng'),
          ],
        ),
        InputField(
          'active',
          'Trạng thái',
          initial: data['active'] == true ? 'true' : 'false',
          choices: const [('true', 'Hoạt động'), ('false', 'Khóa')],
        ),
      ],
      transform: (p) => {...p, 'active': p['active'] == 'true'},
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Nhân viên và phân quyền',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Tạo tài khoản và xác minh đổi mật khẩu bằng công cụ quản trị của chủ project. Quyền mới chỉ có hiệu lực sau khi trạm xác nhận.',
        ),
      ),
      if (users == null)
        const Text('Chỉ Admin hoặc Quản lý được xem danh sách nhân viên.')
      else ...[
        OutlinedButton(
          onPressed: () => setState(() => users = load()),
          child: const Text('Tải lại'),
        ),
        Expanded(
          child: FutureBuilder(
            future: users,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Không tải được nhân viên. Kiểm tra kết nối và quyền.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  for (final row in snapshot.data!)
                    ListTile(
                      title: Text(
                        row.data['displayName'] as String? ??
                            row.name.split('/').last,
                      ),
                      subtitle: Text(
                        '${row.data['role']} • ${row.data['active'] == true ? 'Hoạt động' : 'Đã khóa'} ${row.data['mustChangePassword'] == true ? '• Chờ đổi mật khẩu / kích hoạt' : ''}',
                      ),
                      trailing:
                          allowed(widget.runtime, Operation.staff) &&
                              row.data['role'] != 'station' &&
                              row.name.split('/').last !=
                                  widget.runtime.actor?.uid
                          ? IconButton(
                              onPressed: () => edit(row),
                              icon: const Icon(Icons.manage_accounts_outlined),
                            )
                          : null,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ],
  );
}
