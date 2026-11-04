import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';
import 'business_pages.dart';

class VehiclesPage extends StatelessWidget {
  final AppRuntime runtime;
  const VehiclesPage({super.key, required this.runtime});
  Future<void> edit(
    BuildContext context, [
    Map<String, dynamic> data = const {},
    int version = 0,
  ]) => commandDialog(
    context,
    runtime,
    title: 'Thông tin xe',
    operation: Operation.vehicle,
    entityId: data['id'] as String? ?? const Uuid().v4(),
    version: version,
    fields: [
      InputField('name', 'Tên xe', initial: data['name'] as String? ?? ''),
      InputField('plate', 'Biển số', initial: data['plate'] as String? ?? ''),
      InputField(
        'capacityKg',
        'Tải trọng cho phép khai báo (kg)',
        number: true,
        initial: '${data['capacityKg'] ?? 1000}',
      ),
      InputField(
        'active',
        'Trạng thái',
        initial: data['active'] == false ? 'false' : 'true',
        choices: const [('true', 'Hoạt động'), ('false', 'Ngừng hoạt động')],
      ),
    ],
    transform: (p) => {...p, 'active': p['active'] == 'true'},
  );
  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'vehicle',
    title: 'Xe giao hàng',
    actions: [
      if (allowed(runtime, Operation.vehicle))
        FilledButton.icon(
          onPressed: () => edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Thêm xe'),
        ),
    ],
    item: (context, row, data) => Card(
      child: ListTile(
        title: Text('${data['name']} • ${data['plate']}'),
        subtitle: Text(
          '${data['capacityKg']} kg • ${data['active'] == false ? 'Ngừng hoạt động' : 'Hoạt động'}',
        ),
        trailing: allowed(runtime, Operation.vehicle)
            ? IconButton(
                onPressed: () => edit(context, data, row.version),
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      ),
    ),
  );
}
