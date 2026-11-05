import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vlxd_bay_hai/data/database.dart';
import 'package:vlxd_bay_hai/domain/financial_report.dart';

void main() {
  BusinessEvent event(
    int id,
    String kind,
    int day,
    Map<String, dynamic> input,
    Map<String, dynamic> result,
  ) => BusinessEvent(
    sequence: id,
    commandId: 'c$id',
    kind: kind,
    actorId: 'u',
    payload: jsonEncode({'entityId': 'sale', 'input': input, 'result': result}),
    occurredAt: DateTime(2026, 11, day),
  );
  test(
    'Report separates debt collection, returns, costs and operating expense',
    () {
      final events = [
        event(1, 'sale', 1, {}, {'total': 100000, 'cost': 60000}),
        event(2, 'returnSale', 1, {}, {
          'returnedValue': 40000,
          'returnedCost': 24000,
        }),
        event(3, 'payment', 2, {'amount': 100000, 'method': 'cash'}, {}),
        event(4, 'returnSale', 2, {}, {
          'returnedValue': 60000,
          'returnedCost': 36000,
        }),
        event(5, 'expense', 2, {'amount': 5000, 'method': 'cash'}, {}),
        event(6, 'supplierPayment', 2, {'amount': 10000, 'method': 'bank'}, {}),
      ];
      final r = FinancialReport.fromEvents(
        events,
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 3),
      );
      expect(r.revenue, BigInt.from(-20000));
      expect(r.cost, BigInt.from(-12000));
      expect(r.expenses, BigInt.from(5000));
      expect(r.netProfit, BigInt.from(-13000));
      expect(r.cashNet, BigInt.from(95000));
      expect(r.bankNet, BigInt.from(-10000));
      expect(r.sales, 0);
      expect(
        r.dailyRevenue[reportDay(DateTime(2026, 11, 2))],
        BigInt.from(-20000),
      );
    },
  );
  test('Report totals format exactly beyond JavaScript safe integer range', () {
    expect(reportQuantity(BigInt.from(-500)), '-0,5');
    expect(
      largeVnd(BigInt.parse('90000000000000001')),
      '90.000.000.000.000.001 đ',
    );
  });
}
