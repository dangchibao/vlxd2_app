import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

class AuthSession {
  final String uid, idToken, refreshToken;
  final DateTime expiresAt;
  const AuthSession({
    required this.uid,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  // Do not include tokens in toString, diagnostics or exception messages.
  @override
  String toString() => 'AuthSession(expiresAt: $expiresAt)';
}

/// REST adapter works independently of unsupported FlutterFire Windows SDKs.
/// Caller supplies verified store username mapping, never an arbitrary email
/// from a public directory. Transport defaults to official HTTPS endpoints.
class FirebaseAuthRest {
  final http.Client client;
  final String apiKey;
  final Uri? emulator;
  FirebaseAuthRest({
    required this.client,
    required this.apiKey,
    this.emulator,
  }) {
    if (emulator != null &&
        (!{'127.0.0.1', 'localhost', '::1'}.contains(emulator!.host) ||
            emulator!.scheme != 'http')) {
      throw const AuthFailure('Emulator chỉ được dùng tại localhost.');
    }
  }
  Uri _identity(String action) => emulator == null
      ? Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:$action', {
          'key': apiKey,
        })
      : emulator!.replace(
          path: '/identitytoolkit.googleapis.com/v1/accounts:$action',
          queryParameters: {'key': apiKey},
        );
  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) async {
    try {
      final response = await client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const AuthFailure(
          'Không xác thực được. Kiểm tra tài khoản, mật khẩu hoặc quyền truy cập.',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Không kết nối được dịch vụ xác thực.');
    }
  }

  AuthSession _session(Map<String, dynamic> data, {String? uid}) {
    final seconds = int.tryParse('${data['expiresIn']}');
    if (seconds == null ||
        seconds <= 0 ||
        data['idToken'] is! String ||
        data['refreshToken'] is! String ||
        (uid ?? data['localId']) is! String) {
      throw const AuthFailure('Phản hồi xác thực không hợp lệ.');
    }
    return AuthSession(
      uid: uid ?? data['localId'] as String,
      idToken: data['idToken'] as String,
      refreshToken: data['refreshToken'] as String,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
    );
  }

  Future<AuthSession> signIn(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthFailure('Vui lòng nhập tài khoản và mật khẩu.');
    }
    return _session(
      await _post(_identity('signInWithPassword'), {
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );
  }

  Future<AuthSession> changePassword(
    AuthSession session,
    String newPassword,
  ) async {
    if (newPassword.length < 10) {
      throw const AuthFailure('Mật khẩu mới cần ít nhất 10 ký tự.');
    }
    return _session(
      await _post(_identity('update'), {
        'idToken': session.idToken,
        'password': newPassword,
        'returnSecureToken': true,
      }),
      uid: session.uid,
    );
  }

  Future<AuthSession> refresh(AuthSession session) async {
    final uri = emulator == null
        ? Uri.https('securetoken.googleapis.com', '/v1/token', {'key': apiKey})
        : emulator!.replace(
            path: '/securetoken.googleapis.com/v1/token',
            queryParameters: {'key': apiKey},
          );
    try {
      final response = await client
          .post(
            uri,
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': session.refreshToken,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const AuthFailure(
          'Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['user_id'] != session.uid) {
        throw const AuthFailure('Phiên xác thực không khớp tài khoản.');
      }
      return _session({
        'idToken': data['id_token'],
        'refreshToken': data['refresh_token'],
        'expiresIn': data['expires_in'],
      }, uid: session.uid);
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure('Không thể gia hạn phiên đăng nhập.');
    }
  }
}
