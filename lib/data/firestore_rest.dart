import 'dart:convert';

import 'package:http/http.dart' as http;

import 'firebase_auth_rest.dart';

class FirestoreFailure implements Exception {
  final int status;
  const FirestoreFailure(this.status);
  bool get retryable => {409, 429, 500, 502, 503, 504}.contains(status);
  @override
  String toString() => 'Không xử lý được dữ liệu đồng bộ (mã $status).';
}

class RemoteDocument {
  final String name;
  final Map<String, dynamic> data;
  final String? updateTime;
  final Map<String, dynamic> rawFields;
  const RemoteDocument(
    this.name,
    this.data,
    this.updateTime, {
    this.rawFields = const {},
  });
}

class FirestoreRest {
  final http.Client client;
  final String projectId;
  final Uri? emulator;
  FirestoreRest({
    required this.client,
    required this.projectId,
    this.emulator,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9-]{4,62}$').hasMatch(projectId)) {
      throw ArgumentError('Project ID không hợp lệ.');
    }
    if (emulator != null &&
        (emulator!.scheme != 'http' ||
            !{'localhost', '127.0.0.1', '::1'}.contains(emulator!.host) ||
            !projectId.startsWith('demo-'))) {
      throw ArgumentError(
        'Emulator yêu cầu project demo và địa chỉ localhost.',
      );
    }
  }
  String get root => 'projects/$projectId/databases/(default)/documents';
  Future<List<RemoteDocument>> query(
    String parent,
    Map<String, dynamic> structuredQuery,
    AuthSession session,
  ) async {
    try {
      final response = await client
          .post(
            _uri('${name(parent)}:runQuery'),
            headers: {
              'Authorization': 'Bearer ${session.idToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'structuredQuery': structuredQuery}),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw FirestoreFailure(response.statusCode);
      }
      final body = jsonDecode(response.body);
      final rows = body is List ? body : [body];
      return [
        for (final row in rows)
          if (row['document'] is Map<String, dynamic>)
            RemoteDocument(
              row['document']['name'] as String,
              decodeFields(
                row['document']['fields'] as Map<String, dynamic>? ?? {},
              ),
              row['document']['updateTime'] as String?,
              rawFields:
                  row['document']['fields'] as Map<String, dynamic>? ?? {},
            ),
      ];
    } on FirestoreFailure {
      rethrow;
    } catch (_) {
      throw const FirestoreFailure(503);
    }
  }

  String name(String relative) {
    final segments = relative.split('/');
    if (segments.length.isOdd ||
        segments.any(
          (s) =>
              s.isEmpty || s == '.' || s == '..' || s.contains(RegExp(r'[?#]')),
        )) {
      throw ArgumentError('Đường dẫn chứng từ không hợp lệ.');
    }
    return '$root/$relative';
  }

  Uri _uri(String path, [Map<String, String>? query]) => emulator == null
      ? Uri.https('firestore.googleapis.com', '/v1/$path', query)
      : emulator!.replace(path: '/v1/$path', queryParameters: query);
  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    AuthSession session, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    try {
      final request = http.Request(method, _uri(path, query))
        ..headers.addAll({
          'Authorization': 'Bearer ${session.idToken}',
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 25)),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirestoreFailure(response.statusCode);
      }
      return response.body.isEmpty
          ? {}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } on FirestoreFailure {
      rethrow;
    } catch (_) {
      throw const FirestoreFailure(503);
    }
  }

  Future<RemoteDocument?> _transactionGet(
    String relative,
    AuthSession session,
    String transaction,
  ) async {
    try {
      final response = await client
          .post(
            _uri('$root:batchGet'),
            headers: {
              'Authorization': 'Bearer ${session.idToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'documents': [name(relative)],
              'transaction': transaction,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw FirestoreFailure(response.statusCode);
      }
      final decoded = jsonDecode(response.body);
      final rows = decoded is List ? decoded : [decoded];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) throw const FirestoreFailure(502);
        final found = row['found'];
        if (found is Map<String, dynamic>) {
          return RemoteDocument(
            found['name'] as String,
            decodeFields(found['fields'] as Map<String, dynamic>? ?? {}),
            found['updateTime'] as String?,
          );
        }
        if (row['missing'] != null) return null;
      }
      throw const FirestoreFailure(502);
    } on FirestoreFailure {
      rethrow;
    } catch (_) {
      throw const FirestoreFailure(503);
    }
  }

  Future<RemoteDocument?> get(
    String relative,
    AuthSession session, {
    String? transaction,
  }) async {
    if (transaction != null) {
      return _transactionGet(relative, session, transaction);
    }
    try {
      final doc = await _request(
        'GET',
        name(relative),
        session,
        query: transaction == null ? null : {'transaction': transaction},
      );
      return RemoteDocument(
        doc['name'] as String,
        decodeFields(doc['fields'] as Map<String, dynamic>? ?? {}),
        doc['updateTime'] as String?,
      );
    } on FirestoreFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<String> begin(AuthSession session) async =>
      (await _request(
            'POST',
            '$root:beginTransaction',
            session,
            body: {
              'options': {'readWrite': {}},
            },
          ))['transaction']
          as String;
  Future<void> commit(
    AuthSession session,
    List<Map<String, dynamic>> writes, {
    String? transaction,
  }) async {
    await _request(
      'POST',
      '$root:commit',
      session,
      body: {'writes': writes, 'transaction': ?transaction},
    );
  }

  Future<void> rollback(AuthSession session, String transaction) async {
    await _request(
      'POST',
      '$root:rollback',
      session,
      body: {'transaction': transaction},
    );
  }

  Map<String, dynamic> createWrite(
    String relative,
    Map<String, dynamic> value,
  ) => {
    'update': {'name': name(relative), 'fields': encodeFields(value)},
    'currentDocument': {'exists': false},
  };
  Map<String, dynamic> updateWrite(
    RemoteDocument doc,
    Map<String, dynamic> value,
  ) {
    if (doc.updateTime == null || !doc.name.startsWith('$root/')) {
      throw ArgumentError('Thiếu phiên bản tài liệu.');
    }
    return {
      'update': {'name': doc.name, 'fields': encodeFields(value)},
      'currentDocument': {'updateTime': doc.updateTime},
    };
  }

  static Map<String, dynamic> encodeFields(Map<String, dynamic> fields) =>
      fields.map((k, v) => MapEntry(k, _encode(v)));
  static Map<String, dynamic> _encode(Object? value) => switch (value) {
    null => {'nullValue': null},
    bool() => {'booleanValue': value},
    String() => {'stringValue': value},
    int() => {'integerValue': '$value'},
    DateTime() => {'timestampValue': value.toUtc().toIso8601String()},
    Map<String, dynamic>() => {
      'mapValue': {'fields': encodeFields(value)},
    },
    List() => {
      'arrayValue': {'values': value.map(_encode).toList()},
    },
    _ => throw ArgumentError(
      'Kiểu dữ liệu Firestore không được hỗ trợ; không dùng số thực cho tiền.',
    ),
  };
  static Map<String, dynamic> decodeFields(Map<String, dynamic> fields) =>
      fields.map((k, v) => MapEntry(k, _decode(v as Map<String, dynamic>)));
  static Object? _decode(Map<String, dynamic> value) {
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('integerValue')) {
      final n = BigInt.parse('${value['integerValue']}');
      if (n.abs() > BigInt.from(9000000000000000)) {
        throw const FormatException('Số nguyên vượt giới hạn');
      }
      return n.toInt();
    }
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('timestampValue')) {
      return DateTime.parse(value['timestampValue'] as String);
    }
    if (value.containsKey('mapValue')) {
      return decodeFields(
        (value['mapValue'] as Map<String, dynamic>)['fields']
                as Map<String, dynamic>? ??
            {},
      );
    }
    if (value.containsKey('arrayValue')) {
      return ((value['arrayValue'] as Map<String, dynamic>)['values']
                  as List? ??
              [])
          .map((v) => _decode(v as Map<String, dynamic>))
          .toList();
    }
    throw const FormatException('Giá trị Firestore chưa hỗ trợ');
  }
}
