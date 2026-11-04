import 'dart:convert';

enum StaffRole { admin, manager, sales, warehouse, driver }

enum Operation {
  settings,
  printRequest,
  printClaim,
  printResult,
  vehicle,
  staff,
  inventoryCount,
  reservation,
  approveReservation,
  cancelReservation,
  fulfillReservation,
  quote,
  quoteToSale,
  assignDelivery,
  catalog,
  party,
  transfer,
  returnSale,
  refund,
  supplierPayment,
  purchase,
  receive,
  sale,
  payment,
  delivery,
  quarantine,
  release,
  expense,
  shiftClose,
  warranty,
  warrantyUpdate,
}

class BusinessException implements Exception {
  final String code, message;
  const BusinessException(this.code, this.message);
  @override
  String toString() => message;
}

class Actor {
  final String uid;
  final StaffRole role;
  final bool active, mustChangePassword;
  const Actor(
    this.uid,
    this.role, {
    this.active = true,
    this.mustChangePassword = false,
  });
  void require(Operation operation) {
    final allowed = switch (role) {
      StaffRole.admin => Operation.values.toSet(),
      StaffRole.manager => Operation.values.toSet()..remove(Operation.staff),
      StaffRole.sales => {
        Operation.printRequest,
        Operation.reservation,
        Operation.cancelReservation,
        Operation.fulfillReservation,
        Operation.quote,
        Operation.quoteToSale,
        Operation.party,
        Operation.sale,
        Operation.payment,
        Operation.warranty,
      },
      StaffRole.warehouse => {
        Operation.printRequest,
        Operation.catalog,
        Operation.purchase,
        Operation.receive,
        Operation.quarantine,
        Operation.warrantyUpdate,
      },
      StaffRole.driver => {Operation.delivery, Operation.printRequest},
    };
    if (!active || mustChangePassword || !allowed.contains(operation)) {
      throw const BusinessException(
        'permission',
        'Tài khoản không được phép thực hiện thao tác này.',
      );
    }
  }
}

/// Integer scale quantities: 1000 means one base unit. Money is integer VND.
/// Never use browser-unsafe integer ranges or floating point in journals.
int integerField(
  Map<String, dynamic> data,
  String key, {
  int min = 0,
  int max = 9000000000000,
}) {
  final value = data[key];
  if (value is! int || value < min || value > max) {
    throw BusinessException(
      'validation',
      '$key phải là số nguyên từ $min đến $max.',
    );
  }
  return value;
}

String textField(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.trim().isEmpty || value.length > 1000) {
    throw BusinessException('validation', 'Thiếu hoặc sai thông tin $key.');
  }
  return value.trim();
}

int roundedRatio(int amount, int numerator, int denominator) {
  if (amount < 0 || numerator < 0 || denominator <= 0) {
    throw const BusinessException('validation', 'Tỷ lệ quy đổi không hợp lệ.');
  }
  final product = BigInt.from(amount) * BigInt.from(numerator);
  final result =
      (product + BigInt.from(denominator ~/ 2)) ~/ BigInt.from(denominator);
  if (result > BigInt.from(9000000000000)) {
    throw const BusinessException('range', 'Giá trị vượt giới hạn hỗ trợ.');
  }
  return result.toInt();
}

Object? canonical(Object? value) => switch (value) {
  Map<String, dynamic>() => {
    for (final key in (value.keys.toList()..sort())) key: canonical(value[key]),
  },
  List() => value.map(canonical).toList(),
  _ => value,
};
String canonicalJson(Map<String, dynamic> value) =>
    jsonEncode(canonical(value));

class BusinessCommand {
  final String id, entityId;
  final Operation operation;
  final Map<String, dynamic> payload;
  final int expectedVersion;
  BusinessCommand({
    required this.id,
    required this.entityId,
    required this.operation,
    required Map<String, dynamic> payload,
    this.expectedVersion = 0,
  }) : payload = Map.unmodifiable(
         jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
       ) {
    if (id.isEmpty || entityId.isEmpty || expectedVersion < 0) {
      throw const BusinessException(
        'validation',
        'Định danh hoặc phiên bản chứng từ không hợp lệ.',
      );
    }
  }
  String fingerprint(String actorId) => canonicalJson({
    'actorId': actorId,
    'entityId': entityId,
    'operation': operation.name,
    'payload': payload,
    'expectedVersion': expectedVersion,
  });
}

class MaterialEstimate {
  // Inputs in mm and square millimetres; ceil to complete sale packages.
  static int tileBoxes({
    required int areaSquareMm,
    required int tileWidthMm,
    required int tileHeightMm,
    required int tilesPerBox,
    int wasteBasisPoints = 500,
  }) {
    if (areaSquareMm < 0 ||
        tileWidthMm <= 0 ||
        tileHeightMm <= 0 ||
        tilesPerBox <= 0 ||
        wasteBasisPoints < 0 ||
        wasteBasisPoints > 10000) {
      throw const BusinessException(
        'validation',
        'Quy cách vật liệu không hợp lệ.',
      );
    }
    final numerator =
        BigInt.from(areaSquareMm) * BigInt.from(10000 + wasteBasisPoints);
    final denominator =
        BigInt.from(tileWidthMm) *
        BigInt.from(tileHeightMm) *
        BigInt.from(tilesPerBox) *
        BigInt.from(10000);
    return ((numerator + denominator - BigInt.one) ~/ denominator).toInt();
  }
}
