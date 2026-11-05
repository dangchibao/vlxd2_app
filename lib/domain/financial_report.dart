import 'dart:convert';

import '../data/database.dart';
import 'operations.dart';

String reportDay(DateTime value) =>
    '${value.toLocal().year}-${value.toLocal().month.toString().padLeft(2, '0')}-${value.toLocal().day.toString().padLeft(2, '0')}';
String reportQuantity(BigInt value) {
  final absolute = value.abs(),
      fraction = (value.abs() % BigInt.from(1000))
          .toString()
          .padLeft(3, '0')
          .replaceFirst(RegExp(r'0+$'), '');
  return '${value.isNegative ? '-' : ''}${absolute ~/ BigInt.from(1000)}${fraction.isEmpty ? '' : ',$fraction'}';
}

class ProductSalesTotal {
  final String name, unit;
  final BigInt quantity, revenue;
  const ProductSalesTotal(this.name, this.unit, this.quantity, this.revenue);
}

String largeVnd(BigInt value) {
  final negative = value.isNegative;
  final digits = value.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  return '${negative ? '-' : ''}$digits đ';
}

class FinancialReport {
  final BigInt revenue, cost, expenses, cashNet, bankNet;
  final int sales;
  final Map<String, BigInt> dailyRevenue;
  final Map<String, ProductSalesTotal> products;
  BigInt get grossProfit => revenue - cost;
  BigInt get netProfit => grossProfit - expenses;
  const FinancialReport(
    this.revenue,
    this.cost,
    this.expenses,
    this.cashNet,
    this.bankNet,
    this.sales, {
    this.dailyRevenue = const {},
    this.products = const {},
  });
  factory FinancialReport.fromEvents(
    List<BusinessEvent> events,
    DateTime start,
    DateTime end,
  ) {
    var revenue = BigInt.zero,
        cost = BigInt.zero,
        expenses = BigInt.zero,
        cash = BigInt.zero,
        bank = BigInt.zero;
    var sales = 0;
    final previousReturns = <String, (int, int)>{};
    final daily = <String, BigInt>{}, products = <String, ProductSalesTotal>{};
    void productDelta(Map<String, dynamic> line, int quantity, int revenue) {
      final id = line['productId'] as String;
      final old = products[id];
      products[id] = ProductSalesTotal(
        line['name'] as String? ?? old?.name ?? id,
        line['unit'] as String? ?? old?.unit ?? '',
        (old?.quantity ?? BigInt.zero) + BigInt.from(quantity),
        (old?.revenue ?? BigInt.zero) + BigInt.from(revenue),
      );
    }

    final sorted = [...events]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final event in sorted) {
      final data = jsonDecode(event.payload) as Map<String, dynamic>;
      final input = data['input'] as Map<String, dynamic>? ?? {},
          result = data['result'] as Map<String, dynamic>? ?? {};
      final inPeriod =
          !event.occurredAt.isBefore(start) && event.occurredAt.isBefore(end);
      if ({'sale', 'quoteToSale', 'fulfillReservation'}.contains(event.kind) &&
          inPeriod) {
        final sale = event.kind != 'sale'
            ? result['saleDocument'] as Map<String, dynamic>
            : result;
        revenue += BigInt.from(sale['total'] as int);
        daily.update(
          reportDay(event.occurredAt),
          (n) => n + BigInt.from(sale['total'] as int),
          ifAbsent: () => BigInt.from(sale['total'] as int),
        );
        for (final line in sale['lines'] as List? ?? []) {
          productDelta(
            Map<String, dynamic>.from(line as Map),
            line['quantity'] as int,
            (line['netTotal'] ?? line['total']) as int,
          );
        }
        cost += BigInt.from(sale['cost'] as int);
        sales++;
      }
      if (event.kind == 'returnSale') {
        final id = data['entityId'] as String;
        final original = data['before'] as Map<String, dynamic>?;
        final before = original == null
            ? previousReturns[id] ?? (0, 0)
            : (
                original['returnedValue'] as int? ?? 0,
                original['returnedCost'] as int? ?? 0,
              );
        final returned = result['returnedValue'] as int? ?? 0,
            returnedCost = result['returnedCost'] as int? ?? 0;
        if (inPeriod) {
          revenue -= BigInt.from(returned - before.$1);
          daily.update(
            reportDay(event.occurredAt),
            (n) => n - BigInt.from(returned - before.$1),
            ifAbsent: () => -BigInt.from(returned - before.$1),
          );
          for (final item in input['lines'] as List? ?? []) {
            final line = (result['lines'] as List? ?? [])
                .where((l) => l['productId'] == item['productId'])
                .firstOrNull;
            if (line == null) continue;
            final q = item['quantity'] as int,
                returned = line['returned'] as int,
                originalQuantity = line['quantity'] as int,
                net = (line['netTotal'] ?? line['total']) as int;
            final amount =
                roundedRatio(net, returned, originalQuantity) -
                roundedRatio(net, returned - q, originalQuantity);
            productDelta(Map<String, dynamic>.from(line as Map), -q, -amount);
          }
          cost -= BigInt.from(returnedCost - before.$2);
        }
        previousReturns[id] = (returned, returnedCost);
      }
      if (!inPeriod) continue;
      if (event.kind == 'expense') {
        expenses += BigInt.from(input['amount'] as int);
      }
      final sign = {'payment', 'deposit'}.contains(event.kind)
          ? 1
          : {
              'expense',
              'refund',
              'supplierPayment',
              'reservationRefund',
            }.contains(event.kind)
          ? -1
          : 0;
      if (sign != 0) {
        final amount = BigInt.from(input['amount'] as int) * BigInt.from(sign);
        if (input['method'] == 'cash') {
          cash += amount;
        } else {
          bank += amount;
        }
      }
    }
    return FinancialReport(
      revenue,
      cost,
      expenses,
      cash,
      bank,
      sales,
      dailyRevenue: Map.unmodifiable(daily),
      products: Map.unmodifiable(products),
    );
  }
}
