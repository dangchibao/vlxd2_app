import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vlxd_bay_hai/data/firebase_auth_rest.dart';

void main() {
  test('Sign in uses HTTPS and keeps tokens out of diagnostics', () async {
    final client = MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'identitytoolkit.googleapis.com');
      expect(jsonDecode(request.body)['returnSecureToken'], true);
      return http.Response(
        jsonEncode({
          'localId': 'uid',
          'idToken': 'private-id',
          'refreshToken': 'private-refresh',
          'expiresIn': '3600',
        }),
        200,
      );
    });
    final session = await FirebaseAuthRest(
      client: client,
      apiKey: 'public-key',
    ).signIn('user@example.test', 'secret-value');
    expect(session.uid, 'uid');
    expect(session.toString(), isNot(contains('private')));
    client.close();
  });
  test('Server errors never reveal response tokens or passwords', () async {
    final client = MockClient(
      (_) async => http.Response('sensitive server details', 400),
    );
    try {
      await FirebaseAuthRest(
        client: client,
        apiKey: 'key',
      ).signIn('user', 'secret');
      fail('should reject');
    } catch (e) {
      expect(e, isA<AuthFailure>());
      expect('$e', isNot(contains('sensitive')));
    }
    client.close();
  });
  test('Remote HTTP emulator configuration is forbidden', () {
    final client = MockClient((_) async => http.Response('', 200));
    expect(
      () => FirebaseAuthRest(
        client: client,
        apiKey: 'key',
        emulator: Uri.parse('http://example.com:9099'),
      ),
      throwsA(isA<AuthFailure>()),
    );
    client.close();
  });
  test('Refresh rejects a response belonging to another user', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'user_id': 'different',
          'id_token': 'x',
          'refresh_token': 'y',
          'expires_in': '3600',
        }),
        200,
      ),
    );
    final session = AuthSession(
      uid: 'one',
      idToken: 'id',
      refreshToken: 'refresh',
      expiresAt: DateTime.now(),
    );
    await expectLater(
      FirebaseAuthRest(client: client, apiKey: 'key').refresh(session),
      throwsA(isA<AuthFailure>()),
    );
    client.close();
  });
}
