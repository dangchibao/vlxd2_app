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

  Future<void> clear() => storage.delete(key: _key);
}
