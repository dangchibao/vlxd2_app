import 'package:flutter/material.dart';

import '../data/app_runtime.dart';
import '../domain/operations.dart';

class LoginGate extends StatefulWidget {
  final AppRuntime runtime;
  final Widget child;
  const LoginGate({super.key, required this.runtime, required this.child});
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  final username = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool obscure = true;
  String? previousUid;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit(bool change) async {
    if (change && password.text != confirm.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hai mật khẩu chưa khớp.')));
      return;
    }
    final value = password.text;
    password.clear();
    confirm.clear();
    if (change) {
      await widget.runtime.changePassword(value);
    } else {
      await widget.runtime.signIn(username.text, value);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.runtime,
    builder: (context, _) {
      final runtime = widget.runtime;
      final uid = runtime.actor?.uid;
      if (previousUid != null && previousUid != uid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
      previousUid = uid;
      if (!runtime.config.configured) return widget.child;
      if (runtime.session != null &&
          runtime.actor != null &&
          !runtime.actor!.mustChangePassword) {
        return SessionScope(runtime: runtime, child: widget.child);
      }
      final change = runtime.actor?.mustChangePassword == true;
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, size) => Row(
                    children: [
                      if (size.maxWidth > 650)
                        Expanded(
                          child: Container(
                            height: 480,
                            color: const Color(0xff0055d9),
                            padding: const EdgeInsets.all(32),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.storefront,
                                  size: 72,
                                  color: Colors.white,
                                ),
                                SizedBox(height: 24),
                                Text(
                                  'VLXD Bảy Hải',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Quản lý hàng hóa, kho và bán hàng\nDữ liệu cục bộ • Đồng bộ có xác nhận',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                change ? 'Đổi mật khẩu lần đầu' : 'Đăng nhập',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (!change)
                                TextField(
                                  controller: username,
                                  enabled: !runtime.loading,
                                  decoration: const InputDecoration(
                                    labelText: 'Tên đăng nhập',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: password,
                                enabled: !runtime.loading,
                                obscureText: obscure,
                                decoration: InputDecoration(
                                  labelText: change
                                      ? 'Mật khẩu mới (ít nhất 10 ký tự)'
                                      : 'Mật khẩu',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => obscure = !obscure),
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) =>
                                    runtime.loading ? null : submit(change),
                              ),
                              if (change) ...[
                                const SizedBox(height: 16),
                                TextField(
                                  controller: confirm,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Nhập lại mật khẩu mới',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Sau khi đổi, quản trị xác nhận kích hoạt tài khoản trước khi cho phép ghi chứng từ.',
                                ),
                              ],
                              if (runtime.error != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    runtime.error!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: runtime.loading
                                    ? null
                                    : () => submit(change),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: runtime.loading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          change ? 'Đổi mật khẩu' : 'Đăng nhập',
                                        ),
                                ),
                              ),
                              if (change)
                                TextButton(
                                  onPressed: runtime.loading
                                      ? null
                                      : runtime.checkMembership,
                                  child: const Text(
                                    'Kiểm tra trạng thái kích hoạt',
                                  ),
                                ),
                              if (change)
                                TextButton(
                                  onPressed: runtime.logout,
                                  child: const Text('Đăng xuất'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class SessionScope extends InheritedNotifier<AppRuntime> {
  const SessionScope({
    super.key,
    required AppRuntime runtime,
    required super.child,
  }) : super(notifier: runtime);
  static AppRuntime? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.notifier;
}

String roleLabel(StaffRole role) => switch (role) {
  StaffRole.admin => 'Quản trị',
  StaffRole.manager => 'Quản lý',
  StaffRole.sales => 'Bán hàng',
  StaffRole.warehouse => 'Kho',
  StaffRole.driver => 'Giao hàng',
};
