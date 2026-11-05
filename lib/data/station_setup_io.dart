import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_runtime.dart';
import 'firebase_auth_rest.dart';
import 'firestore_rest.dart';
import 'session_vault.dart';

Future<void> provisionStation() async {
  final config = AppConnection.environment();
  final password = Platform.environment['BAYHAI_STATION_SETUP_PASSWORD'];
  if (!Platform.isWindows ||
      !config.configured ||
      config.authEmulator != null ||
      config.firestoreEmulator != null ||
      password == null ||
      password.length < 20) {
    exit(2);
  }
  final client = http.Client();
  try {
    final auth = FirebaseAuthRest(client: client, apiKey: config.apiKey);
    final session = await auth.signIn(config.emailFor('tram'), password);
    final firestore = FirestoreRest(
      client: client,
      projectId: config.projectId,
    );
    final member = await firestore.get(
      'stores/${config.storeId}/members/${session.uid}',
      session,
    );
    if (member?.data['role'] != 'station' ||
        member?.data['active'] != true ||
        member?.data['mustChangePassword'] != false) {
      exit(3);
    }
    final vault = SessionVault('${config.projectId}.${config.storeId}.station');
    await vault.write(session);
    final saved = await vault.read();
    exit(saved?.uid == session.uid ? 0 : 4);
  } catch (_) {
    exit(5);
  } finally {
    client.close();
  }
}
