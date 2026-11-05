import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/financial_report.dart';

class RevenueChart extends StatelessWidget {
  final Map<String, BigInt> values;
  final DateTime end;
  final int days;
  const RevenueChart({
    super.key,
    required this.values,
    required this.end,
    required this.days,
  });
  @override
  Widget build(BuildContext context) {
    final count = days > 30 ? 30 : days;
    final dates = [
      for (var i = count; i > 0; i--) end.subtract(Duration(days: i)),
    ];
    var maximum = BigInt.one;
    for (final date in dates) {
      final n = (values[reportDay(date)] ?? BigInt.zero).abs();
      if (n > maximum) maximum = n;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Doanh thu thuần theo ngày${days > 30 ? ' • 30 ngày gần nhất' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final date in dates) buildBar(date, maximum)],
                ),
              ),
            ),
            const Text(
              'Trỏ hoặc nhấn giữ cột để xem số tiền. Hàng trả được trừ vào ngày ghi nhận trả.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBar(DateTime date, BigInt maximum) {
    final value = values[reportDay(date)] ?? BigInt.zero;
    final height = (value.abs() * BigInt.from(740) ~/ maximum).toInt() / 10;
    Widget bar() => Container(
      width: 28,
      height: height,
      decoration: BoxDecoration(
        color: value.isNegative ? Colors.red.shade400 : const Color(0xff2683f7),
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Tooltip(
      message: '${DateFormat('dd/MM/yyyy').format(date)}: ${largeVnd(value)}',
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            SizedBox(
              height: 78,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: value.isNegative ? const SizedBox() : bar(),
              ),
            ),
            Container(height: 1, color: Colors.blueGrey.shade200),
            SizedBox(
              height: 78,
              child: Align(
                alignment: Alignment.topCenter,
                child: value.isNegative ? bar() : const SizedBox(),
              ),
            ),
            Text(
              DateFormat('dd/MM').format(date),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
