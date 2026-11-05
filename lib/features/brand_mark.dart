import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  final double size;
  final Color roofColor;
  const BrandMark({
    super.key,
    this.size = 64,
    this.roofColor = const Color(0xff073e98),
  });

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _BrandPainter(roofColor));
}

class _BrandPainter extends CustomPainter {
  final Color roofColor;
  const _BrandPainter(this.roofColor);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawPath(
      Path()
        ..moveTo(5, 40)
        ..lineTo(5, 28)
        ..lineTo(32, 8)
        ..lineTo(59, 28)
        ..lineTo(59, 40),
      Paint()
        ..color = roofColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    final brick = Paint()..color = const Color(0xffc15427);
    for (final rect in [
      const Rect.fromLTWH(23, 29, 18, 8),
      const Rect.fromLTWH(13, 41, 17, 8),
      const Rect.fromLTWH(34, 41, 17, 8),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        brick,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      roofColor != oldDelegate.roofColor;
}
