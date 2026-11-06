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

      debugPrint('[VLXD] Da tiep nhan yeu cau hang hoa: ${data['sku']}');

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
  Widget build(BuildContext context) {
    // Khu vực chọn ảnh sản phẩm.
    final imagePanel = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E5F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hình ảnh sản phẩm',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF14243C),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder(
            valueListenable: fields['imageUrl']!,
            builder: (context, value, _) {
              return Column(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F7FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ProductPhoto(value.text, size: 180),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PopupMenuButton<String>(
                    enabled: !busy,
                    onSelected: (selected) {
                      fields['imageUrl']!.text = selected;
                    },
                    itemBuilder: (context) => [
                      for (final entry in sampleImages.entries)
                        PopupMenuItem(
                          value: entry.key,
                          child: Row(
                            children: [
                              ProductPhoto(entry.key, size: 28),
                              const SizedBox(width: 10),
                              Flexible(child: Text(entry.value)),
                            ],
                          ),
                        ),
                      const PopupMenuItem(value: '', child: Text('Bỏ ảnh')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Color(0xFF0059D6),
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Chọn ảnh minh họa',
                              style: TextStyle(
                                color: Color(0xFF0059D6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          field(
            'imageUrl',
            'Ảnh sản phẩm',
            help: 'Dán đường dẫn HTTPS hoặc chọn ảnh minh họa có sẵn.',
          ),
        ],
      ),
    );

    // Các trường thông tin chính.
    final mainFields = <Widget>[
      field('sku', 'SKU', enabled: widget.row == null),
      field('name', 'Tên hàng'),
      field('group', 'Nhóm hàng (nhập tên mới để tạo)'),
      field('unit', 'Đơn vị gốc', enabled: widget.row == null),
      field('price', 'Giá bán gốc (VND)'),
      field('model', 'Model / Quy cách'),
      field('brand', 'Thương hiệu'),
      field(
        'barcode',
        'Mã vạch',
        suffixIcon: BarcodeScanButton(
          enabled: !busy,
          onScan: (code) => fields['barcode']!.text = code,
        ),
      ),
      field('variantOf', 'SKU sản phẩm gốc (nếu là biến thể)'),
    ];

    // Các trường nâng cao, giữ nguyên logic hiện tại.
    final advancedFields = <Widget>[
      field('minimumStock', 'Tồn tối thiểu theo đơn vị gốc'),
      field(
        'warrantyDays',
        'Thời hạn bảo hành (ngày)',
        help: 'Nhập 0 nếu chưa quy định. Đơn bán giữ thời hạn tại lúc ghi sổ.',
      ),
      field(
        'components',
        'Thành phần cho một bộ',
        lines: 3,
        help: 'Mỗi dòng nhập Mã hàng=Số lượng gốc. Ví dụ ONG25=2.',
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
        help: 'Mỗi dòng: Đại lý=150000. Giá cho một đơn vị gốc.',
      ),
      field(
        'quantityTiers',
        'Giá theo số lượng',
        lines: 3,
        help: 'Mỗi dòng: Đại lý;10;140000 hoặc ;10;145000.',
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
          help: 'Nhập theo cấu hình đã được cửa hàng xác minh.',
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
    ];

    // Tự động chia trường nhập thành 1 hoặc 2 cột.
    Widget responsiveFields(List<Widget> items) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 600;
          final itemWidth = twoColumns
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final item in items) SizedBox(width: itemWidth, child: item),
            ],
          );
        },
      );
    }

    // Khung thông tin chính.
    final informationPanel = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E5F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin hàng hóa',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF14243C),
            ),
          ),
          const SizedBox(height: 20),
          responsiveFields(mainFields),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.row == null ? 'Thêm hàng hóa' : 'Sửa hàng hóa'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 290, child: imagePanel),
                          const SizedBox(width: 20),
                          Expanded(child: informationPanel),
                        ],
                      )
                    else ...[
                      imagePanel,
                      const SizedBox(height: 20),
                      informationPanel,
                    ],
                    const SizedBox(height: 20),

                    // Thông tin nâng cao.
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD8E5F7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thiết lập nâng cao',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF14243C),
                            ),
                          ),
                          const SizedBox(height: 20),
                          responsiveFields(advancedFields),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: busy ? null : save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Lưu chờ xác nhận'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
