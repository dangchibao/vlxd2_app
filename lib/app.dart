import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'data/database.dart';
import 'data/app_runtime.dart';
import 'features/login_gate.dart';
import 'features/brand_mark.dart';
import 'features/bayhai_style.dart';
import 'features/mobile_home.dart';
import 'features/catalog_art.dart';
import 'features/business_pages.dart';
import 'features/reports_search.dart';
import 'features/data_tools.dart';
import 'features/business_drafts.dart';
import 'features/quotes_page.dart';
import 'features/reservations_page.dart';
import 'features/catalog_page.dart';
import 'features/staff_page.dart';
import 'features/alerts_page.dart';
import 'features/vehicles_page.dart';
import 'features/print_jobs_page.dart';
import 'features/settings_page.dart';
import 'features/documents_page.dart';
import 'domain/operations.dart';
import 'domain/sale.dart';
import 'features/material_calculator.dart';
import 'features/receipt_preview.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final config = AppConnection.environment();
  final db = AppDatabase(
    null,
    config.configured
        ? 'bayhai_${config.projectId}_${config.storeId}'
        : 'bayhai_v1',
  );
  ref.onDispose(db.close);
  return db;
});
final runtimeProvider = Provider<AppRuntime>((ref) {
  final value = AppRuntime(
    ref.watch(databaseProvider),
    AppConnection.environment(),
  );
  ref.onDispose(value.dispose);
  unawaited(value.restore());
  return value;
});
final productsProvider = StreamProvider(
  (ref) => ref.watch(databaseProvider).watchProducts(),
);
final draftsProvider = StreamProvider(
  (ref) => ref.watch(databaseProvider).watchDrafts(),
);
final queueProvider = StreamProvider(
  (ref) => ref.watch(databaseProvider).watchQueue(),
);
String money(int value) =>
    '${NumberFormat.decimalPattern('vi').format(value)} đ';
final router = GoRouter(
  routes: [GoRoute(path: '/', builder: (_, _) => const RuntimeGate())],
);

class RuntimeGate extends ConsumerWidget {
  const RuntimeGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider);
    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) => LoginGate(
        runtime: runtime,
        child: runtime.actor == null
            ? const Workspace()
            : ProviderScope(
                key: ValueKey(runtime.actor!.uid),
                overrides: [
                  databaseProvider.overrideWithValue(runtime.db),
                  runtimeProvider.overrideWithValue(runtime),
                ],
                child: const Workspace(),
              ),
      ),
    );
  }
}

class BayHaiApp extends StatelessWidget {
  const BayHaiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'VLXD Bảy Hải',
    debugShowCheckedModeBanner: false,
    routerConfig: router,
    theme: BayHaiStyle.theme,
  );
}

class Workspace extends ConsumerStatefulWidget {
  const Workspace({super.key});
  @override
  ConsumerState<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<Workspace> {
  int page = 0;
  bool showMore = false;

  void go(int index) => setState(() {
    page = index;
    showMore = false;
  });
  final labels = [
    'Tổng quan',
    'Hàng hóa',
    'Bán hàng',
    'Đơn đã lưu',
    'Đồng bộ',
    'Tính vật liệu',
  ];
  final icons = [
    Icons.dashboard_outlined,
    Icons.inventory_2_outlined,
    Icons.shopping_cart_outlined,
    Icons.receipt_long_outlined,
    Icons.sync,
    Icons.calculate_outlined,
  ];
  @override
  Widget build(BuildContext context) {
    final runtime = SessionScope.maybeOf(context);
    final driver = runtime?.actor?.role == StaffRole.driver;
    final mobile = MediaQuery.sizeOf(context).width < 800;
    final mobileShell = mobile && runtime != null && !driver;
    final labels = runtime == null
        ? this.labels
        : driver
        ? ['Giao hàng', 'Đồng bộ']
        : [
            'Tổng quan',
            'Hàng hóa',
            'Bán hàng',
            'Mua hàng',
            'Đối tác',
            'Kho',
            'Thu chi / Công nợ',
            'Bảo hành',
            'Đồng bộ / Trạm',
            'Tính vật liệu',
            'Giao hàng',
            'Báo cáo',
            'Tìm kiếm',
            'Excel / Sao lưu',
            'Đơn nháp',
            'Báo giá',
            'Giữ hàng / Duyệt tồn',
            'Lô / Serial',
            'Nhân viên',
            'Cảnh báo',
            'Xe giao hàng',
            'Yêu cầu / Nhật ký in',
            'Thiết lập',
            'Chứng từ',
            if (mobileShell) ...[
              'Khách hàng',
              'Nhà cung cấp',
              'Tổng quan cửa hàng',
            ],
          ];
    final icons = runtime == null
        ? this.icons
        : driver
        ? [Icons.local_shipping_outlined, Icons.sync]
        : [
            Icons.dashboard_outlined,
            Icons.inventory_2_outlined,
            Icons.shopping_cart_outlined,
            Icons.local_shipping_outlined,
            Icons.people_outline,
            Icons.warehouse_outlined,
            Icons.payments_outlined,
            Icons.build_outlined,
            Icons.sync,
            Icons.calculate_outlined,
            Icons.local_shipping_outlined,
            Icons.bar_chart_outlined,
            Icons.search,
            Icons.backup_outlined,
            Icons.edit_note_outlined,
            Icons.request_quote_outlined,
            Icons.pending_actions_outlined,
            Icons.qr_code_outlined,
            Icons.manage_accounts_outlined,
            Icons.notifications_active_outlined,
            Icons.directions_car_outlined,
            Icons.print_outlined,
            Icons.settings_outlined,
            Icons.description_outlined,
            if (mobileShell) ...[
              Icons.person_outline,
              Icons.store_outlined,
              Icons.analytics_outlined,
            ],
          ];
    final mainNav = [
      ('Trang chủ', Icons.home_outlined, labels.indexOf('Tổng quan')),
      ('Bán hàng', Icons.shopping_cart_outlined, labels.indexOf('Bán hàng')),
      ('Kho', Icons.warehouse_outlined, labels.indexOf('Kho')),
      (
        'Công nợ',
        Icons.account_balance_wallet_outlined,
        labels.indexOf('Thu chi / Công nợ'),
      ),
    ];
    final pages = runtime == null
        ? const [
            Overview(),
            Catalog(),
            SaleEditor(),
            DraftList(),
            QueueView(),
            MaterialCalculator(),
          ]
        : driver
        ? [DeliveriesPage(runtime: runtime), ConnectionPage(runtime: runtime)]
        : [
            if (mobileShell)
              MobileHome(
                runtime: runtime,
                overview: () => go(labels.indexOf('Tổng quan cửa hàng')),
                shortcuts: [
                  for (final (label, destination, icon, color) in const [
                    (
                      'Bán hàng',
                      'Bán hàng',
                      Icons.shopping_bag_outlined,
                      BayHaiStyle.primary,
                    ),
                    (
                      'Nhập hàng',
                      'Mua hàng',
                      Icons.inventory_2_outlined,
                      BayHaiStyle.orange,
                    ),
                    (
                      'Tồn kho',
                      'Kho',
                      Icons.warehouse_outlined,
                      BayHaiStyle.green,
                    ),
                    (
                      'Khách hàng',
                      'Khách hàng',
                      Icons.people_outline,
                      BayHaiStyle.purple,
                    ),
                    (
                      'Nhà cung cấp',
                      'Nhà cung cấp',
                      Icons.store_outlined,
                      BayHaiStyle.primary,
                    ),
                    (
                      'Công nợ',
                      'Thu chi / Công nợ',
                      Icons.payments_outlined,
                      BayHaiStyle.orange,
                    ),
                    (
                      'Báo cáo',
                      'Báo cáo',
                      Icons.bar_chart_rounded,
                      BayHaiStyle.primary,
                    ),
                    (
                      'Giao hàng',
                      'Giao hàng',
                      Icons.local_shipping_outlined,
                      BayHaiStyle.red,
                    ),
                    (
                      'Bảo hành',
                      'Bảo hành',
                      Icons.verified_user_outlined,
                      BayHaiStyle.purple,
                    ),
                  ])
                    (label, icon, color, () => go(labels.indexOf(destination))),
                ],
              )
            else
              ReportsPage(runtime: runtime, dashboard: true),
            CatalogPage(runtime: runtime),
            TradingPage(runtime: runtime),
            TradingPage(runtime: runtime, purchase: true),
            PartiesPage(runtime: runtime),
            if (mobileShell)
              DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Tồn kho'),
                        Tab(text: 'Sản phẩm'),
                        Tab(text: 'Lô / Serial'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          StockPage(runtime: runtime),
                          CatalogPage(runtime: runtime),
                          TrackingPage(runtime: runtime),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              StockPage(runtime: runtime),
            FinancePage(runtime: runtime),
            WarrantiesPage(runtime: runtime),
            ConnectionPage(runtime: runtime),
            const MaterialCalculator(),
            DeliveriesPage(runtime: runtime),
            ReportsPage(runtime: runtime),
            GlobalSearchPage(runtime: runtime),
            DataToolsPage(runtime: runtime),
            BusinessDraftsPage(runtime: runtime),
            QuotesPage(runtime: runtime),
            ReservationsPage(runtime: runtime),
            TrackingPage(runtime: runtime),
            StaffPage(runtime: runtime),
            AlertsPage(runtime: runtime),
            VehiclesPage(runtime: runtime),
            PrintJobsPage(runtime: runtime),
            SettingsPage(runtime: runtime),
            DocumentsPage(runtime: runtime),
            if (mobileShell) ...[
              PartiesPage(runtime: runtime, partyType: 'customer'),
              PartiesPage(runtime: runtime, partyType: 'supplier'),
              ReportsPage(runtime: runtime, dashboard: true),
            ],
          ];
    if (page >= pages.length) page = 0;
    final more = mobileShell && showMore;
    const pinned = [
      'Nhân viên',
      'Excel / Sao lưu',
      'Đồng bộ / Trạm',
      'Thiết lập',
      'Yêu cầu / Nhật ký in',
      'Chứng từ',
    ];
    final content = runtime != null && more
        ? MobileMore(
            runtime: runtime,
            actions: [
              for (final label in pinned)
                (
                  label,
                  icons[labels.indexOf(label)],
                  () => go(labels.indexOf(label)),
                ),
              for (var i = 1; i < labels.length; i++)
                if (!pinned.contains(labels[i]))
                  (labels[i], icons[i], () => go(i)),
            ],
          )
        : KeyedSubtree(key: ValueKey(page), child: pages[page]);
    final mobileTitle = more
        ? 'Thêm'
        : page == 0
        ? 'VLXD Bảy Hải'
        : labels[page];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BayHaiStyle.navy,
        foregroundColor: Colors.white,
        centerTitle: mobileShell,
        automaticallyImplyLeading: !mobileShell,
        leading: mobileShell && (more || page != 0)
            ? IconButton(
                tooltip: 'Về trang chủ',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => go(0),
              )
            : null,
        title: mobileShell && (more || page != 0)
            ? Text(
                mobileTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              )
            : const Row(
                children: [
                  BrandMark(size: 30, roofColor: Colors.white),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'VLXD Bảy Hải',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
        actions: [
          if (runtime == null)
            IconButton(
              onPressed: () => SampleCatalog.open(context),
              icon: const Icon(Icons.grid_view_outlined),
              tooltip: 'Xem danh mục mẫu',
            ),
          if (runtime != null) ...[
            IconButton(
              tooltip: 'Đồng bộ',
              onPressed: runtime.syncing ? null : runtime.tick,
              icon: Icon(
                runtime.offline ? Icons.cloud_off_outlined : Icons.sync,
              ),
            ),
            if (!mobileShell)
              IconButton(
                tooltip: 'Đăng xuất',
                onPressed: runtime.logout,
                icon: const Icon(Icons.logout),
              ),
          ],
          if (!mobile)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                runtime == null
                    ? 'Cục bộ • Chưa kết nối Firebase'
                    : '${roleLabel(runtime.actor!.role)} • ${runtime.offline ? 'Offline' : 'Đã đăng nhập'}',
              ),
            )
          else if (runtime == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Tooltip(
                message: 'Cục bộ • Chưa kết nối Firebase',
                child: Icon(Icons.cloud_off_outlined),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, size) => Row(
          children: [
            if (size.maxWidth >= 800)
              SizedBox(
                width: 205,
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Expanded(
                      child: ListView(
                        children: [
                          for (var i = 0; i < labels.length; i++)
                            ListTile(
                              selected: page == i,
                              selectedTileColor: const Color(0xffdceaff),
                              leading: Icon(icons[i]),
                              title: Text(labels[i]),
                              onTap: () => setState(() => page = i),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'VLXD Bảy Hải',
                      ),
                      child: const Text('Giấy phép phần mềm'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        runtime == null
                            ? 'Chế độ xem thử cục bộ'
                            : 'VLXD Bảy Hải 1.0.1',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(mobileShell ? 12 : 20),
                child: content,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: mobileShell
          ? Builder(
              builder: (context) {
                final selected = mainNav.indexWhere(
                  (entry) => entry.$3 == page,
                );
                return NavigationBar(
                  height: 62,
                  selectedIndex: more || selected < 0
                      ? mainNav.length
                      : selected,
                  onDestinationSelected: (index) {
                    if (index == mainNav.length) {
                      setState(() => showMore = true);
                    } else {
                      go(mainNav[index].$3);
                    }
                  },
                  destinations: [
                    for (final (label, icon, _) in mainNav)
                      NavigationDestination(icon: Icon(icon), label: label),
                    const NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: 'Thêm',
                    ),
                  ],
                );
              },
            )
          : null,
      drawer: mobile && !mobileShell
          ? Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'VLXD Bảy Hải',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    for (var i = 0; i < labels.length; i++)
                      ListTile(
                        leading: Icon(icons[i]),
                        title: Text(labels[i]),
                        selected: page == i,
                        onTap: () {
                          setState(() => page = i);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class Overview extends ConsumerWidget {
  const Overview({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider).asData?.value;
    final drafts = ref.watch(draftsProvider).asData?.value;
    final queue = ref.watch(queueProvider).asData?.value;
    return ListView(
      children: [
        const Text(
          'Tổng quan cửa hàng',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            metric(
              'Hàng hóa cục bộ',
              products?.length.toString() ?? '…',
              Colors.blue,
            ),
            metric(
              'Đơn đã lưu',
              drafts?.length.toString() ?? '…',
              Colors.green,
            ),
            metric(
              'Chờ xác nhận',
              queue?.length.toString() ?? '…',
              Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Bắt đầu bằng cách thêm hàng hóa, sau đó lập đơn bán hàng.\n\nDữ liệu được lưu trên thiết bị. Đơn chờ xử lý chưa trừ kho, chưa ghi nhận doanh thu hoặc công nợ.\nChưa cấu hình đăng nhập, trạm xác nhận và đồng bộ Firebase.',
            ),
          ),
        ),
      ],
    );
  }

  Widget metric(String label, String value, MaterialColor color) => SizedBox(
    width: 240,
    child: Card(
      color: color.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: color.shade800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Catalog extends ConsumerStatefulWidget {
  const Catalog({super.key});
  @override
  ConsumerState<Catalog> createState() => _CatalogState();
}

class _CatalogState extends ConsumerState<Catalog> {
  String search = '';
  Future<void> add() async {
    final runtime = SessionScope.maybeOf(context);
    final fields = List.generate(4, (_) => TextEditingController());
    final form = GlobalKey<FormState>();
    String? error;
    String tracking = 'none';
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Thêm hàng hóa'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: fields[i],
                        decoration: InputDecoration(
                          labelText: [
                            'Mã SKU',
                            'Tên sản phẩm',
                            'Đơn vị tính',
                            'Giá bán (VND)',
                          ][i],
                        ),
                        keyboardType: i == 3
                            ? TextInputType.number
                            : TextInputType.text,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Vui lòng nhập thông tin'
                            : i == 3 &&
                                  (int.tryParse(v) == null ||
                                      int.parse(v) < 0 ||
                                      int.parse(v) > 1000000000000)
                            ? 'Nhập số nguyên từ 0 đến 1.000.000.000.000'
                            : null,
                      ),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (runtime != null)
                    DropdownButtonFormField<String>(
                      initialValue: tracking,
                      decoration: const InputDecoration(
                        labelText: 'Theo dõi tồn',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Theo số lượng'),
                        ),
                        DropdownMenuItem(
                          value: 'lot',
                          child: Text('Theo lô / mã màu'),
                        ),
                        DropdownMenuItem(
                          value: 'serial',
                          child: Text('Theo serial thiết bị'),
                        ),
                      ],
                      onChanged: busy ? null : (v) => tracking = v!,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) {
                        return;
                      }
                      update(() => busy = true);
                      try {
                        if (runtime != null) {
                          await runtime.enqueue(
                            Operation.catalog,
                            const Uuid().v4(),
                            {
                              'sku': fields[0].text.trim(),
                              'name': fields[1].text.trim(),
                              'unit': fields[2].text.trim(),
                              'price': int.parse(fields[3].text),
                              'tracking': tracking,
                            },
                          );
                        } else {
                          await ref
                              .read(databaseProvider)
                              .addProduct(
                                fields[0].text,
                                fields[1].text,
                                fields[2].text,
                                int.parse(fields[3].text),
                              );
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      } catch (_) {
                        update(() {
                          error = 'Không lưu được. Kiểm tra mã SKU trùng hoặc dữ liệu.';
                          busy = false;
                        });
                      }
                    },
              child: const Text('Lưu hàng hóa'),
            ),
          ],
        ),
      ),
    );
    // Dialog route owns its text fields until its exit animation completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final field in fields) {
      field.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 20,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Danh sách hàng hóa',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          FilledButton.icon(
            onPressed: add,
            icon: const Icon(Icons.add),
            label: const Text('Thêm hàng hóa'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Tìm tên sản phẩm, mã SKU…',
        ),
        onChanged: (v) => setState(() => search = v.toLowerCase()),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: ref
            .watch(productsProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Text(
                'Không đọc được database. Hãy khởi động lại ứng dụng.',
              ),
              data: (items) {
                final filtered = items
                    .where(
                      (p) =>
                          '${p.sku} ${p.name}'.toLowerCase().contains(search),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Chưa có hàng hóa phù hợp.'));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final p = filtered[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.blue,
                        ),
                        title: Text(p.name),
                        subtitle: Text('${p.sku} • ${p.unit}'),
                        trailing: Text(
                          money(p.price),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      ),
    ],
  );
}

class SaleEditor extends ConsumerStatefulWidget {
  final Draft? draft;
  const SaleEditor({super.key, this.draft});
  @override
  ConsumerState<SaleEditor> createState() => _SaleEditorState();
}

class _SaleEditorState extends ConsumerState<SaleEditor> {
  late String id;
  List<SaleLine> lines = [];
  final invalidQuantities = <String>{};
  final customer = TextEditingController(),
      discount = TextEditingController(text: '0'),
      paid = TextEditingController(text: '0');
  Timer? timer;
  Future<void> tail = Future.value();
  bool busy = false, submitted = false;
  String status = 'Chưa lưu', search = '';
  @override
  void initState() {
    super.initState();
    id = widget.draft?.id ?? const Uuid().v4();
    if (widget.draft != null) {
      final j = jsonDecode(widget.draft!.payload) as Map<String, dynamic>;
      lines = (j['lines'] as List)
          .map((v) => SaleLine.fromJson(v as Map<String, dynamic>))
          .toList();
      customer.text = j['customer'] as String;
      discount.text = '${j['discount']}';
      paid.text = '${j['paid']}';
    }
  }

  SaleTotals? get totals {
    if (invalidQuantities.isNotEmpty) return null;
    try {
      return SaleTotals(
        lines,
        discount: int.parse(discount.text),
        paid: int.parse(paid.text),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> get payload => {
    'customer': customer.text,
    'lines': lines.map((l) => l.toJson()).toList(),
    'discount': int.parse(discount.text),
    'paid': int.parse(paid.text),
  };
  void changed() {
    setState(() => status = 'Đang chỉnh sửa');
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 500), () => save());
  }

  Future<void> save({bool submit = false}) async {
    if (submitted || totals == null || lines.isEmpty) {
      return;
    }
    final snapshot = payload;
    final draftId = id;
    final database = ref.read(databaseProvider);
    tail = tail
        .catchError((Object _) {})
        .then((_) => database.saveDraft(draftId, snapshot, submit: submit));
    try {
      await tail;
      if (mounted) {
        setState(() {
          status = submit
              ? 'Chờ xác nhận • Chưa ghi sổ'
              : 'Đã lưu trên thiết bị';
          if (submit) {
            submitted = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => status = 'Lưu thất bại. Vui lòng thử lại.');
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    customer.dispose();
    discount.dispose();
    paid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = totals;
    final products = ref.watch(productsProvider).asData?.value ?? <Product>[];
    return ListView(
      children: [
        const Text(
          'Tạo đơn bán hàng',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: customer,
          enabled: !submitted && !busy,
          decoration: const InputDecoration(
            labelText: 'Khách hàng / Số điện thoại',
          ),
          onChanged: (_) => changed(),
        ),
        const SizedBox(height: 16),
        if (!submitted)
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Tìm hàng để thêm vào đơn',
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        if (!submitted)
          ...products
              .where(
                (p) =>
                    search.isNotEmpty &&
                    '${p.name} ${p.sku}'.toLowerCase().contains(
                      search.toLowerCase(),
                    ),
              )
              .take(8)
              .map(
                (p) => ListTile(
                  title: Text(p.name),
                  subtitle: Text('${p.sku} • ${money(p.price)} / ${p.unit}'),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: busy
                      ? null
                      : () {
                          final i = lines.indexWhere(
                            (l) => l.productId == p.id,
                          );
                          if (i < 0) {
                            lines.add(
                              SaleLine(
                                productId: p.id,
                                sku: p.sku,
                                name: p.name,
                                unit: p.unit,
                                price: p.price,
                              ),
                            );
                          } else {
                            lines[i] = lines[i].withQuantity(
                              lines[i].quantity + 1,
                            );
                          }
                          changed();
                        },
                ),
              ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Thêm hàng hóa ở mục Hàng hóa, sau đó tìm và chọn sản phẩm.',
            ),
          ),
        for (var i = 0; i < lines.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lines[i].name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${lines[i].sku} • ${money(lines[i].price)} / ${lines[i].unit}',
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: TextFormField(
                          key: ValueKey(lines[i].productId),
                          initialValue: '${lines[i].quantity}',
                          enabled: !submitted && !busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Số lượng',
                          ),
                          onChanged: (v) {
                            final q = int.tryParse(v);
                            if (q != null && q > 0 && q <= 1000000) {
                              invalidQuantities.remove(lines[i].productId);
                              lines[i] = lines[i].withQuantity(q);
                            } else {
                              invalidQuantities.add(lines[i].productId);
                            }
                            changed();
                          },
                          validator: (v) => int.tryParse(v ?? '') == null
                              ? 'Số lượng không hợp lệ'
                              : null,
                        ),
                      ),
                      const Spacer(),
                      Text(money(lines[i].total)),
                      IconButton(
                        onPressed: submitted || busy
                            ? null
                            : () {
                                invalidQuantities.remove(lines[i].productId);
                                lines.removeAt(i);
                                changed();
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: discount,
                enabled: !submitted && !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Chiết khấu (VND)',
                ),
                onChanged: (_) => changed(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: paid,
                enabled: !submitted && !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Thanh toán tạm (VND)',
                ),
                onChanged: (_) => changed(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (t == null)
          const Text(
            'Kiểm tra chiết khấu/thanh toán: phải là số nguyên không âm và không vượt giá trị đơn.',
            style: TextStyle(color: Colors.red),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Tiền hàng: ${money(t.subtotal)}'),
                  Text(
                    'Tổng tiền: ${money(t.total)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('Còn nợ tạm tính: ${money(t.debt)}'),
                ],
              ),
            ),
          ),
        Text(status),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton(
              onPressed: submitted || busy || t == null || lines.isEmpty
                  ? null
                  : () => save(),
              child: const Text('Lưu nháp'),
            ),
            FilledButton(
              onPressed: submitted || busy || t == null || lines.isEmpty
                  ? null
                  : () async {
                      timer?.cancel();
                      setState(() => busy = true);
                      await save(submit: true);
                      if (mounted) {
                        setState(() => busy = false);
                      }
                    },
              child: const Text('Gửi chờ xác nhận'),
            ),
            OutlinedButton.icon(
              onPressed: t == null || lines.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReceiptPreview(
                          database: ref.read(databaseProvider),
                          documentId: id,
                          customer: customer.text,
                          lines: List.unmodifiable(lines),
                          totals: t,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Xem phiếu K80'),
            ),
            if (submitted)
              OutlinedButton(
                onPressed: () => setState(() {
                  id = const Uuid().v4();
                  lines = [];
                  customer.clear();
                  discount.text = '0';
                  paid.text = '0';
                  invalidQuantities.clear();
                  submitted = false;
                  status = 'Chưa lưu';
                }),
                child: const Text('Tạo đơn tiếp theo'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Chưa kết nối trạm xác nhận. Không dùng đơn tạm thay cho chứng từ đã ghi sổ.',
        ),
      ],
    );
  }
}

class DraftList extends ConsumerWidget {
  const DraftList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(draftsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Text('Không tải được đơn.'),
        data: (items) => items.isEmpty
            ? const Center(child: Text('Chưa có đơn được lưu.'))
            : ListView(
                children: [
                  const Text(
                    'Đơn đã lưu',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  for (final d in items)
                    Card(
                      child: ListTile(
                        title: Text('Đơn ${d.id.substring(0, 8)}'),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(d.updatedAt)} • ${d.status == 'draft' ? 'Bản nháp' : 'Chờ xác nhận'}',
                        ),
                        trailing: d.status == 'draft'
                            ? const Icon(Icons.edit_outlined)
                            : const Icon(Icons.hourglass_empty),
                        onTap: d.status != 'draft'
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(
                                      title: const Text('Khôi phục đơn nháp'),
                                    ),
                                    body: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: SaleEditor(draft: d),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                ],
              ),
      );
}

class QueueView extends ConsumerWidget {
  const QueueView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(queueProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Text('Không tải được hàng đợi.'),
        data: (items) => ListView(
          children: [
            const Text(
              'Hàng đợi giao dịch',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Chưa cấu hình Firebase/trạm xác nhận. Giao dịch được giữ trên thiết bị, không tự xác nhận.',
            ),
            for (final item in items)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off),
                  title: Text(item.aggregateId.substring(0, 8)),
                  subtitle: Text(
                    item.actorUid == null
                        ? 'Đơn thử cục bộ, chưa gắn tài khoản đồng bộ.'
                        : '${item.status} • Số lần thử: ${item.attempts}',
                  ),
                ),
              ),
          ],
        ),
      );
}
