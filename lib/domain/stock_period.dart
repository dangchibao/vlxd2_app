import 'dart:convert';

import '../data/database.dart';

typedef StockPosition = (String warehouse, String product, String quality);

class StockMovement {
  final StockPosition position;
  final String sku, name, unit, commandId, operation;
  final DateTime time;
  final int quantity, value;
  const StockMovement(
    this.position,
    this.sku,
    this.name,
    this.unit,
    this.commandId,
    this.operation,
    this.time,
    this.quantity,
    this.value,
  );
}

class StockPeriodRow {
  final StockMovement item;
  BigInt opening = BigInt.zero;
  BigInt incoming = BigInt.zero;
  BigInt outgoing = BigInt.zero;
  BigInt openingValue = BigInt.zero;
  BigInt valueChange = BigInt.zero;
  StockPeriodRow(this.item);
  BigInt get closing => opening + incoming - outgoing;
  BigInt get closingValue => openingValue + valueChange;
}

class StockPeriod {
  final List<StockPeriodRow> balances;
  final List<StockMovement> movements;
  final int missingHistory;
  const StockPeriod(this.balances, this.movements, this.missingHistory);

  factory StockPeriod.fromLedger(
    List<InboxEvent> inbox,
    List<BusinessEvent> events,
    DateTime start,
    DateTime end,
  ) {
    final byId = {for (final event in events) event.commandId: event};
    final previous = <StockPosition, (int, int)>{};
    final balances = <StockPosition, StockPeriodRow>{};
    final movements = <StockMovement>[];
    var missing = 0;
    for (final entry in [
      ...inbox,
    ]..sort((a, b) => a.sequence.compareTo(b.sequence))) {
      final prefix = '${entry.storeId}:';
      if (!entry.id.startsWith(prefix)) continue;
      final command = entry.id.substring(prefix.length);
      final event = byId[command];
      final records = jsonDecode(entry.payload) as Map<String, dynamic>;
      for (final row in records.values) {
        if (row is! Map || row['kind'] != 'stock') continue;
        final key = (
          row['warehouse'] as String,
          row['productId'] as String,
          row['quality'] as String,
        );
        final now = (row['quantity'] as int, row['value'] as int);
        final before = previous[key];
        previous[key] = now;
        if (event == null || (before == null && row['version'] != 1)) {
          missing++;
          continue;
        }
        if (!event.occurredAt.isBefore(end)) continue;
        final delta = now.$1 - (before?.$1 ?? 0),
            value = now.$2 - (before?.$2 ?? 0);
        if (delta == 0 && value == 0) continue;
        final movement = StockMovement(
          key,
          row['sku'] as String? ?? '',
          row['name'] as String? ?? key.$2,
          row['unit'] as String? ?? '',
          command,
          event.kind,
          event.occurredAt,
          delta,
          value,
        );
        final total = balances.putIfAbsent(key, () => StockPeriodRow(movement));
        if (event.occurredAt.isBefore(start)) {
          total.opening += BigInt.from(delta);
          total.openingValue += BigInt.from(value);
        } else {
          movements.add(movement);
          if (delta > 0) total.incoming += BigInt.from(delta);
          if (delta < 0) total.outgoing -= BigInt.from(delta);
          total.valueChange += BigInt.from(value);
        }
      }
    }
    return StockPeriod(
      balances.values.toList(),
      movements.reversed.toList(),
      missing,
    );
  }
}
