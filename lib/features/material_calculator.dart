import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../domain/operations.dart';

int parseFixed(String text, int scale) {
  final normalized = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(normalized)) {
    throw const FormatException(
      'Nhập số không âm, dùng dấu phẩy hoặc chấm cho phần thập phân.',
    );
  }
  final parts = normalized.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > scale) {
    throw FormatException('Tối đa $scale chữ số thập phân.');
  }
  final value = BigInt.parse(parts[0] + fraction.padRight(scale, '0'));
  if (value > BigInt.from(9000000000000)) {
    throw const FormatException('Giá trị vượt giới hạn.');
  }
  return value.toInt();
}

class MaterialCalculator extends StatefulWidget {
  const MaterialCalculator({super.key});
  @override
  State<MaterialCalculator> createState() => _MaterialCalculatorState();
}

class _MaterialCalculatorState extends State<MaterialCalculator> {
  final area = TextEditingController(text: '10'),
      width = TextEditingController(text: '600'),
      height = TextEditingController(text: '600'),
      tiles = TextEditingController(text: '4'),
      waste = TextEditingController(text: '5');
  final pipeLength = TextEditingController(text: '10'),
      stickLength = TextEditingController(text: '4'),
      volumeLength = TextEditingController(text: '10'),
      volumeWidth = TextEditingController(text: '2'),
      volumeHeight = TextEditingController(text: '0,1'),
      proposedQuantity = TextEditingController();
  String mode = 'tile';
  bool manual = false;
  @override
  void dispose() {
    for (final c in [
      area,
      width,
      height,
      tiles,
      waste,
      pipeLength,
      stickLength,
      volumeLength,
      volumeWidth,
      volumeHeight,
      proposedQuantity,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int? result;
    String? error;
    try {
      result = mode == 'pipe'
          ? MaterialEstimate.pipeSticks(
              lengthMm: parseFixed(pipeLength.text, 3),
              stickLengthMm: parseFixed(stickLength.text, 3),
              wasteBasisPoints: parseFixed(waste.text, 2),
            )
          : mode == 'volume'
          ? MaterialEstimate.volumeScaled(
              lengthMm: parseFixed(volumeLength.text, 3),
              widthMm: parseFixed(volumeWidth.text, 3),
              heightMm: parseFixed(volumeHeight.text, 3),
              wasteBasisPoints: parseFixed(waste.text, 2),
            )
          : MaterialEstimate.tileBoxes(
              areaSquareMm: parseFixed(area.text, 6),
              tileWidthMm: parseFixed(width.text, 0),
              tileHeightMm: parseFixed(height.text, 0),
              tilesPerBox: parseFixed(tiles.text, 0),
              wasteBasisPoints: parseFixed(waste.text, 2),
            );
    } on FormatException catch (e) {
      error = e.message;
    } on BusinessException catch (e) {
      error = e.message;
    }
    return ListView(
      children: [
        const Text(
          'Tính vật liệu',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: mode,
          items: const [
            DropdownMenuItem(
              value: 'tile',
              child: Text('Gạch • Diện tích → Thùng'),
            ),
            DropdownMenuItem(
              value: 'pipe',
              child: Text('Ống / Cây • Mét → Số cây'),
            ),
            DropdownMenuItem(
              value: 'volume',
              child: Text('Thể tích • Kích thước → m³'),
            ),
          ],
          onChanged: (v) => setState(() {
            mode = v!;
            manual = false;
          }),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tính chính xác, làm tròn lên theo đơn vị bán. Kết quả là đề xuất, chưa tạo đơn hoặc giữ hàng.',
        ),
        const SizedBox(height: 20),
        for (final field
            in mode == 'pipe'
                ? [
                    (pipeLength, 'Tổng chiều dài cần (m)'),
                    (stickLength, 'Chiều dài một cây (m)'),
                    (waste, 'Hao hụt (%)'),
                  ]
                : mode == 'volume'
                ? [
                    (volumeLength, 'Chiều dài (m)'),
                    (volumeWidth, 'Chiều rộng (m)'),
                    (volumeHeight, 'Chiều cao / Độ dày (m)'),
                    (waste, 'Hao hụt (%)'),
                  ]
                : [
                    (area, 'Diện tích cần lát (m²)'),
                    (width, 'Chiều rộng viên (mm)'),
                    (height, 'Chiều dài viên (mm)'),
                    (tiles, 'Số viên / thùng'),
                    (waste, 'Hao hụt (%)'),
                  ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: field.$1,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: field.$2),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (error != null)
          Text(error, style: const TextStyle(color: Colors.red))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                mode == 'pipe'
                    ? 'Đề xuất: $result cây'
                    : mode == 'volume'
                    ? 'Đề xuất: ${NumberFormat('0.###', 'vi').format(result! / 1000)} m³'
                    : 'Đề xuất: $result thùng',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        SwitchListTile(
          title: const Text('Sửa số lượng đề xuất'),
          value: manual,
          onChanged: (v) => setState(() {
            manual = v;
            if (v) {
              proposedQuantity.text = mode == 'volume'
                  ? NumberFormat('0.###', 'vi').format((result ?? 0) / 1000)
                  : '${result ?? 0}';
            }
          }),
        ),
        if (manual)
          TextField(
            controller: proposedQuantity,
            decoration: const InputDecoration(labelText: 'Số lượng muốn dùng'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        if (error == null)
          OutlinedButton.icon(
            onPressed: () async {
              final value = manual
                  ? proposedQuantity.text
                  : (mode == 'volume'
                        ? NumberFormat('0.###', 'vi').format(result! / 1000)
                        : '$result');
              try {
                parseFixed(value, mode == 'volume' ? 3 : 0);
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã sao chép số lượng để nhập vào đơn.'),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Số lượng muốn dùng chưa hợp lệ.'),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Sao chép số lượng dùng'),
          ),
      ],
    );
  }
}
