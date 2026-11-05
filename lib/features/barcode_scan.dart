import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScanButton extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onScan;

  const BarcodeScanButton({
    super.key,
    this.enabled = true,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb &&
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Quét mã vạch bằng camera',
      icon: const Icon(Icons.qr_code_scanner),
      onPressed: !enabled
          ? null
          : () async {
              final code = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const _BarcodeCamera()),
              );
              if (context.mounted && code != null) onScan(code);
            },
    );
  }
}

class _BarcodeCamera extends StatefulWidget {
  const _BarcodeCamera();

  @override
  State<_BarcodeCamera> createState() => _BarcodeCameraState();
}

class _BarcodeCameraState extends State<_BarcodeCamera> {
  bool detected = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét mã vạch')),
    body: MobileScanner(
      onDetect: (capture) {
        if (!mounted || detected) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue?.trim();
          if (value == null || value.isEmpty || value.length > 1000) continue;
          detected = true;
          Navigator.of(context).pop(value);
          break;
        }
      },
      errorBuilder: (context, error) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Không mở được camera. Kiểm tra quyền camera hoặc quay lại nhập mã.',
          ),
        ),
      ),
    ),
  );
}
