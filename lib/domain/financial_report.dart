import 'dart:convert';

import '../data/database.dart';

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
  BigInt get grossProfit => revenue - cost;
  BigInt get netProfit => grossProfit - expenses;
  const FinancialReport(
    this.revenue,
    this.cost,
    this.expenses,
    this.cashNet,
    this.bankNet,
    this.sales,
  );
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
        cost += BigInt.from(sale['cost'] as int);
        sales++;
      }
      if (event.kind == 'returnSale') {
        final id = data['entityId'] as String;
        final before = previousReturns[id] ?? (0, 0);
        final returned = result['returnedValue'] as int? ?? 0,
            returnedCost = result['returnedCost'] as int? ?? 0;
        if (inPeriod) {
          revenue -= BigInt.from(returned - before.$1);
          cost -= BigInt.from(returnedCost - before.$2);
        }
        previousReturns[id] = (returned, returnedCost);
      }
      if (!inPeriod) continue;
      if (event.kind == 'expense') {
        expenses += BigInt.from(input['amount'] as int);
      }
      final sign = event.kind == 'payment'
          ? 1
          : {'expense', 'refund', 'supplierPayment'}.contains(event.kind)
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
    return FinancialReport(revenue, cost, expenses, cash, bank, sales);
  }
}
