import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import '../domain/operations.dart';
import 'database.dart';

class BackupPreview {
  final Map<String, dynamic> snapshot;
  final String currentHash;
  final String snapshotHash;
  final int rows;
  const BackupPreview._(
    this.snapshot,
    this.currentHash,
    this.rows,
    this.snapshotHash,
  );
}

class BackupService {
  final AppDatabase db;
  final String storeId, userId;
  BackupService(this.db, {required this.storeId, required this.userId});
  Object? _encode(Object? value) =>
      value is Uint8List ? {'binary': base64Encode(value)} : value;
  Object? _decode(Object? value) {
    if (value is Map<String, dynamic> &&
        value.length == 1 &&
        value['binary'] is String) {
      return base64Decode(value['binary'] as String);
    }
    if (value == null || value is String || value is int || value is double) {
      return value;
    }
    throw const FormatException('Kiểu dữ liệu sao lưu không hợp lệ.');
  }

  String _hash(Map<String, dynamic> value) =>
      hash.sha256.convert(utf8.encode(canonicalJson(value))).toString();
  Future<Map<String, dynamic>> _capture() => db.transaction(() async {
    final tables = <String, dynamic>{};
    for (final table in db.allTables) {
      final order = table.$primaryKey.map((c) => '"${c.$name}"').join(',');
      final rows = await db
          .customSelect(
            'SELECT * FROM "${table.actualTableName}"${order.isEmpty ? '' : ' ORDER BY $order'}',
          )
          .get();
      tables[table.actualTableName] = [
        for (final row in rows) row.data.map((k, v) => MapEntry(k, _encode(v))),
      ];
    }
    return {
      'format': 'bayhai-backup',
      'schema': db.schemaVersion,
      'storeId': storeId,
      'userId': userId,
      'tables': tables,
    };
  });
  Future<Uint8List> create(String password) async {
    if (password.length < 10) {
      throw const FormatException('Mật khẩu bản sao cần ít nhất 10 ký tự.');
    }
    final integrity = await db
        .customSelect('PRAGMA integrity_check')
        .getSingle();
    if (integrity.data.values.single != 'ok') {
      throw const FormatException('Database chưa đạt kiểm tra toàn vẹn.');
    }
    final snapshot = await _capture(), cipher = AesGcm.with256bits();
    final salt = await cipher.newSecretKey();
    final saltBytes = await salt.extractBytes();
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: saltBytes);
    final box = await cipher.encrypt(
      utf8.encode(
        canonicalJson({
          'snapshot': snapshot,
          'sha256': _hash(snapshot),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
      secretKey: key,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'bayhai-encrypted-v1',
          'salt': base64Encode(saltBytes),
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
  }

  Future<BackupPreview> preview(Uint8List bytes, String password) async {
    if (bytes.length > 100 * 1024 * 1024) {
      throw const FormatException('Bản sao vượt giới hạn 100 MB.');
    }
    Map<String, dynamic> body;
    try {
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (envelope['format'] != 'bayhai-encrypted-v1') {
        throw const FormatException();
      }
      final key =
          await Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: 120000,
            bits: 256,
          ).deriveKey(
            secretKey: SecretKey(utf8.encode(password)),
            nonce: base64Decode(envelope['salt'] as String),
          );
      final plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(envelope['ciphertext'] as String),
          nonce: base64Decode(envelope['nonce'] as String),
          mac: Mac(base64Decode(envelope['mac'] as String)),
        ),
        secretKey: key,
      );
      body = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Sai mật khẩu hoặc bản sao đã bị hỏng.');
    }
    final snapshot = body['snapshot'] as Map<String, dynamic>;
    if (body['sha256'] != _hash(snapshot)) {
      throw const FormatException('Checksum bản sao không khớp.');
    }
    if (snapshot['schema'] != db.schemaVersion ||
        snapshot['storeId'] != storeId ||
        snapshot['userId'] != userId) {
      throw const FormatException(
        'Bản sao khác cửa hàng, tài khoản hoặc phiên bản database.',
      );
    }
    final tables = snapshot['tables'] as Map<String, dynamic>;
    final known = {
      for (final table in db.allTables) table.actualTableName: table,
    };
    if (tables.length != known.length ||
        !known.keys.every(tables.containsKey)) {
      throw const FormatException('Danh sách bảng không hợp lệ.');
    }
    var count = 0;
    for (final entry in tables.entries) {
      final columns = known[entry.key]!.$columns.map((c) => c.$name).toSet();
      if (entry.value is! List) {
        throw const FormatException('Dữ liệu bảng không hợp lệ.');
      }
      for (final row in entry.value as List) {
        if (row is! Map<String, dynamic> ||
            row.keys.toSet().difference(columns).isNotEmpty ||
            row.length != columns.length) {
          throw const FormatException('Schema dòng dữ liệu không khớp.');
        }
        for (final value in row.values) {
          _decode(value);
        }
        count++;
      }
    }
    return BackupPreview._(
      snapshot,
      _hash(await _capture()),
      count,
      _hash(snapshot),
    );
  }

  Future<void> restore(
    BackupPreview approved, {
    required bool acknowledged,
  }) async {
    if (!acknowledged) {
      throw const BusinessException(
        'approval',
        'Cần xác nhận khôi phục dữ liệu cục bộ.',
      );
    }
    await db.transaction(() async {
      if (_hash(approved.snapshot) != approved.snapshotHash) {
        throw const FormatException('Bản xem trước đã bị thay đổi.');
      }
      if (_hash(await _capture()) != approved.currentHash) {
        throw const BusinessException(
          'conflict',
          'Dữ liệu đã thay đổi sau khi xem trước. Hãy kiểm tra lại bản sao.',
        );
      }
      final tables = approved.snapshot['tables'] as Map<String, dynamic>;
      for (final table in db.allTables.toList().reversed) {
        await db.customStatement('DELETE FROM "${table.actualTableName}"');
      }
      for (final table in db.allTables) {
        for (final row in tables[table.actualTableName] as List) {
          final values = row as Map<String, dynamic>;
          final columns = values.keys.map((c) => '"$c"').join(',');
          await db.customStatement(
            'INSERT INTO "${table.actualTableName}" ($columns) VALUES (${List.filled(values.length, '?').join(',')})',
            values.values.map(_decode).toList(),
          );
        }
      }
      final foreign = await db.customSelect('PRAGMA foreign_key_check').get();
      final integrity = await db
          .customSelect('PRAGMA integrity_check')
          .getSingle();
      if (foreign.isNotEmpty || integrity.data.values.single != 'ok') {
        throw const FormatException('Khôi phục không đạt kiểm tra toàn vẹn.');
      }
      for (final table in db.allTables) {
        db.markTablesUpdated({table});
      }
    });
    // Only local rows were restored. No cloud snapshot is ever uploaded here.
    // Pending immutable commands reconcile against remote receipts during sync.
  }
}
