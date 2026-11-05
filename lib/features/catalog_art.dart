import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';

final _currency = NumberFormat.decimalPattern('vi');

const catalogArt = 'assets/catalog';
const sampleImages = {
  'asset:tile-white': 'Trắng vân mây',
  'asset:tile-stone': 'Xám vân đá',
  'asset:tile-beige': 'Be vân đá',
  'asset:tile-gray': 'Xám nhạt',
};

class ProductPhoto extends StatelessWidget {
  final Object? source;
  final double size;
  const ProductPhoto(this.source, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: Color(0xffe7effc),
      child: Center(
        child: Icon(Icons.inventory_2_outlined, color: Color(0xff225d9f)),
      ),
    );
    final uri = source is String ? Uri.tryParse(source as String) : null;
    final Widget child;
    if (sampleImages.containsKey(source)) {
      child = Image.asset(
        '$catalogArt/${uri!.path}.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else if (uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      child = Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        loadingBuilder: (_, image, progress) =>
            progress == null ? image : fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      child = fallback;
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
    );
  }
}

class SampleCatalog extends StatefulWidget {
  const SampleCatalog({super.key});

  static void open(BuildContext context) =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => const SampleCatalog()));

  @override
  State<SampleCatalog> createState() => _SampleCatalogState();
}

class _SampleCatalogState extends State<SampleCatalog> {
  late final samples = _load();
  String search = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final raw = await rootBundle.loadString('$catalogArt/samples.json');
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  String _price(Map<String, dynamic> item) =>
      "${_currency.format(item['price'] as int)} đ / ${item['unit']}";

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Danh mục mẫu'),
      backgroundColor: const Color(0xff0055d9),
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ảnh, giá và tồn dưới đây là dữ liệu minh họa.'),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) =>
                    setState(() => search = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Tìm theo mã hoặc tên gạch',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder(
                  future: samples,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Không đọc được danh mục mẫu.'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = snapshot.data!
                        .where(
                          (item) => "${item['sku']} ${item['name']}"
                              .toLowerCase()
                              .contains(search),
                        )
                        .toList();
                    if (rows.isEmpty) {
                      return const Center(
                        child: Text('Không tìm thấy hàng mẫu.'),
                      );
                    }
                    return LayoutBuilder(
                      builder: (context, size) {
                        if (size.maxWidth < 670) {
                          return ListView(
                            children: [
                              for (final item in rows)
                                Card(
                                  child: ListTile(
                                    leading: ProductPhoto(item['imageUrl']),
                                    title: Text(item['name'] as String),
                                    subtitle: Text(
                                      "${item['sku']} · ${item['model']}\n${_price(item)} · Tồn mẫu ${item['stock']} ${item['unit']}",
                                    ),
                                    isThreeLine: true,
                                  ),
                                ),
                            ],
                          );
                        }
                        return SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: size.maxWidth,
                              ),
                              child: DataTable(
                                columnSpacing: 16,
                                horizontalMargin: 12,
                                headingRowColor: const WidgetStatePropertyAll(
                                  Color(0xffe7effc),
                                ),
                                columns: [
                                  for (final title in [
                                    'Hình ảnh',
                                    'Mã hàng',
                                    'Tên hàng',
                                    'Quy cách',
                                    'Giá bán',
                                    'Tồn mẫu',
                                  ])
                                    DataColumn(label: Text(title)),
                                ],
                                rows: [
                                  for (final item in rows)
                                    DataRow(
                                      cells: [
                                        DataCell(
                                          ProductPhoto(
                                            item['imageUrl'],
                                            size: 36,
                                          ),
                                        ),
                                        DataCell(Text(item['sku'] as String)),
                                        DataCell(Text(item['name'] as String)),
                                        DataCell(Text(item['model'] as String)),
                                        DataCell(Text(_price(item))),
                                        DataCell(
                                          Text(
                                            "${item['stock']} ${item['unit']}",
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
