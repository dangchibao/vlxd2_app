import 'package:flutter/material.dart';

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
  @override
  void dispose() {
    for (final c in [area, width, height, tiles, waste]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int? result;
    String? error;
    try {
      result = MaterialEstimate.tileBoxes(
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
          'Tính vật liệu — gạch',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tính theo quy cách chính xác và làm tròn lên số thùng nguyên. Kết quả là đề xuất, chưa tạo đơn hoặc giữ hàng.',
        ),
        const SizedBox(height: 20),
        for (final field in [
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
                'Đề xuất: $result thùng',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
