import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'firebase_auth_rest.dart';

/// Stores refresh credentials using the platform's secure-storage adapter.
/// The web implementation still depends on browser security and HTTPS.
class SessionVault {
  final FlutterSecureStorage storage;
  final String storeId;
  SessionVault(this.storeId, {this.storage = const FlutterSecureStorage()});
  String get _key => 'bayhai.session.$storeId';
  Future<Map<String, dynamic>?> readData(String name) async {
    final value = await storage.read(key: '$_key.$name');
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeData(String name, Map<String, dynamic> value) =>
      storage.write(key: '$_key.$name', value: jsonEncode(value));
  Future<void> write(AuthSession session) => storage.write(
    key: _key,
    value: jsonEncode({
      'uid': session.uid,
      'idToken': session.idToken,
      'refreshToken': session.refreshToken,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    }),
  );
  Future<AuthSession?> read() async {
    final encoded = await storage.read(key: _key);
    if (encoded == null) return null;
    try {
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      return AuthSession(
        uid: data['uid'] as String,
        idToken: data['idToken'] as String,
        refreshToken: data['refreshToken'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    await storage.delete(key: _key);
    await storage.delete(key: '$_key.profile');
  }
}
