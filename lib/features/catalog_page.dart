import 'package:drift/drift.dart'
    show StringExpressionOperators, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../data/receipt_printer.dart';
import 'business_receipt.dart';
import '../domain/operations.dart';
import '../domain/product_policy.dart';
import 'business_pages.dart';
import 'catalog_art.dart';
import 'barcode_scan.dart';
import 'material_calculator.dart';
import 'reports_search.dart';
import 'bayhai_style.dart';

class CatalogPage extends StatelessWidget {
  final AppRuntime runtime;
  const CatalogPage({super.key, required this.runtime});
  void edit(BuildContext context, [BusinessRecord? row]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => CatalogEditor(runtime: runtime, row: row),
    ),
  );
  Future<void> openLabel(
    BuildContext context,
    Map<String, dynamic> product,
  ) async {
    final codes = [
      product['barcode'],
      product['sku'],
    ].whereType<String>().where(validLabelCode).toSet().toList();
    if (codes.isEmpty) {
      feedback(context, 'Cần SKU hoặc mã vạch hợp lệ để tạo tem.');
      return;
    }
    var code = codes.first, copies = '1';
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Tạo tem mã vạch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: code,
                decoration: const InputDecoration(labelText: 'Mã trên tem'),
                items: [
                  for (final option in codes)
                    DropdownMenuItem(value: option, child: Text(option)),
                ],
                onChanged: (value) => code = value!,
              ),
              TextFormField(
                initialValue: copies,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tem, từ 1 đến 100',
                ),
                onChanged: (value) => update(() => copies = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed:
                  (int.tryParse(copies) ?? 0) < 1 ||
                      (int.tryParse(copies) ?? 0) > 100
                  ? null
                  : () => Navigator.pop(context, {
                      ...product,
                      'labelCode': code,
                      'copies': int.parse(copies),
                    }),
              child: const Text('Xem trước'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BusinessReceipt(
          database: runtime.db,
          kind: 'barcodeLabel',
          data: selected,
        ),
      ),
    );
  }

  Future<void> priceHistory(
    BuildContext context,
    Map<String, dynamic> product,
  ) async {
    final db = runtime.db;
    final rows =
        await (db.select(db.businessRecords)..where(
              (row) =>
                  row.kind.equals('priceHistory') &
                  row.id.like("priceHistory:${product['id']}:%"),
            ))
            .get();
    if (!context.mounted) return;
    final history =
        rows
            .map(recordData)
            .where((entry) => entry['productId'] == product['id'])
            .toList()
          ..sort(
            (a, b) =>
                (b['changedAt'] as String).compareTo(a['changedAt'] as String),
          );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Lịch sử giá • ${product['sku']}"),
        content: SizedBox(
          width: 540,
          child: history.isEmpty
              ? const Text('Chưa có lịch sử giá đã đồng bộ.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in history)
                        ListTile(
                          title: Text(vnd(entry['price'] as int)),
                          subtitle: Text(
                            DateTime.parse(entry['changedAt'] as String)
                                .toLocal()
                                .toString()
                                .split('.')
                                .first,
                          ),
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Chi tiết bảng giá'),
                              content: SingleChildScrollView(
                                child: RecordDetails(data: entry),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'catalog',
    title: 'Danh sách hàng hóa',
    actions: [
      OutlinedButton.icon(
        onPressed: () => SampleCatalog.open(context),
        icon: const Icon(Icons.grid_view_outlined),
        label: const Text('Danh mục mẫu'),
      ),
      if (allowed(runtime, Operation.catalog))
        FilledButton.icon(
          onPressed: () => edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Thêm hàng hóa'),
        ),
    ],
    item: (context, row, data) => Card(
      child: ListTile(
        leading: ProductPhoto(data['imageUrl']),
        title: Text(
          data['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: [data['sku'], data['group'], data['brand'], data['model']]
                    .whereType<String>()
                    .where((part) => part.isNotEmpty)
                    .join(' • '),
                style: const TextStyle(color: BayHaiStyle.muted),
              ),
              TextSpan(
                text: "\n${vnd(data['price'] as int)} / ${data['unit']}",
                style: const TextStyle(
                  color: BayHaiStyle.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (data['active'] == false)
                const TextSpan(text: ' • Ngừng kinh doanh'),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: allowed(runtime, Operation.catalog)
            ? IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => edit(context, row),
              )
            : null,
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(data['name'] as String),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductPhoto(data['imageUrl'], size: 128),
                  const SizedBox(height: 12),
                  RecordDetails(data: data),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => openLabel(context, data),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Tem mã vạch'),
              ),
              TextButton.icon(
                onPressed: () => priceHistory(context, data),
                icon: const Icon(Icons.history),
                label: const Text('Lịch sử giá'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CatalogEditor extends StatefulWidget {
  final AppRuntime runtime;
  final BusinessRecord? row;
  const CatalogEditor({super.key, required this.runtime, this.row});
  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  late final old = widget.row == null
      ? <String, dynamic>{}
      : recordData(widget.row!);
  late final fields = <String, TextEditingController>{
    for (final key in [
      'sku',
      'name',
      'unit',
      'price',
      'group',
      'barcode',
      'brand',
      'model',
      'imageUrl',
      'variantOf',
      'minimumStock',
      'warrantyDays',
      'components',
      'units',
      'priceLists',
      'quantityTiers',
      'attributes',
      'accessories',
      'alternatives',
      'taxRate',
    ])
      key: TextEditingController(),
  };
  String tracking = 'none', error = '';
  String taxTreatment = '';
  bool active = true, busy = false;
  String mapText(Object? value, {bool scaled = false}) => (value as Map? ?? {})
      .entries
      .map((e) => '${e.key}=${scaled ? qty(e.value as int) : e.value}')
      .join('\n');
  @override
  void initState() {
    super.initState();
    for (final entry in fields.entries) {
      entry.value.text = '${old[entry.key] ?? ''}';
    }
    fields['price']!.text = '${old['price'] ?? 0}';
    fields['minimumStock']!.text = qty(old['minimumStock'] as int? ?? 0);
    fields['units']!.text = mapText(old['units'], scaled: true);
    fields['components']!.text = mapText(old['components'], scaled: true);
    fields['warrantyDays']!.text = '${old['warrantyDays'] ?? 0}';
    fields['priceLists']!.text = mapText(old['priceLists']);
    fields['attributes']!.text = mapText(old['attributes']);
    fields['quantityTiers']!.text = (old['quantityTiers'] as List? ?? [])
        .map(
          (e) =>
              '${e['priceList'] ?? ''};${qty(e['minimum'] as int)};${e['price']}',
        )
        .join('\n');
    for (final key in ['accessories', 'alternatives']) {
      fields[key]!.text = (old[key] as List? ?? []).join(', ');
    }
    tracking = old['tracking'] as String? ?? 'none';
    active = old['active'] != false;
    taxTreatment = (old['tax'] as Map?)?['treatment'] as String? ?? '';
    fields['taxRate']!.text = qty(
      ((old['tax'] as Map?)?['rateBasisPoints'] as int? ?? 0) * 10,
    );
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> parsePairs(
    String key,
    Object Function(String value) parse,
  ) {
    final result = <String, dynamic>{};
    for (final row
        in fields[key]!.text.split('\n').where((r) => r.trim().isNotEmpty)) {
      final i = row.indexOf('=');
      if (i <= 0) throw const FormatException('Mỗi dòng cần có Tên=Giá trị.');
      final name = row.substring(0, i).trim();
      if (result.containsKey(name)) throw FormatException('Trùng dòng $name.');
      result[name] = parse(row.substring(i + 1).trim());
    }
    return result;
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final data = <String, dynamic>{
        ...old,
        for (final key in [
          'sku',
          'name',
          'unit',
          'group',
          'barcode',
          'brand',
          'model',
          'imageUrl',
          'variantOf',
        ])
          key: fields[key]!.text.trim(),
        'price': int.parse(fields['price']!.text),
        'minimumStock': parseFixed(fields['minimumStock']!.text, 3),
        'tracking': tracking,
        'warrantyDays': parseFixed(fields['warrantyDays']!.text, 0),
        'components': parsePairs('components', (value) => parseFixed(value, 3)),
        'active': active,
        'tax': taxTreatment.isEmpty
            ? null
            : {
                'treatment': taxTreatment,
                if (taxTreatment == 'rate')
                  'rateBasisPoints': parseFixed(fields['taxRate']!.text, 2),
              },
        'units': parsePairs('units', (v) => parseFixed(v, 3)),
        'priceLists': parsePairs('priceLists', int.parse),
        'attributes': parsePairs('attributes', (v) => v),
        'quantityTiers': [
          for (final row
              in fields['quantityTiers']!.text
                  .split('\n')
                  .where((r) => r.trim().isNotEmpty))
            parseTier(row),
        ],
        for (final key in ['accessories', 'alternatives'])
          key: fields[key]!.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
      };
      for (final key in ['sku', 'name', 'unit']) {
        textField(data, key);
      }
      integerField(data, 'price', max: 1000000000000);
      ProductPolicy.validate(data);
      await widget.runtime.enqueue(
        Operation.catalog,
        old['id'] as String? ?? const Uuid().v4(),
        data,
        expectedVersion: widget.row?.version ?? 0,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is BusinessException
              ? e.message
              : e is FormatException
              ? e.message
              : 'Dữ liệu chưa hợp lệ.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, dynamic> parseTier(String row) {
    final values = row.split(';');
    if (values.length != 3) {
      throw const FormatException(
        'Mức giá: Tên bảng;Số lượng từ;Giá. Bỏ trống tên bảng cho giá chung.',
      );
    }
    return {
      'priceList': values[0].trim(),
      'minimum': parseFixed(values[1].trim(), 3),
      'price': int.parse(values[2].trim()),
    };
  }

  Widget field(
    String key,
    String label, {
    int lines = 1,
    String? help,
    bool enabled = true,
    Widget? suffixIcon,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: fields[key],
      enabled: !busy && enabled,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 8,
      decoration: InputDecoration(
        labelText: label,
        helperText: help,
        helperMaxLines: 3,
        suffixIcon: suffixIcon,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.row == null ? 'Thêm hàng hóa' : 'Sửa hàng hóa'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        field('sku', 'SKU', enabled: widget.row == null),
        field('name', 'Tên hàng'),
        field('unit', 'Đơn vị gốc', enabled: widget.row == null),
        field('price', 'Giá bán gốc (VND)'),
        field('group', 'Nhóm hàng (nhập tên mới để tạo)'),
        field(
          'barcode',
          'Mã vạch',
          suffixIcon: BarcodeScanButton(
            enabled: !busy,
            onScan: (code) => fields['barcode']!.text = code,
          ),
        ),
        field('brand', 'Thương hiệu'),
        field('model', 'Model'),
        field('variantOf', 'SKU sản phẩm gốc (nếu là biến thể)'),
        ValueListenableBuilder(
          valueListenable: fields['imageUrl']!,
          builder: (context, value, _) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ProductPhoto(value.text, size: 96),
                PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (selected) => fields['imageUrl']!.text = selected,
                  itemBuilder: (context) => [
                    for (final entry in sampleImages.entries)
                      PopupMenuItem(
                        value: entry.key,
                        child: Row(
                          children: [
                            ProductPhoto(entry.key, size: 28),
                            const SizedBox(width: 10),
                            Text(entry.value),
                          ],
                        ),
                      ),
                    const PopupMenuItem(value: '', child: Text('Bỏ ảnh')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Chọn ảnh minh họa ▾'),
                  ),
                ),
              ],
            ),
          ),
        ),
        field(
          'imageUrl',
          'Ảnh sản phẩm',
          help: 'Dán đường dẫn HTTPS hoặc chọn ảnh minh họa có sẵn.',
        ),
        field('minimumStock', 'Tồn tối thiểu theo đơn vị gốc'),
        field(
          'warrantyDays',
          'Thời hạn bảo hành (ngày)',
          help:
              'Nhập 0 nếu chưa quy định. Đơn bán giữ thời hạn tại lúc ghi sổ.',
        ),
        field(
          'components',
          'Thành phần cho một bộ',
          lines: 3,
          help: 'Mỗi dòng nhập Mã hàng=Số lượng gốc. Ví dụ ONG25=2. Để trống với hàng thường.',
        ),
        DropdownButtonFormField<String>(
          initialValue: tracking,
          decoration: const InputDecoration(labelText: 'Theo dõi tồn'),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Số lượng')),
            DropdownMenuItem(value: 'lot', child: Text('Lô / Mã màu')),
            DropdownMenuItem(value: 'serial', child: Text('Serial thiết bị')),
          ],
          onChanged: busy || widget.row != null
              ? null
              : (v) => setState(() => tracking = v!),
        ),
        SwitchListTile(
          title: const Text('Đang kinh doanh'),
          value: active,
          onChanged: busy ? null : (v) => setState(() => active = v),
        ),
        field(
          'units',
          'Đơn vị quy đổi',
          lines: 3,
          help: 'Mỗi dòng: Thùng=12 (1 thùng bằng 12 đơn vị gốc).',
        ),
        field(
          'priceLists',
          'Bảng giá theo nhóm khách',
          lines: 3,
          help: 'Mỗi dòng: Đại lý=150000. Giá cho một đơn vị gốc; chọn cùng tên bảng ở khách hàng.',
        ),
        field(
          'quantityTiers',
          'Giá theo số lượng',
          lines: 3,
          help: 'Mỗi dòng: Đại lý;10;140000 hoặc ;10;145000 cho bảng giá chung. Số lượng theo đơn vị gốc.',
        ),
        field(
          'attributes',
          'Thuộc tính theo nhóm',
          lines: 3,
          help: 'Mỗi dòng: Kích thước=60x60 hoặc Màu=Trắng.',
        ),
        DropdownButtonFormField<String>(
          initialValue: taxTreatment,
          decoration: const InputDecoration(
            labelText: 'Phân loại thuế để chuẩn bị tích hợp',
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('Chưa cấu hình')),
            DropdownMenuItem(
              value: 'rate',
              child: Text('Theo thuế suất cấu hình'),
            ),
            DropdownMenuItem(
              value: 'exempt',
              child: Text('Miễn thuế theo cấu hình'),
            ),
            DropdownMenuItem(
              value: 'outsideScope',
              child: Text('Ngoài phạm vi theo cấu hình'),
            ),
          ],
          onChanged: busy ? null : (v) => setState(() => taxTreatment = v!),
        ),
        if (taxTreatment == 'rate')
          field(
            'taxRate',
            'Thuế suất (%)',
            help: 'Nhập theo cấu hình đã được cửa hàng xác minh; phần mềm không tự chọn mức thuế.',
          ),
        field(
          'accessories',
          'SKU phụ kiện tương thích',
          help: 'Ngăn cách bằng dấu phẩy.',
        ),
        field(
          'alternatives',
          'SKU sản phẩm thay thế',
          help: 'Ngăn cách bằng dấu phẩy.',
        ),
        if (error.isNotEmpty)
          Text(error, style: const TextStyle(color: Colors.red)),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Lưu chờ xác nhận'),
        ),
      ],
    ),
  );
}
