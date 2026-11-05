import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/app_runtime.dart';
import '../data/database.dart';
import '../data/stock_tracking.dart';
import '../domain/operations.dart';
import '../domain/product_policy.dart';
import 'material_calculator.dart';
import 'business_receipt.dart';
import 'shift_close.dart';
import 'delivery_map.dart';
import 'invoice_preparation.dart';
import 'record_table.dart';
import 'catalog_art.dart';
import 'barcode_scan.dart';
import 'debt_ledger.dart';

String vnd(int value) => '${NumberFormat.decimalPattern('vi').format(value)} đ';
String qty(int value) => NumberFormat('0.###', 'vi').format(value / 1000);
String shortId(String value, [int length = 8]) =>
    value.length <= length ? value : value.substring(0, length);
List<String> parseSerials(String text) => text
    .split(RegExp(r'[,;\n]'))
    .map((s) => s.trim().toUpperCase())
    .where((s) => s.isNotEmpty)
    .toList();
const lotEntryHelp = 'Một lô: A • Nhiều lô: A:2; B:3 (đơn vị gốc)';

Map<String, dynamic> lotFields(String input, int quantity, {String? color}) {
  final text = input.trim();
  if (text.isEmpty) return {};
  if (!text.contains(';') && !text.contains(':')) {
    return {
      'lotId': text,
      if (color != null && color.isNotEmpty) 'colorCode': color,
    };
  }
  final allocations = <Map<String, dynamic>>[];
  for (final entry in text.split(';')) {
    final parts = entry.split(':').map((p) => p.trim()).toList();
    if (parts.length < 2 || parts.length > (color == null ? 2 : 3)) {
      throw FormatException(
        color == null
            ? lotEntryHelp
            : 'Nhập A:2:MÀU1; B:3:MÀU2 (mã màu có thể bỏ trống).',
      );
    }
    allocations.add({
      'lotId': parts[0],
      'quantity': parseFixed(parts[1], 3),
      if (parts.length == 3 && parts[2].isNotEmpty)
        'colorCode': parts[2]
      else if (color != null && color.isNotEmpty)
        'colorCode': color,
    });
  }
  return {
    'lotAllocations': StockTracking.lots({
      'lotAllocations': allocations,
    }, quantity),
  };
}

int coordinate(String text, int limit) {
  final raw = text.trim();
  final value =
      parseFixed(raw.startsWith('-') ? raw.substring(1) : raw, 6) *
      (raw.startsWith('-') ? -1 : 1);
  if (value < -limit || value > limit) {
    throw const FormatException('Tọa độ vượt giới hạn.');
  }
  return value;
}

Map<String, dynamic> recordData(BusinessRecord row) =>
    jsonDecode(row.payload) as Map<String, dynamic>;
bool allowed(AppRuntime runtime, Operation op) {
  try {
    runtime.actor?.require(op);
    return runtime.actor != null;
  } catch (_) {
    return false;
  }
}

void feedback(BuildContext context, String text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class RecordList extends StatefulWidget {
  final AppRuntime runtime;
  final String kind, title;
  final String? onlyId;
  final List<Widget> actions;
  final Widget Function(BuildContext, BusinessRecord, Map<String, dynamic>)
  item;
  const RecordList({
    super.key,
    required this.runtime,
    required this.kind,
    required this.title,
    required this.item,
    this.actions = const [],
    this.onlyId,
  });
  @override
  State<RecordList> createState() => _RecordListState();
}

class _RecordListState extends State<RecordList> {
  int page = 0;
  String search = '';
  Timer? searchTimer;
  late Stream<List<BusinessRecord>> stream;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(RecordList old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind ||
        old.runtime != widget.runtime ||
        old.onlyId != widget.onlyId) {
      page = 0;
      refresh();
    }
  }

  void refresh() {
    stream = widget.runtime.records(
      widget.kind,
      offset: page * 100,
      limit: 101,
      search: search,
      recordId: widget.onlyId,
    );
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    super.dispose();
  }

  void move(int next) {
    setState(() {
      page = next;
      refresh();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.title.isNotEmpty)
            Text(
              widget.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ...widget.actions,
        ],
      ),
      const SizedBox(height: 16),
      if (widget.onlyId == null) ...[
        SizedBox(
          width: 420,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm mã, tên, điện thoại hoặc chứng từ…',
            ),
            onChanged: (value) {
              searchTimer?.cancel();
              searchTimer = Timer(const Duration(milliseconds: 180), () {
                if (mounted) {
                  setState(() {
                    search = value.trim();
                    page = 0;
                    refresh();
                  });
                }
              });
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
      Expanded(
        child: StreamBuilder(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Không đọc được dữ liệu.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!;
            if (rows.isEmpty && page == 0) {
              return const Center(
                child: Text(
                  'Chưa có chứng từ đã xác nhận. Dữ liệu đang chờ ở mục Đồng bộ.',
                ),
              );
            }
            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, size) => size.maxWidth >= 850
                        ? RecordTable(
                            runtime: widget.runtime,
                            kind: widget.kind,
                            rows: rows.take(100).toList(),
                            details: widget.item,
                          )
                        : ListView.builder(
                            itemCount: rows.length > 100 ? 100 : rows.length,
                            itemBuilder: (context, index) => widget.item(
                              context,
                              rows[index],
                              recordData(rows[index]),
                            ),
                          ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Trang ${page + 1}'),
                    IconButton(
                      tooltip: 'Trang trước',
                      onPressed: page == 0 ? null : () => move(page - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Trang sau',
                      onPressed: rows.length > 100
                          ? () => move(page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class InputField {
  final String key, label, initial;
  final String? help;
  final bool number, optional;
  final int scale;
  final List<(String, String)>? choices;
  const InputField(
    this.key,
    this.label, {
    this.initial = '',
    this.help,
    this.number = false,
    this.optional = false,
    this.choices,
    this.scale = 0,
  });
}

Future<void> commandDialog(
  BuildContext context,
  AppRuntime runtime, {
  required String title,
  required Operation operation,
  required String entityId,
  required List<InputField> fields,
  Map<String, dynamic> fixed = const {},
  int version = 0,
  int? balance,
  Map<String, dynamic> Function(Map<String, dynamic>)? transform,
}) async {
  final controllers = {
    for (final f in fields) f.key: TextEditingController(text: f.initial),
  };
  final values = {
    for (final f in fields)
      if (f.choices != null)
        f.key: f.initial.isEmpty ? f.choices!.first.$1 : f.initial,
  };
  final key = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: field.choices != null
                          ? DropdownButtonFormField<String>(
                              initialValue: values[field.key],
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: field.label,
                              ),
                              items: [
                                for (final option in field.choices!)
                                  DropdownMenuItem(
                                    value: option.$1,
                                    child: Text(option.$2),
                                  ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) => values[field.key] = v!,
                            )
                          : TextFormField(
                              controller: controllers[field.key],
                              onChanged: (_) => update(() {}),
                              enabled: !busy,
                              keyboardType: field.number
                                  ? TextInputType.number
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                labelText: field.label,
                                helperText: field.help,
                                helperMaxLines: 3,
                              ),
                              validator: (v) {
                                if (field.optional && (v ?? '').isEmpty) {
                                  return null;
                                }
                                if ((v ?? '').trim().isEmpty) {
                                  return 'Vui lòng nhập thông tin';
                                }
                                if (field.number) {
                                  try {
                                    parseFixed(v!, field.scale);
                                  } catch (_) {
                                    return field.scale == 0
                                        ? 'Nhập số nguyên không âm'
                                        : 'Nhập số lượng hợp lệ, tối đa ${field.scale} chữ số thập phân';
                                  }
                                }
                                return null;
                              },
                            ),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (balance != null)
                    Builder(
                      builder: (_) {
                        final amount = int.tryParse(
                          controllers['amount']?.text ?? '',
                        );
                        return Text(
                          amount == null
                              ? 'Số dư hiện tại: ${vnd(balance)}'
                              : 'Còn lại sau phiếu này: ${vnd(balance - amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: amount != null && amount > balance
                                ? Colors.red
                                : Colors.blue,
                          ),
                        );
                      },
                    ),
                  const Text(
                    'Chứng từ được lưu chờ; chỉ ghi sổ khi trạm xác nhận hợp lệ.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!key.currentState!.validate()) return;
                    update(() => busy = true);
                    try {
                      final payload = {
                        ...fixed,
                        for (final field in fields)
                          field.key: field.choices != null
                              ? values[field.key]
                              : field.number
                              ? parseFixed(
                                  controllers[field.key]!.text,
                                  field.scale,
                                )
                              : controllers[field.key]!.text.trim(),
                      };
                      await runtime.enqueue(
                        operation,
                        entityId,
                        transform == null ? payload : transform(payload),
                        expectedVersion: version,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      update(() {
                        busy = false;
                        error = e is BusinessException
                            ? e.message
                            : e is FormatException
                            ? e.message
                            : 'Không lưu được chứng từ.';
                      });
                    }
                  },
            child: const Text('Lưu chờ xác nhận'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in controllers.values) {
    c.dispose();
  }
}

const methods = [('cash', 'Tiền mặt'), ('bank', 'Chuyển khoản')];
String currentShift(AppRuntime runtime) =>
    '${DateFormat('yyyy-MM-dd').format(DateTime.now())}-${runtime.actor!.uid}';

class PartiesPage extends StatelessWidget {
  final AppRuntime runtime;
  const PartiesPage({super.key, required this.runtime});
  Future<void> edit(
    BuildContext context, {
    BusinessRecord? row,
    Map<String, dynamic> data = const {},
  }) => commandDialog(
    context,
    runtime,
    title: row == null ? 'Thêm đối tác' : 'Sửa đối tác',
    operation: Operation.party,
    entityId: row == null ? const Uuid().v4() : data['id'] as String,
    version: row?.version ?? 0,
    fields: [
      InputField('name', 'Tên đối tác', initial: data['name'] as String? ?? ''),
      InputField(
        'type',
        'Loại đối tác',
        initial: data['type'] as String? ?? 'customer',
        choices: runtime.actor?.role == StaffRole.sales
            ? [('customer', 'Khách hàng')]
            : [
                ('customer', 'Khách hàng'),
                ('supplier', 'Nhà cung cấp'),
                ('both', 'Khách hàng và NCC'),
              ],
      ),
      InputField(
        'phone',
        'Số điện thoại',
        initial: data['phone'] as String? ?? '',
        optional: true,
      ),
      InputField(
        'address',
        'Địa chỉ',
        initial: data['address'] as String? ?? '',
        optional: true,
      ),
      InputField(
        'priceList',
        'Tên bảng giá áp dụng',
        initial: data['priceList'] as String? ?? '',
        optional: true,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'party',
    title: 'Khách hàng / Nhà cung cấp',
    actions: [
      if (allowed(runtime, Operation.party))
        FilledButton.icon(
          onPressed: () => edit(context),
          icon: const Icon(Icons.add),
          label: const Text('Thêm đối tác'),
        ),
    ],
    item: (context, row, data) => Card(
      child: ListTile(
        title: Text(data['name'] as String),
        subtitle: Text('${data['phone'] ?? ''} • ${data['address'] ?? ''}'),
        trailing: allowed(runtime, Operation.party)
            ? IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => edit(context, row: row, data: data),
              )
            : null,
      ),
    ),
  );
}

class OrderComposer extends StatefulWidget {
  final AppRuntime runtime;
  final bool purchase;
  final bool quote;
  final Draft? draft;
  const OrderComposer({
    super.key,
    required this.runtime,
    this.purchase = false,
    this.quote = false,
    this.draft,
  });
  @override
  State<OrderComposer> createState() => _OrderComposerState();
}

class _OrderComposerState extends State<OrderComposer> {
  late final AppDatabase database;
  late final String id, owner;
  late String entityId;
  int expectedVersion = 0;
  Timer? autosave;
  Future<void> pendingSave = Future.value();
  bool submitted = false;
  bool reserveOrder = false, allowMixedLotColors = false;
  final quantities = <String, TextEditingController>{},
      costs = <String, TextEditingController>{};
  final warehouse = TextEditingController(text: 'main'),
      discount = TextEditingController(text: '0');
  final surcharge = TextEditingController(text: '0'),
      dueDate = TextEditingController();
  final searchInput = TextEditingController();
  List<Product> products = [];
  List<BusinessRecord> parties = [];
  final missingItems = <Map<String, dynamic>>[];
  final trackingModes = <String, String>{};
  final trackingInputs = <String, TextEditingController>{};
  final catalog = <String, Map<String, dynamic>>{};
  final selectedUnits = <String, String>{};
  final physicalStock = <String, int>{}, heldStock = <String, int>{};
  final lotPositions = <String, List<Map<String, dynamic>>>{};
  final lotColors = <String, String>{};
  StreamSubscription<List<BusinessRecord>>? stockSubscription;
  void stockChanged(List<BusinessRecord> rows) {
    physicalStock.clear();
    heldStock.clear();
    lotPositions.clear();
    lotColors.clear();
    for (final row in rows) {
      final data = recordData(row);
      final key = jsonEncode([data['warehouse'], data['productId']]);
      if (row.kind == 'stock' && data['quality'] == 'good') {
        physicalStock[key] = data['quantity'] as int;
      }
      if (row.kind == 'reservedStock') heldStock[key] = data['quantity'] as int;
      if (row.kind == 'lotStock' &&
          data['quality'] == 'good' &&
          (data['quantity'] as int) > 0) {
        (lotPositions[key] ??= []).add(data);
      }
      if (row.kind == 'lot') {
        lotColors[jsonEncode([data['productId'], data['lotId']])] =
            data['colorCode'] as String? ?? '';
      }
    }
    if (mounted && !loading) setState(() {});
  }

  String? party;
  String search = '', message = '';
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    database = widget.runtime.db;
    id = widget.draft?.id ?? const Uuid().v4();
    owner = widget.runtime.actor!.uid;
    entityId = id;
    warehouse.addListener(changed);
    discount.addListener(changed);
    surcharge.addListener(changed);
    dueDate.addListener(changed);
    load();
  }

  Future<void> load() async {
    try {
      final db = database;
      final stockQuery = db.select(db.businessRecords)
        ..where(
          (r) => r.kind.isIn(['stock', 'reservedStock', 'lotStock', 'lot']),
        );
      stockChanged(await stockQuery.get());
      stockSubscription = stockQuery.watch().listen(stockChanged);
      products = await db.select(db.products).get();
      for (final row in await (db.select(
        db.businessRecords,
      )..where((r) => r.kind.equals('catalog'))).get()) {
        final data = recordData(row);
        catalog[data['id'] as String] = data;
        trackingModes[data['id'] as String] =
            data['tracking'] as String? ?? 'none';
      }
      parties = await (db.select(
        db.businessRecords,
      )..where((r) => r.kind.equals('party'))).get();
      if (widget.draft != null) {
        final data = jsonDecode(widget.draft!.payload) as Map<String, dynamic>;
        entityId = data['targetId'] as String? ?? id;
        expectedVersion = data['expectedVersion'] as int? ?? 0;
        warehouse.text = data['warehouse'] as String;
        discount.text = data['discount'] as String;
        surcharge.text = data['surcharge'] as String? ?? '0';
        dueDate.text = data['dueDate'] as String? ?? '';
        party = data['party'] as String?;
        reserveOrder = data['reserveOrder'] as bool? ?? false;
        allowMixedLotColors = data['allowMixedLotColors'] == true;
        for (final item in data['items'] as List) {
          final key = item['productId'] as String;
          if (!products.any((p) => p.id == key)) {
            missingItems.add(Map<String, dynamic>.from(item as Map));
            message =
                'Có hàng hóa chưa có trong cache. Đồng bộ lại để mở đủ đơn.';
            continue;
          }
          quantities[key] = TextEditingController(
            text: item['quantity'] as String,
          )..addListener(changed);
          costs[key] = TextEditingController(text: item['cost'] as String)
            ..addListener(changed);
          trackingInputs[key] = TextEditingController(
            text: item['trackingInput'] as String? ?? '',
          )..addListener(changed);
          selectedUnits[key] =
              item['saleUnit'] as String? ??
              products.firstWhere((p) => p.id == key).unit;
        }
      }
      if (mounted) setState(() => loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          message = 'Không đọc được danh mục.';
        });
      }
    }
  }

  @override
  void dispose() {
    autosave?.cancel();
    unawaited(stockSubscription?.cancel());
    if (!submitted && !loading) unawaited(saveDraft());
    for (final c in [
      ...quantities.values,
      ...costs.values,
      ...trackingInputs.values,
      warehouse,
      discount,
      surcharge,
      dueDate,
      searchInput,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> snapshot() => {
    'kind': widget.purchase
        ? 'purchase'
        : widget.quote
        ? 'quote'
        : 'sale',
    'targetId': entityId,
    'expectedVersion': expectedVersion,
    'warehouse': warehouse.text,
    'discount': discount.text,
    'surcharge': surcharge.text,
    'dueDate': dueDate.text,
    'party': party,
    'reserveOrder': reserveOrder,
    'allowMixedLotColors': allowMixedLotColors,
    'items': [
      ...missingItems,
      for (final entry in quantities.entries)
        {
          'productId': entry.key,
          'quantity': entry.value.text,
          'cost': costs[entry.key]!.text,
          'trackingInput': trackingInputs[entry.key]?.text ?? '',
          'saleUnit': selectedUnits[entry.key],
        },
    ],
  };
  void changed() {
    if (loading || submitted || !mounted) return;
    setState(() {});
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 500), () => saveDraft());
  }

  Future<void> saveDraft() {
    final data = snapshot();
    pendingSave = pendingSave
        .catchError((Object _) {})
        .then((_) => database.saveDraft(id, data));
    return pendingSave.catchError((Object _) {
      if (mounted) {
        setState(() => message = 'Chưa lưu được nháp. Vui lòng thử lại.');
      }
    });
  }

  int baseQuantity(String id) {
    final product = products.firstWhere((p) => p.id == id);
    final raw = parseFixed(quantities[id]!.text, 3);
    return widget.purchase
        ? raw
        : ProductPolicy.baseQuantity(
            catalog[id] ?? {},
            product.unit,
            selectedUnits[id] ?? product.unit,
            raw,
          );
  }

  int priceFor(String id) {
    final product = products.firstWhere((p) => p.id == id);
    final customer = parties
        .where((r) => recordData(r)['id'] == party)
        .firstOrNull;
    return ProductPolicy.price(
      catalog[id] ?? {},
      product.price,
      customer == null
          ? ''
          : recordData(customer)['priceList'] as String? ?? '',
      baseQuantity(id),
    );
  }

  int? get total {
    try {
      var value = 0;
      for (final entry in quantities.entries) {
        final q = baseQuantity(entry.key);
        if (q <= 0) throw const FormatException();
        final price = widget.purchase
            ? int.parse(costs[entry.key]!.text)
            : priceFor(entry.key);
        if (price < 0) throw const FormatException();
        value += roundedRatio(price, q, 1000);
      }
      final d = widget.purchase ? 0 : int.parse(discount.text);
      if (d < 0 || d > value) throw const FormatException();
      final extra = widget.purchase ? 0 : int.parse(surcharge.text);
      if (extra < 0 || extra > 1000000000000) throw const FormatException();
      return value - d + extra;
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    if (missingItems.isNotEmpty ||
        party == null ||
        quantities.isEmpty ||
        total == null ||
        warehouse.text.trim().isEmpty) {
      setState(
        () => message = missingItems.isNotEmpty
            ? 'Đơn còn hàng chưa có trong cache. Hãy quay lại và đồng bộ trước khi gửi; nháp được giữ nguyên.'
            : 'Chọn đối tác, kho và ít nhất một dòng hàng hợp lệ.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (widget.runtime.actor?.uid != owner) {
        throw const BusinessException(
          'permission',
          'Phiên đăng nhập đã thay đổi.',
        );
      }
      autosave?.cancel();
      await pendingSave;
      final lines = [
        for (final entry in quantities.entries)
          {
            'productId': entry.key,
            'quantity': baseQuantity(entry.key),
            if (!widget.purchase) 'saleUnit': selectedUnits[entry.key],
            if (!widget.purchase)
              'saleQuantity': parseFixed(entry.value.text, 3),
            if (!widget.purchase && trackingModes[entry.key] == 'lot')
              ...lotFields(
                trackingInputs[entry.key]!.text,
                baseQuantity(entry.key),
              ),
            if (trackingModes[entry.key] == 'serial')
              'serials': parseSerials(trackingInputs[entry.key]!.text),
            if (!widget.purchase) 'expectedPrice': priceFor(entry.key),
            if (widget.purchase) 'unitCost': int.parse(costs[entry.key]!.text),
          },
      ];
      await database.transaction(() async {
        await widget.runtime.enqueue(
          widget.purchase
              ? Operation.purchase
              : widget.quote
              ? Operation.quote
              : reserveOrder
              ? Operation.reservation
              : Operation.sale,
          entityId,
          {
            'warehouse': warehouse.text.trim(),
            widget.purchase ? 'supplierId' : 'customerId': party,
            'lines': lines,
            if (!widget.purchase) 'discount': int.parse(discount.text),
            if (!widget.purchase) 'surcharge': int.parse(surcharge.text),
            if (!widget.purchase && allowMixedLotColors)
              'allowMixedLotColors': true,
            widget.purchase ? 'expectedAt' : 'dueAt': dueDate.text.trim(),
          },
          syncNow: false,
          expectedVersion: expectedVersion,
        );
        await database.saveDraft(
          id,
          snapshot(),
          submit: true,
          createOutbox: false,
        );
      });
      submitted = true;
      unawaited(widget.runtime.tick());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is BusinessException
              ? e.message
              : e is FormatException
              ? e.message
              : 'Không lưu được đơn.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = parties.where((r) {
      final p = recordData(r);
      return p['type'] == 'both' ||
          p['type'] == (widget.purchase ? 'supplier' : 'customer');
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.purchase
              ? 'Tạo đơn mua'
              : widget.quote
              ? 'Tạo / sửa báo giá'
              : 'Tạo đơn bán',
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: party,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: widget.purchase ? 'Nhà cung cấp' : 'Khách hàng',
                  ),
                  items: [
                    for (final p in options)
                      DropdownMenuItem(
                        value: recordData(p)['id'] as String,
                        child: Text(recordData(p)['name'] as String),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          party = v;
                          changed();
                        },
                ),
                if (options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Thêm và đồng bộ đối tác trước khi lập đơn.'),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: warehouse,
                  decoration: const InputDecoration(labelText: 'Kho'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dueDate,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: widget.purchase
                        ? 'Ngày hẹn nhận (năm-tháng-ngày, nếu có)'
                        : 'Hạn công nợ (năm-tháng-ngày, nếu có)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchInput,
                  decoration: InputDecoration(
                    labelText: 'Tìm theo tên, mã hàng hoặc mã vạch',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: BarcodeScanButton(
                      enabled: !busy,
                      onScan: (code) {
                        searchInput.text = code;
                        setState(() => search = code.toLowerCase());
                      },
                    ),
                  ),
                  onChanged: (v) =>
                      setState(() => search = v.trim().toLowerCase()),
                ),
                if (search.isNotEmpty)
                  ...products
                      .where(
                        (p) =>
                            '${p.sku} ${p.name} ${catalog[p.id]?['barcode'] ?? ''} ${catalog[p.id]?['model'] ?? ''}'
                                .toLowerCase()
                                .contains(search) &&
                            !quantities.containsKey(p.id),
                      )
                      .take(8)
                      .map(
                        (p) => ListTile(
                          leading: ProductPhoto(
                            catalog[p.id]?['imageUrl'],
                            size: 36,
                          ),
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.sku} • ${vnd(p.price)} / ${p.unit}',
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: busy
                              ? null
                              : () => setState(() {
                                  quantities[p.id] = TextEditingController(
                                    text: '1',
                                  )..addListener(changed);
                                  costs[p.id] = TextEditingController(text: '0')
                                    ..addListener(changed);
                                  trackingInputs[p.id] = TextEditingController()
                                    ..addListener(changed);
                                  selectedUnits[p.id] = p.unit;
                                  changed();
                                }),
                        ),
                      ),
                const SizedBox(height: 12),
                for (final id in quantities.keys)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            products.firstWhere((p) => p.id == id).name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          if (!widget.purchase)
                            DropdownButtonFormField<String>(
                              initialValue:
                                  selectedUnits[id] ??
                                  products.firstWhere((p) => p.id == id).unit,
                              decoration: const InputDecoration(
                                labelText: 'Đơn vị bán',
                              ),
                              items: [
                                for (final unit in {
                                  products.firstWhere((p) => p.id == id).unit,
                                  ...(catalog[id]?['units'] as Map? ?? {}).keys
                                      .cast<String>(),
                                  ?selectedUnits[id],
                                })
                                  DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (v) {
                                      selectedUnits[id] = v!;
                                      changed();
                                    },
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: quantities[id],
                                  enabled: !busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText:
                                        'Số lượng (${widget.purchase ? products.firstWhere((p) => p.id == id).unit : selectedUnits[id]})',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              if (widget.purchase) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: costs[id],
                                    enabled: !busy,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Đơn giá nhập (VND)',
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                              IconButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        quantities.remove(id)?.dispose();
                                        costs.remove(id)?.dispose();
                                        trackingInputs.remove(id)?.dispose();
                                        changed();
                                      }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          if (!widget.purchase)
                            Builder(
                              builder: (context) {
                                try {
                                  final q = baseQuantity(id),
                                      price = priceFor(id);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      'Quy đổi: ${qty(q)} ${products.firstWhere((p) => p.id == id).unit} • Giá gốc áp dụng: ${vnd(price)} • Thành tiền: ${vnd(roundedRatio(price, q, 1000))}',
                                    ),
                                  );
                                } catch (_) {
                                  return const Text(
                                    'Số lượng hoặc quy đổi chưa hợp lệ.',
                                  );
                                }
                              },
                            ),
                          Builder(
                            builder: (context) {
                              final key = jsonEncode([
                                    warehouse.text.trim(),
                                    id,
                                  ]),
                                  physical =
                                      physicalStock[jsonEncode([
                                        warehouse.text.trim(),
                                        id,
                                      ])] ??
                                      0,
                                  held =
                                      heldStock[jsonEncode([
                                        warehouse.text.trim(),
                                        id,
                                      ])] ??
                                      0;
                              return Text(
                                'Tồn thực tế: ${qty(physical)} • Giữ chỗ: ${qty(heldStock[key] ?? 0)} • Khả dụng: ${qty(physical - held)} ${products.firstWhere((p) => p.id == id).unit}',
                                style: TextStyle(
                                  color: physical - held <= 0
                                      ? Colors.orange.shade900
                                      : Colors.green.shade800,
                                ),
                              );
                            },
                          ),
                          if (!widget.purchase && trackingModes[id] == 'lot')
                            Builder(
                              builder: (context) {
                                final lots =
                                    lotPositions[jsonEncode([
                                      warehouse.text.trim(),
                                      id,
                                    ])] ??
                                    [];
                                if (lots.isEmpty) {
                                  return const Text(
                                    'Chưa có tồn lô hàng tốt đã đồng bộ.',
                                  );
                                }
                                final preview = lots
                                    .take(5)
                                    .map((lot) {
                                      final label = lot['lotId'];
                                      final color =
                                          lotColors[jsonEncode([id, label])] ??
                                          '';
                                      return '$label${color.isEmpty ? '' : ' ($color)'}: ${qty(lot['quantity'] as int)}';
                                    })
                                    .join(' • ');
                                return Text(
                                  'Tồn lô: $preview${lots.length > 5 ? ' • +${lots.length - 5} lô' : ''}',
                                );
                              },
                            ),
                          if (!widget.purchase &&
                              {'lot', 'serial'}.contains(trackingModes[id]))
                            TextField(
                              controller: trackingInputs[id],
                              enabled: !busy,
                              decoration: InputDecoration(
                                labelText: trackingModes[id] == 'lot'
                                    ? 'Mã lô xuất'
                                    : 'Serial xuất (ngăn cách bằng dấu phẩy)',
                                helperText: trackingModes[id] == 'lot'
                                    ? lotEntryHelp
                                    : null,
                                helperMaxLines: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (!widget.purchase) ...[
                  if (quantities.keys.any(
                    (id) =>
                        trackingModes[id] == 'lot' &&
                        trackingInputs[id]!.text.contains(';'),
                  ))
                    CheckboxListTile(
                      title: const Text('Khách đồng ý dùng lô khác mã màu'),
                      subtitle: const Text(
                        'Kiểm tra mã màu trước khi trộn các lô gạch.',
                      ),
                      value: allowMixedLotColors,
                      onChanged: busy
                          ? null
                          : (v) {
                              allowMixedLotColors = v ?? false;
                              changed();
                            },
                    ),
                  if (!widget.quote)
                    SwitchListTile(
                      title: const Text('Giữ hàng / Xin duyệt đơn vượt tồn'),
                      subtitle: const Text(
                        'Không xuất âm kho. Đơn thiếu hàng chờ quản lý quyết định.',
                      ),
                      value: reserveOrder,
                      onChanged: busy
                          ? null
                          : (v) {
                              reserveOrder = v;
                              changed();
                            },
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: discount,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Chiết khấu (VND)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: surcharge,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Phí giao / Bốc xếp / Phụ thu (VND)',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: busy ? null : saveDraft,
                  child: const Text('Lưu nháp trên thiết bị'),
                ),
                Text(
                  total == null
                      ? 'Số lượng hoặc tiền chưa hợp lệ'
                      : 'Tổng tiền: ${vnd(total!)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (message.isNotEmpty)
                  Text(message, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: const Text('Lưu chờ xác nhận'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Đơn mua chưa cộng tồn. Đơn bán chưa xuất hàng cho đến khi trạm xác nhận; thu tiền ở chứng từ đã ghi sổ.',
                ),
              ],
            ),
    );
  }
}

Future<void> lineAction(
  BuildContext context,
  AppRuntime runtime,
  BusinessRecord row,
  Map<String, dynamic> data,
  Operation op,
  String title,
) async {
  final lines = (data['lines'] as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  final controllers = [for (final _ in lines) TextEditingController(text: '0')];
  final lotInputs = [for (final _ in lines) TextEditingController()];
  final serialInputs = [for (final _ in lines) TextEditingController()];
  final colors = [for (final _ in lines) TextEditingController()];
  final extra = TextEditingController();
  final purchaseCosts = TextEditingController(text: '0');
  String quality = 'good', error = '';
  bool busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        TextField(
                          controller: controllers[i],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                lines[i]['name'] as String? ?? 'Hàng ${i + 1}',
                            helperText:
                                'Đặt/bán: ${qty(lines[i]['quantity'] as int)} • Đã xử lý: ${qty((lines[i][op == Operation.receive
                                        ? 'received'
                                        : op == Operation.delivery
                                        ? 'delivered'
                                        : 'returned'] as int?) ?? 0)}',
                          ),
                        ),
                        if (op == Operation.receive ||
                            (op == Operation.returnSale &&
                                lines[i]['lotAllocations'] is List &&
                                (lines[i]['lotAllocations'] as List).length >
                                    1))
                          TextField(
                            controller: lotInputs[i],
                            decoration: InputDecoration(
                              labelText: op == Operation.returnSale
                                  ? 'Lô thực trả'
                                  : 'Lô nhận (nếu theo dõi)',
                              helperText: op == Operation.receive
                                  ? 'Một lô: A • Nhiều lô: A:2:MÀU1; B:3:MÀU2'
                                  : 'Còn được trả: ${(lines[i]['lotAllocations'] as List).map((lot) {
                                      final returned = (lines[i]['returnedByLot'] as List? ?? []).where((item) => item['lotId'] == lot['lotId']).firstOrNull;
                                      final previous = returned?['quantity'] as int? ?? 0;
                                      return "${lot['lotId']}: ${qty((lot['quantity'] as int) - previous)}";
                                    }).join('; ')}. $lotEntryHelp',
                              helperMaxLines: 5,
                            ),
                          ),
                        if (op == Operation.receive) ...[
                          TextField(
                            controller: colors[i],
                            decoration: const InputDecoration(
                              labelText: 'Mã màu lô gạch (nếu có)',
                            ),
                          ),
                        ],
                        if (op == Operation.receive ||
                            op == Operation.returnSale)
                          TextField(
                            controller: serialInputs[i],
                            decoration: const InputDecoration(
                              labelText: 'Serial (nếu theo dõi serial), ngăn cách bằng dấu phẩy',
                            ),
                          ),
                      ],
                    ),
                  ),
                if (op == Operation.receive)
                  DropdownButtonFormField<String>(
                    initialValue: quality,
                    decoration: const InputDecoration(
                      labelText: 'Chất lượng hàng nhận',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'good', child: Text('Hàng tốt')),
                      DropdownMenuItem(
                        value: 'quarantine',
                        child: Text('Cách ly'),
                      ),
                      DropdownMenuItem(
                        value: 'damaged',
                        child: Text('Hàng hỏng'),
                      ),
                    ],
                    onChanged: (v) => quality = v!,
                  ),
                if (op == Operation.returnSale)
                  TextField(
                    controller: extra,
                    decoration: const InputDecoration(
                      labelText: 'Lý do trả hàng',
                    ),
                  ),
                if (op == Operation.receive)
                  TextField(
                    controller: purchaseCosts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Phí mua NCC tính thêm vào đợt nhận (VND)',
                    ),
                  ),
                if (error.isNotEmpty)
                  Text(error, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                const Text(
                  'Nhập 0 cho dòng chưa xử lý; hàng trả luôn vào cách ly.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    try {
                      final selected = <Map<String, dynamic>>[];
                      for (var i = 0; i < lines.length; i++) {
                        final q = parseFixed(controllers[i].text, 3);
                        if (q > 0) {
                          if (op == Operation.returnSale &&
                              lines[i]['lotAllocations'] is List &&
                              (lines[i]['lotAllocations'] as List).length > 1 &&
                              lotInputs[i].text.trim().isEmpty) {
                            throw const FormatException(
                              'Nhập mã lô thực trả cho dòng đã xuất nhiều lô.',
                            );
                          }
                          selected.add({
                            'productId': lines[i]['productId'],
                            'quantity': q,
                            if (op == Operation.receive) 'quality': quality,
                            if (op == Operation.receive ||
                                op == Operation.returnSale)
                              ...lotFields(
                                lotInputs[i].text,
                                q,
                                color: op == Operation.receive
                                    ? colors[i].text.trim()
                                    : null,
                              ),
                            if (op == Operation.receive ||
                                op == Operation.returnSale)
                              'serials': parseSerials(serialInputs[i].text),
                          });
                        }
                      }
                      if (selected.isEmpty) {
                        throw const FormatException(
                          'Chọn số lượng ít nhất một dòng.',
                        );
                      }
                      if (op == Operation.returnSale &&
                          extra.text.trim().isEmpty) {
                        throw const FormatException('Nhập lý do trả hàng.');
                      }
                      update(() => busy = true);
                      await runtime.enqueue(
                        op,
                        data['id'] as String,
                        {
                          'lines': selected,
                          if (op == Operation.receive)
                            'purchaseCosts': int.parse(purchaseCosts.text),
                          if (op == Operation.delivery) ...{
                            'driverId': data['driverId'],
                            'vehicleId': data['vehicleId'],
                          },
                          if (op == Operation.returnSale)
                            'reason': extra.text.trim(),
                        },
                        expectedVersion:
                            data['saleVersion'] as int? ?? row.version,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      update(() {
                        busy = false;
                        error = e is FormatException
                            ? e.message
                            : e is BusinessException
                            ? e.message
                            : 'Không lưu được chứng từ.';
                      });
                    }
                  },
            child: const Text('Lưu chờ'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in [
    ...controllers,
    ...lotInputs,
    ...serialInputs,
    ...colors,
    extra,
    purchaseCosts,
  ]) {
    c.dispose();
  }
}

class TradingPage extends StatelessWidget {
  final AppRuntime runtime;
  final bool purchase;
  final String? onlyId;
  const TradingPage({
    super.key,
    required this.runtime,
    this.purchase = false,
    this.onlyId,
  });
  Future<void> assign(
    BuildContext context,
    BusinessRecord row,
    Map<String, dynamic> data,
  ) async {
    try {
      final drivers = await runtime.firestore.query(
        'stores/${runtime.config.storeId}',
        {
          'from': [
            {'collectionId': 'members'},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': 'role'},
              'op': 'EQUAL',
              'value': {'stringValue': 'driver'},
            },
          },
          'limit': 100,
        },
        await runtime.currentSession(),
      );
      if (!context.mounted) return;
      if (drivers.isEmpty) {
        feedback(context, 'Chưa có tài khoản giao hàng được cấp quyền.');
        return;
      }
      final vehicles = await (runtime.db.select(
        runtime.db.businessRecords,
      )..where((r) => r.kind.equals('vehicle'))).get();
      if (!context.mounted) return;
      if (vehicles.isNotEmpty &&
          vehicles.every((r) => recordData(r)['active'] == false)) {
        feedback(
          context,
          'Các xe đều ngừng hoạt động. Cập nhật danh mục xe trước.',
        );
        return;
      }
      await commandDialog(
        context,
        runtime,
        title: 'Phân công giao hàng',
        operation: Operation.assignDelivery,
        entityId: data['id'] as String,
        version: row.version,
        fields: [
          InputField(
            'driverId',
            'Nhân viên giao hàng',
            choices: [
              for (final driver in drivers)
                (
                  driver.name.split('/').last,
                  driver.data['displayName'] as String? ??
                      driver.name.split('/').last,
                ),
            ],
          ),
          vehicles.isEmpty
              ? const InputField(
                  'vehicleId',
                  'Xe / Biển số (thêm xe ở danh mục để kiểm tra tải trọng)',
                )
              : InputField(
                  'vehicleId',
                  'Xe',
                  choices: [
                    for (final row in vehicles.where(
                      (r) => recordData(r)['active'] != false,
                    ))
                      (
                        recordData(row)['id'] as String,
                        '${recordData(row)['name']} • ${recordData(row)['plate']}',
                      ),
                  ],
                ),
          const InputField(
            'loadKg',
            'Khối lượng chuyến dự kiến (kg)',
            number: true,
            initial: '0',
          ),
          const InputField(
            'scheduledAt',
            'Lịch giao (VD: 2026-11-06T08:30)',
            optional: true,
          ),
          const InputField('address', 'Địa chỉ giao', optional: true),
          const InputField('latitude', 'Vĩ độ (nếu có)', optional: true),
          const InputField('longitude', 'Kinh độ (nếu có)', optional: true),
        ],
        transform: (p) {
          final lat = p.remove('latitude') as String,
              lng = p.remove('longitude') as String;
          if (lat.isNotEmpty || lng.isNotEmpty) {
            p['latE6'] = coordinate(lat, 90000000);
            p['lngE6'] = coordinate(lng, 180000000);
          }
          return p;
        },
      );
    } catch (_) {
      if (context.mounted) {
        feedback(context, 'Không tải được danh sách nhân viên giao hàng.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: purchase ? 'purchase' : 'sale',
    onlyId: onlyId,
    title: purchase ? 'Đơn mua nhà cung cấp' : 'Đơn bán đã ghi sổ',
    actions: [
      if (allowed(runtime, purchase ? Operation.purchase : Operation.sale))
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  OrderComposer(runtime: runtime, purchase: purchase),
            ),
          ),
          icon: const Icon(Icons.add),
          label: Text(purchase ? 'Tạo đơn mua' : 'Tạo đơn bán'),
        ),
    ],
    item: (context, row, data) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${purchase ? 'Đơn mua' : 'Đơn bán'} ${shortId(data['id'] as String)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              purchase
                  ? 'Trạng thái: ${data['status']} • Đã nhận: ${vnd(data['receivedValue'] as int? ?? 0)}'
                  : 'Tổng: ${vnd(data['total'] as int)} • Còn nợ: ${vnd(data['debt'] as int)}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => openBusinessReceipt(
                    context,
                    runtime,
                    purchase ? 'purchase' : 'sale',
                    data,
                  ),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Xem / in phiếu'),
                ),
                if (purchase && allowed(runtime, Operation.receive))
                  OutlinedButton(
                    onPressed: () => lineAction(
                      context,
                      runtime,
                      row,
                      data,
                      Operation.receive,
                      'Nhận hàng từng đợt',
                    ),
                    child: const Text('Nhận hàng'),
                  ),
                if (!purchase) ...[
                  TextButton(
                    onPressed: () => prepareInvoice(context, runtime, data),
                    child: const Text('Chuẩn bị HĐ điện tử'),
                  ),
                  if (allowed(runtime, Operation.payment))
                    OutlinedButton(
                      onPressed: () => commandDialog(
                        context,
                        runtime,
                        title: 'Thu tiền / Thu nợ',
                        balance: data['debt'] as int,
                        operation: Operation.payment,
                        entityId: data['id'] as String,
                        version: row.version,
                        fields: [
                          const InputField(
                            'amount',
                            'Số tiền thu (VND)',
                            number: true,
                          ),
                          const InputField(
                            'method',
                            'Phương thức',
                            choices: methods,
                          ),
                          InputField(
                            'shiftId',
                            'Ca thu tiền',
                            initial: currentShift(runtime),
                          ),
                        ],
                      ),
                      child: const Text('Thu tiền'),
                    ),
                  if (allowed(runtime, Operation.returnSale))
                    OutlinedButton(
                      onPressed: () => lineAction(
                        context,
                        runtime,
                        row,
                        data,
                        Operation.returnSale,
                        'Tiếp nhận trả hàng',
                      ),
                      child: const Text('Trả hàng'),
                    ),
                  if (allowed(runtime, Operation.refund) &&
                      (data['refundDue'] as int? ?? 0) > 0)
                    OutlinedButton(
                      onPressed: () => commandDialog(
                        context,
                        runtime,
                        title: 'Hoàn tiền',
                        balance: data['refundDue'] as int,
                        operation: Operation.refund,
                        entityId: data['id'] as String,
                        version: row.version,
                        fields: [
                          InputField(
                            'amount',
                            'Số tiền hoàn (VND)',
                            number: true,
                            initial: '${data['refundDue']}',
                          ),
                          const InputField(
                            'method',
                            'Phương thức',
                            choices: methods,
                          ),
                          InputField(
                            'shiftId',
                            'Ca chi tiền',
                            initial: currentShift(runtime),
                          ),
                          const InputField('reason', 'Lý do'),
                        ],
                      ),
                      child: const Text('Hoàn tiền'),
                    ),
                  if (allowed(runtime, Operation.warranty))
                    OutlinedButton(
                      onPressed: () => commandDialog(
                        context,
                        runtime,
                        title: 'Tiếp nhận bảo hành',
                        operation: Operation.warranty,
                        entityId: const Uuid().v4(),
                        fixed: {
                          'saleId': data['id'],
                          'customerId': data['customerId'],
                        },
                        fields: [
                          InputField(
                            'productId',
                            'Hàng bảo hành',
                            choices: [
                              for (final line in data['lines'] as List)
                                (
                                  line['productId'] as String,
                                  line['name'] as String,
                                ),
                            ],
                          ),
                          const InputField(
                            'serial',
                            'Serial (nếu có)',
                            optional: true,
                          ),
                          const InputField('condition', 'Tình trạng tiếp nhận'),
                          const InputField('accessories', 'Phụ kiện kèm theo'),
                        ],
                      ),
                      child: const Text('Bảo hành'),
                    ),
                  if (allowed(runtime, Operation.assignDelivery))
                    OutlinedButton(
                      onPressed: () => assign(context, row, data),
                      child: const Text('Phân công giao'),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Chi tiết hàng hóa'),
              children: [
                for (final line in data['lines'] as List)
                  ListTile(
                    dense: true,
                    title: Text(
                      line['name'] as String? ?? line['productId'] as String,
                    ),
                    subtitle: Text(
                      'Số lượng: ${qty(line['quantity'] as int)}${line['received'] != null ? ' • Đã nhận: ${qty(line['received'] as int)}' : ''}',
                    ),
                    trailing: line['total'] != null
                        ? Text(vnd(line['total'] as int))
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class StockPage extends StatelessWidget {
  final AppRuntime runtime;
  const StockPage({super.key, required this.runtime});
  Future<void> count(
    BuildContext context,
    BusinessRecord row,
    Map<String, dynamic> data,
  ) => commandDialog(
    context,
    runtime,
    title: 'Kiểm kê và điều chỉnh có chứng từ',
    operation: Operation.inventoryCount,
    entityId: const Uuid().v4(),
    fixed: {
      'warehouse': data['warehouse'],
      'productId': data['productId'],
      'quality': data['quality'],
      'stockVersion': row.version,
    },
    fields: [
      InputField(
        'counted',
        'Số thực đếm (đơn vị gốc; nếu theo lô là số của lô)',
        number: true,
        scale: 3,
        initial: qty(data['quantity'] as int),
      ),
      const InputField('lotId', 'Mã lô (nếu theo lô)', optional: true),
      const InputField(
        'expectedLotQuantity',
        'Tồn lô trên sổ (nếu theo lô)',
        number: true,
        scale: 3,
        initial: '0',
      ),
      const InputField(
        'serialText',
        'Serial thừa hoặc thiếu, ngăn cách bằng dấu phẩy',
        optional: true,
      ),
      const InputField(
        'unitCost',
        'Giá vốn một đơn vị nếu tồn sổ bằng 0 (VND)',
        number: true,
        initial: '0',
      ),
      const InputField('reason', 'Lý do và căn cứ kiểm kê'),
    ],
    transform: (data) => {
      ...data,
      'serials': parseSerials(data['serialText'] as String? ?? ''),
    },
  );
  Future<void> assemble(BuildContext context) async {
    final db = runtime.db;
    final rows = await (db.select(
      db.businessRecords,
    )..where((r) => r.kind.equals('catalog'))).get();
    if (!context.mounted) return;
    final catalog = {for (final row in rows) row: recordData(row)};
    final kits = [
      for (final entry in catalog.entries)
        if ((entry.value['components'] as Map?)?.isNotEmpty == true &&
            entry.value['active'] != false)
          entry.key,
    ];
    if (kits.isEmpty) {
      feedback(
        context,
        'Khai báo định mức của bộ sản phẩm trong Hàng hóa trước.',
      );
      return;
    }
    final selected = kits.length == 1
        ? kits.single
        : await showDialog<BusinessRecord>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Chọn bộ sản phẩm'),
              children: [
                for (final row in kits)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, row),
                    child: Text(
                      "${catalog[row]!['sku']} • ${catalog[row]!['name']}",
                    ),
                  ),
              ],
            ),
          );
    if (selected == null || !context.mounted) return;
    final kit = catalog[selected]!;
    final bySku = {
      for (final product in catalog.values) product['sku']: product,
    };
    final components = (kit['components'] as Map).cast<String, int>();
    final tracked = <String, String>{};
    for (final sku in components.keys) {
      final part = bySku[sku];
      if (part == null ||
          part['active'] == false ||
          (part['components'] as Map?)?.isNotEmpty == true) {
        feedback(
          context,
          'Thành phần $sku chưa đồng bộ hoặc không còn hợp lệ.',
        );
        return;
      }
      final mode = part['tracking'];
      if (mode == 'lot' || mode == 'serial') tracked[sku] = mode as String;
    }
    final mode = kit['tracking'];
    await commandDialog(
      context,
      runtime,
      title: "Lắp bộ • ${kit['sku']}",
      operation: Operation.assemble,
      entityId: const Uuid().v4(),
      fields: [
        const InputField('warehouse', 'Kho', initial: 'main'),
        const InputField('kits', 'Số bộ cần lắp', number: true, initial: '1'),
        for (final entry in tracked.entries)
          InputField(
            'part:${entry.key}',
            "${entry.value == 'lot' ? 'Lô xuất' : 'Serial xuất'} • ${entry.key}",
            help:
                "${qty(components[entry.key]!)} ${bySku[entry.key]!['unit'] ?? ''} / bộ. "
                "${entry.value == 'lot' ? lotEntryHelp : 'Ngăn cách serial bằng dấu phẩy.'}",
          ),
        if (mode == 'lot') ...[
          const InputField('output', 'Lô thành phẩm', help: lotEntryHelp),
          const InputField('outputColor', 'Mã màu thành phẩm', optional: true),
        ],
        if (mode == 'serial')
          const InputField(
            'output',
            'Serial mới của thành phẩm',
            help: 'Nhập một serial mới cho mỗi bộ, ngăn cách bằng dấu phẩy.',
          ),
      ],
      transform: (data) {
        final count = data['kits'] as int;
        if (count < 1 || count > 1000000) {
          throw const FormatException('Nhập từ 1 đến 1.000.000 bộ.');
        }
        return {
          'productId': kit['id'],
          'warehouse': data['warehouse'],
          'kits': count,
          'catalogVersion': selected.version,
          if (tracked.isNotEmpty)
            'componentTracking': [
              for (final entry in tracked.entries)
                {
                  'sku': entry.key,
                  if (entry.value == 'lot')
                    ...lotFields(
                      data['part:${entry.key}'] as String,
                      count * components[entry.key]!,
                    )
                  else
                    'serials': parseSerials(
                      data['part:${entry.key}'] as String,
                    ),
                },
            ],
          if (mode == 'lot')
            'outputTracking': lotFields(
              data['output'] as String,
              count * 1000,
              color: data['outputColor'] as String,
            ),
          if (mode == 'serial')
            'outputTracking': {
              'serials': parseSerials(data['output'] as String),
            },
        };
      },
    );
  }

  Future<void> disposition(
    BuildContext context,
    BusinessRecord row,
    Map<String, dynamic> data,
  ) => commandDialog(
    context,
    runtime,
    title: 'Xử lý hàng lỗi',
    operation: Operation.qualityDisposition,
    entityId: const Uuid().v4(),
    fixed: {
      'warehouse': data['warehouse'],
      'productId': data['productId'],
      'quality': data['quality'],
      'stockVersion': row.version,
    },
    fields: [
      InputField(
        'action',
        'Cách xử lý',
        choices: [
          if (data['quality'] == 'quarantine') ('damage', 'Xác nhận hỏng'),
          if (data['quality'] == 'damaged')
            ('repair', 'Sửa xong, đưa về cách ly kiểm tra'),
          ('supplier', 'Xuất trả nhà cung cấp'),
          ('discard', 'Xuất hủy'),
        ],
      ),
      const InputField(
        'quantity',
        'Số lượng theo đơn vị gốc',
        number: true,
        scale: 3,
      ),
      const InputField('reason', 'Lý do và kết quả kiểm tra'),
      const InputField(
        'reference',
        'Số phiếu NCC nếu xuất trả',
        optional: true,
      ),
      const InputField(
        'imageUrl',
        'Liên kết HTTPS ảnh bằng chứng',
        optional: true,
      ),
      const InputField(
        'lotText',
        'Lô: A hoặc A:2; B:3 (đơn vị gốc)',
        optional: true,
      ),
      const InputField(
        'serialText',
        'Serial nếu theo dõi, ngăn cách bằng dấu phẩy',
        optional: true,
      ),
    ],
    transform: (data) =>
        {
            ...data,
            ...lotFields(data['lotText'] as String, data['quantity'] as int),
            'serials': parseSerials(data['serialText'] as String? ?? ''),
          }
          ..remove('serialText')
          ..remove('lotText'),
  );

  Future<void> movement(BuildContext context, Operation operation) async {
    final products = await runtime.db.select(runtime.db.products).get();
    if (!context.mounted) return;
    if (products.isEmpty) {
      feedback(context, 'Thêm và đồng bộ hàng hóa trước.');
      return;
    }
    final choices = [for (final p in products) (p.id, '${p.sku} • ${p.name}')];
    await commandDialog(
      context,
      runtime,
      title: operation == Operation.transfer
          ? 'Chuyển kho'
          : operation == Operation.release
          ? 'Chuyển về hàng tốt'
          : 'Chuyển cách ly',
      operation: operation,
      entityId: const Uuid().v4(),
      fields: [
        InputField('productId', 'Hàng hóa', choices: choices),
        if (operation == Operation.transfer) ...[
          const InputField('fromWarehouse', 'Kho nguồn', initial: 'main'),
          const InputField('toWarehouse', 'Kho đích'),
        ] else
          const InputField('warehouse', 'Kho', initial: 'main'),
        const InputField(
          'quantity',
          'Số lượng theo đơn vị gốc',
          number: true,
          scale: 3,
        ),
        const InputField('reason', 'Lý do'),
        const InputField(
          'lotText',
          'Lô: A hoặc A:2; B:3 (đơn vị gốc)',
          optional: true,
        ),
        const InputField(
          'serialText',
          'Serial (ngăn cách bằng dấu phẩy, nếu có)',
          optional: true,
        ),
      ],
      fixed: const {},
      transform: (data) {
        final lots = lotFields(
          data['lotText'] as String,
          data['quantity'] as int,
        );
        final tracked =
            {
                ...data,
                ...lots,
                'serials': parseSerials(data['serialText'] as String? ?? ''),
              }
              ..remove('serialText')
              ..remove('lotText');
        return operation == Operation.transfer
            ? {
                'fromWarehouse': data['fromWarehouse'],
                'toWarehouse': data['toWarehouse'],
                'reason': data['reason'],
                'lines': [
                  {
                    'productId': data['productId'],
                    'quantity': data['quantity'],
                    ...lots,
                    'serials': tracked['serials'],
                  },
                ],
              }
            : tracked;
      },
    );
  }

  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'stock',
    title: 'Tồn kho đã xác nhận',
    actions: [
      if (allowed(runtime, Operation.assemble))
        FilledButton.icon(
          onPressed: () => assemble(context),
          icon: const Icon(Icons.widgets_outlined),
          label: const Text('Lắp bộ'),
        ),
      for (final entry in [
        (Operation.transfer, 'Chuyển kho'),
        (Operation.quarantine, 'Cách ly'),
        (Operation.release, 'Chuyển về hàng tốt'),
      ])
        if (allowed(runtime, entry.$1))
          OutlinedButton(
            onPressed: () => movement(context, entry.$1),
            child: Text(entry.$2),
          ),
    ],
    item: (context, row, data) => Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ListTile(
            onTap: allowed(runtime, Operation.inventoryCount)
                ? () => count(context, row, data)
                : null,
            title: FutureBuilder(
              future:
                  (runtime.db.select(
                        runtime.db.products,
                      )..where((p) => p.id.equals(data['productId'] as String)))
                      .getSingleOrNull(),
              builder: (context, snapshot) =>
                  Text(snapshot.data?.name ?? data['productId'] as String),
            ),
            subtitle: Text(
              'Kho ${data['warehouse']} • ${switch (data['quality']) {
                'good' => 'Hàng tốt',
                'quarantine' => 'Cách ly',
                _ => 'Hàng hỏng',
              }}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  qty(data['quantity'] as int),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(vnd(data['value'] as int)),
              ],
            ),
          ),
          if (data['quality'] != 'good' &&
              (data['quantity'] as int) > 0 &&
              allowed(runtime, Operation.qualityDisposition))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: OutlinedButton.icon(
                onPressed: () => disposition(context, row, data),
                icon: const Icon(Icons.build_outlined),
                label: const Text('Xử lý hàng lỗi'),
              ),
            ),
        ],
      ),
    ),
  );
}

class DeliveriesPage extends StatelessWidget {
  final AppRuntime runtime;
  const DeliveriesPage({super.key, required this.runtime});
  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'delivery',
    title: 'Giao hàng',
    item: (context, row, data) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đơn ${shortId(data['id'] as String)} • Xe ${data['vehicleId']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text('Trạng thái: ${data['status']}'),
            if (data['scheduledAt'] != null)
              Text('Lịch: ${data['scheduledAt']}'),
            if (data['address'] != null) Text('Địa chỉ: ${data['address']}'),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      openBusinessReceipt(context, runtime, 'delivery', data),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Phiếu giao'),
                ),
                if (data['latE6'] != null && data['lngE6'] != null)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => DeliveryMap(data: data),
                      ),
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Bản đồ / Chỉ đường'),
                  ),
              ],
            ),
            for (final line in data['lines'] as List)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(line['name'] as String),
                subtitle: Text(
                  'Đã giao ${qty(line['delivered'] as int)} / ${qty(line['quantity'] as int)} ${line['unit']}',
                ),
              ),
            if (allowed(runtime, Operation.delivery) &&
                data['status'] != 'delivered')
              OutlinedButton(
                onPressed: () => lineAction(
                  context,
                  runtime,
                  row,
                  data,
                  Operation.delivery,
                  'Xác nhận số lượng chuyến giao',
                ),
                child: const Text('Giao từng chuyến'),
              ),
          ],
        ),
      ),
    ),
  );
}

class FinancePage extends StatelessWidget {
  final AppRuntime runtime;
  const FinancePage({super.key, required this.runtime});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (allowed(runtime, Operation.expense))
              FilledButton(
                onPressed: () => commandDialog(
                  context,
                  runtime,
                  title: 'Phiếu chi chi phí',
                  operation: Operation.expense,
                  entityId: const Uuid().v4(),
                  fields: [
                    const InputField(
                      'amount',
                      'Số tiền chi (VND)',
                      number: true,
                    ),
                    const InputField('method', 'Phương thức', choices: methods),
                    InputField('shiftId', 'Ca', initial: currentShift(runtime)),
                    const InputField('reason', 'Nội dung chi'),
                  ],
                ),
                child: const Text('Lập phiếu chi'),
              ),
            if (allowed(runtime, Operation.shiftClose))
              OutlinedButton(
                onPressed: () => showShiftClose(context, runtime),
                child: const Text('Chốt ca'),
              ),
          ],
        ),
        const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Khách còn nợ'),
            Tab(text: 'Nợ nhà cung cấp'),
            Tab(text: 'Chi phí'),
            Tab(text: 'Ca đã chốt'),
            Tab(text: 'Tiền đặt cọc'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            children: [
              for (final kind in [
                'receivable',
                'payable',
                'expense',
                'shiftClose',
                'customerDeposit',
              ])
                RecordList(
                  runtime: runtime,
                  kind: kind,
                  title: '',
                  item: (context, row, data) => Card(
                    child: ListTile(
                      onTap: kind == 'receivable' || kind == 'payable'
                          ? () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => DebtLedger(
                                  runtime: runtime,
                                  balanceRow: row,
                                  customer: kind == 'receivable',
                                ),
                              ),
                            )
                          : null,
                      title: Text(
                        kind == 'receivable' ||
                                kind == 'payable' ||
                                kind == 'customerDeposit'
                            ? row.id.split(':').skip(1).join(':')
                            : data['reason'] as String? ??
                                  data['shiftId'] as String? ??
                                  'Chứng từ',
                      ),
                      subtitle: Text(
                        kind == 'shiftClose'
                            ? 'Dự kiến: ${vnd(data['expected'] as int)} • Lệch: ${vnd(data['difference'] as int)}'
                            : kind == 'expense'
                            ? '${data['shiftId']} • ${data['method'] == 'cash' ? 'Tiền mặt' : 'Chuyển khoản'}'
                            : '',
                      ),
                      trailing:
                          kind == 'payable' &&
                              allowed(runtime, Operation.supplierPayment)
                          ? TextButton(
                              onPressed: () => commandDialog(
                                context,
                                runtime,
                                title: 'Trả tiền nhà cung cấp',
                                balance: data['balance'] as int,
                                operation: Operation.supplierPayment,
                                entityId: row.id.substring('payable:'.length),
                                version: row.version,
                                fields: [
                                  const InputField(
                                    'amount',
                                    'Số tiền trả (VND)',
                                    number: true,
                                  ),
                                  const InputField(
                                    'method',
                                    'Phương thức',
                                    choices: methods,
                                  ),
                                  InputField(
                                    'shiftId',
                                    'Ca',
                                    initial: currentShift(runtime),
                                  ),
                                ],
                              ),
                              child: Text(vnd(data['balance'] as int)),
                            )
                          : Text(
                              vnd(
                                (data['balance'] ??
                                        data['amount'] ??
                                        data['counted'] ??
                                        0)
                                    as int,
                              ),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class WarrantiesPage extends StatelessWidget {
  final AppRuntime runtime;
  const WarrantiesPage({super.key, required this.runtime});

  Future<void> replace(
    BuildContext context,
    BusinessRecord row,
    Map<String, dynamic> claim,
  ) async {
    final db = runtime.db;
    final records = await (db.select(
      db.businessRecords,
    )..where((r) => r.kind.isIn(['sale', 'returnReceipt']))).get();
    if (!context.mounted) return;
    final returns = <(String, String)>[];
    final replacements = <(String, String)>[];
    for (final record in records) {
      final data = recordData(record);
      final id = data['id'] as String;
      if (!(data['lines'] as List? ?? []).any(
        (line) => line['productId'] == claim['productId'],
      )) {
        continue;
      }
      final label =
          "${shortId(id)} • ${data['customerName'] ?? ''} • ${data['createdAt']?.toString().split('T').first ?? ''}";
      if (record.kind == 'returnReceipt' && data['saleId'] == claim['saleId']) {
        returns.add((id, label));
      }
      if (record.kind == 'sale' &&
          id != claim['saleId'] &&
          data['customerId'] == claim['customerId']) {
        replacements.add((id, label));
      }
    }
    if (returns.isEmpty || replacements.isEmpty) {
      feedback(
        context,
        'Cần ghi sổ phiếu trả của đơn gốc và đơn bán hàng thay thế trước.',
      );
      return;
    }
    await commandDialog(
      context,
      runtime,
      title: 'Đối chiếu đổi bảo hành',
      operation: Operation.warrantyUpdate,
      entityId: claim['id'] as String,
      version: row.version,
      fixed: const {'status': 'replaced'},
      fields: [
        InputField('returnId', 'Phiếu hàng trả', choices: returns),
        InputField(
          'replacementSaleId',
          'Đơn hàng thay thế',
          choices: replacements,
        ),
        InputField(
          'cost',
          'Chi phí (VND)',
          number: true,
          initial: '${claim['cost']}',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RecordList(
    runtime: runtime,
    kind: 'warranty',
    title: 'Theo dõi bảo hành',
    item: (context, row, data) => Card(
      child: ListTile(
        title: Text('Bảo hành ${shortId(data['id'] as String)}'),
        subtitle: Text(
          [
            if (data['customerName'] != null) data['customerName'],
            data['condition'],
            businessStatus(data['status']),
            vnd(data['cost'] as int),
            if (data['warrantyUntil'] != null)
              "Hạn ${data['warrantyUntil'].toString().split('T').first}",
            if (data['returnId'] != null)
              "Phiếu trả ${shortId(data['returnId'] as String)}",
            if (data['replacementSaleId'] != null)
              "Đơn thay ${shortId(data['replacementSaleId'] as String)}",
          ].join(' • '),
        ),
        trailing: allowed(runtime, Operation.warrantyUpdate)
            ? Wrap(
                children: [
                  if ({
                        StaffRole.admin,
                        StaffRole.manager,
                      }.contains(runtime.actor?.role) &&
                      {
                        'checking',
                        'repairing',
                        'supplier',
                      }.contains(data['status']))
                    IconButton(
                      tooltip: 'Đối chiếu đổi bảo hành',
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: () => replace(context, row, data),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => commandDialog(
                      context,
                      runtime,
                      title: 'Cập nhật bảo hành',
                      operation: Operation.warrantyUpdate,
                      entityId: data['id'] as String,
                      version: row.version,
                      fields: [
                        const InputField(
                          'status',
                          'Bước xử lý',
                          choices: [
                            ('checking', 'Đang kiểm tra'),
                            ('repairing', 'Đang sửa chữa'),
                            ('supplier', 'Gửi NCC'),
                            ('completed', 'Hoàn thành'),
                            ('rejected', 'Từ chối'),
                          ],
                        ),
                        InputField(
                          'cost',
                          'Chi phí (VND)',
                          number: true,
                          initial: '${data['cost']}',
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : null,
      ),
    ),
  );
}

class ConnectionPage extends StatefulWidget {
  final AppRuntime runtime;
  const ConnectionPage({super.key, required this.runtime});
  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> recover(OutboxData row) async {
    try {
      final draft = await widget.runtime.recoverRejected(row.id);
      if (!mounted) return;
      feedback(
        context,
        'Đã tạo nháp mới từ lệnh bị từ chối. Kiểm tra giá, tồn và đối chiếu đơn gốc trước khi gửi.',
      );
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => OrderComposer(
            runtime: widget.runtime,
            draft: draft,
            purchase: row.operation == 'purchase',
            quote: row.operation == 'quote',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        feedback(
          context,
          e is BusinessException
              ? e.message
              : 'Cần kết nối mạng để xác minh từ chối trước khi khôi phục.',
        );
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.runtime,
    builder: (context, _) {
      final r = widget.runtime;
      return ListView(
        children: [
          const Text(
            'Kết nối và trạm Windows',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(r.offline ? 'Đang làm việc cục bộ' : 'Có kết nối'),
          Text(
            r.lastSync == null
                ? 'Chưa đồng bộ'
                : 'Lần đồng bộ: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(r.lastSync!)}',
          ),
          if (r.error != null)
            Text(r.error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: r.syncing ? null : r.tick,
            icon: const Icon(Icons.sync),
            label: const Text('Đồng bộ ngay'),
          ),
          const SizedBox(height: 24),
          if (r.actor?.role == StaffRole.admin ||
              r.actor?.role == StaffRole.manager) ...[
            const Text(
              'Tài khoản trạm được cấp riêng. Giữ ứng dụng Windows mở để xác nhận giao dịch từ các thiết bị.',
            ),
            if (r.stationSession != null)
              OutlinedButton(
                onPressed: r.disconnectStation,
                child: const Text('Ngắt tài khoản trạm'),
              )
            else ...[
              const SizedBox(height: 16),
              TextField(
                controller: email,
                decoration: const InputDecoration(
                  labelText: 'Email tài khoản trạm',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu trạm'),
              ),
              const SizedBox(height: 16),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final secret = password.text;
                        password.clear();
                        setState(() => busy = true);
                        try {
                          await r.connectStation(email.text.trim(), secret);
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => error = 'Không kết nối được tài khoản trạm. Kiểm tra quyền và thông tin đăng nhập.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Kích hoạt trạm xác nhận'),
              ),
            ],
          ],
          const SizedBox(height: 24),
          StreamBuilder(
            stream: r.db.watchQueue(),
            builder: (context, snapshot) => Column(
              children: [
                for (final item in snapshot.data ?? <OutboxData>[])
                  Card(
                    child: ListTile(
                      title: Text(
                        '${item.operation ?? 'Đơn thử cũ'} • ${shortId(item.aggregateId)}',
                      ),
                      subtitle: Text(
                        '${item.status} • ${item.lastError ?? ''}',
                      ),
                      onTap:
                          item.actorUid == r.actor?.uid &&
                              {'error', 'conflict'}.contains(item.status) &&
                              {
                                'sale',
                                'purchase',
                                'quote',
                                'reservation',
                              }.contains(item.operation)
                          ? () => recover(item)
                          : null,
                      trailing:
                          item.status == 'error' &&
                              item.actorUid == r.actor?.uid
                          ? IconButton(
                              tooltip: 'Thử lại',
                              onPressed: () => r.retry(item.id),
                              icon: const Icon(Icons.refresh),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
