import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_runtime.dart';
import 'login_gate.dart';
import 'bayhai_style.dart';
import 'catalog_art.dart';

class MobileHome extends StatelessWidget {
  final AppRuntime runtime;
  final VoidCallback overview;
  final List<(String, IconData, Color, VoidCallback)> shortcuts;

  const MobileHome({
    super.key,
    required this.runtime,
    required this.overview,
    required this.shortcuts,
  });

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('mobile-home'),
    children: [
      Card(
        child: ListTile(
          onTap: overview,
          leading: const CircleAvatar(
            backgroundColor: BayHaiStyle.blueTint,
            foregroundColor: BayHaiStyle.primary,
            child: Icon(Icons.person_rounded),
          ),
          title: Text(
            'Xin chào, ${roleLabel(runtime.actor!.role)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            "Hôm nay, ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final columns = constraints.maxWidth < 268 ? 2 : 3;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (label, icon, color, open) in shortcuts)
                SizedBox(
                  width: width,
                  height: 76,
                  child: OutlinedButton(
                    onPressed: open,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BayHaiStyle.ink,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: color, size: 24),
                        const SizedBox(height: 5),
                        Text(
                          label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(BayHaiStyle.radius),
        child: Image.asset(
          '$catalogArt/showroom.jpg',
          height: 130,
          fit: BoxFit.cover,
          semanticLabel: 'Showroom vật liệu xây dựng Bảy Hải',
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: Icon(
            runtime.offline
                ? Icons.cloud_off_outlined
                : Icons.analytics_outlined,
            color: BayHaiStyle.primary,
          ),
          title: const Text('Tổng quan cửa hàng'),
          subtitle: Text(
            runtime.offline
                ? 'Đang xem dữ liệu trên máy'
                : 'Doanh thu, lợi nhuận và tình hình cửa hàng',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: overview,
        ),
      ),
    ],
  );
}

class MobileMore extends StatelessWidget {
  final AppRuntime runtime;
  final List<(String, IconData, VoidCallback)> actions;
  const MobileMore({super.key, required this.runtime, required this.actions});

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: BayHaiStyle.blueTint,
            foregroundColor: BayHaiStyle.primary,
            child: Icon(Icons.person_rounded),
          ),
          title: Text(
            roleLabel(runtime.actor!.role),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('VLXD Bảy Hải'),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0) const Divider(height: 1, indent: 52),
              ListTile(
                leading: Icon(actions[index].$2, color: BayHaiStyle.primary),
                title: Text(actions[index].$1),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: BayHaiStyle.muted,
                ),
                onTap: actions[index].$3,
              ),
            ],
          ],
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.logout, color: BayHaiStyle.red),
          title: const Text(
            'Đăng xuất',
            style: TextStyle(color: BayHaiStyle.red),
          ),
          onTap: runtime.logout,
        ),
      ),
    ],
  );
}
