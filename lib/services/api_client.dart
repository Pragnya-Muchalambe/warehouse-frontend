import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import 'credentialed_http_client.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? code;
  final bool retryable;
  final List<ApiErrorDetail> details;
  final String? requestId;
  final Duration? retryAfter;
  final String? etag;

  const ApiException(
    this.message,
    this.statusCode, {
    this.code,
    this.retryable = false,
    this.details = const [],
    this.requestId,
    this.retryAfter,
    this.etag,
  });

  bool get isVersionConflict => statusCode == 412 || code == 'VERSION_CONFLICT';

  @override
  String toString() => message;
}

class ApiErrorDetail {
  final String? field;
  final String? code;
  final String message;

  const ApiErrorDetail({this.field, this.code, required this.message});
}

class ApiPage<T> {
  final List<T> data;
  final int limit;
  final String? nextCursor;
  final bool hasMore;
  final String? requestId;

  const ApiPage({
    required this.data,
    required this.limit,
    required this.nextCursor,
    required this.hasMore,
    this.requestId,
  });
}

class ApiClient {
  ApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? createCredentialedHttpClient();

  static final instance = ApiClient();
  static const _uuid = Uuid();
  static const String _configuredBaseUrl = String.fromEnvironment(
    'WAREHOUSE_API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  final http.Client _httpClient;
  final Map<String, String> _pendingIdempotencyKeys = {};
  static const _requestTimeout = Duration(seconds: 30);
  String? accessToken;
  Future<bool> Function()? refreshAccessToken;

  String get _baseUrl {
    final base = _configuredBaseUrl.replaceFirst(RegExp(r'/$'), '');
    return base.endsWith('/api/v1') ? base : '$base/api/v1';
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers({String? idempotencyKey, int? version}) => {
        'Accept': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        if (version != null) 'If-Match': '"$version"',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    return _withRefresh(
      () => _httpClient.get(_uri(path, query), headers: _headers()),
      _decodeData,
    );
  }

  Future<List<dynamic>> getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    final values = <dynamic>[];
    String? cursor;
    final seenCursors = <String>{};
    do {
      final page = await getPage(path, query: query, cursor: cursor);
      values.addAll(page.data);
      cursor = page.hasMore ? page.nextCursor : null;
      if (page.hasMore && (cursor == null || !seenCursors.add(cursor))) {
        throw const ApiException(
          'The server returned invalid pagination metadata.',
          0,
        );
      }
    } while (cursor != null);
    return values;
  }

  Future<ApiPage<dynamic>> getPage(
    String path, {
    Map<String, String>? query,
    String? cursor,
  }) async {
    final parameters = <String, String>{
      ...?query,
      'limit': query?['limit'] ?? '100',
      if (cursor != null) 'cursor': cursor,
    };
    final envelope = await _withRefresh(
      () => _httpClient.get(_uri(path, parameters), headers: _headers()),
      _decodeEnvelope,
    );
    final data = envelope['data'];
    final page = envelope['page'];
    final meta = envelope['meta'];
    if (data is! List || page is! Map<String, dynamic>) {
      throw const ApiException('The server returned an invalid collection.', 0);
    }
    return ApiPage<dynamic>(
      data: data,
      limit: (page['limit'] as num?)?.toInt() ?? data.length,
      nextCursor:
          page['nextCursor'] is String ? page['nextCursor'] as String : null,
      hasMore: page['hasMore'] == true,
      requestId:
          meta is Map<String, dynamic> ? meta['requestId'] as String? : null,
    );
  }

  Future<dynamic> sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int? version,
    bool useIdempotencyKey = true,
    bool allowRefresh = true,
  }) async {
    final operationSignature =
        '$method|$path|$version|${jsonEncode(body ?? const <String, dynamic>{})}';
    final idempotencyKey = useIdempotencyKey
        ? _pendingIdempotencyKeys.putIfAbsent(operationSignature, _uuid.v4)
        : null;
    Future<http.Response> send() async {
      final request = http.Request(method, _uri(path));
      request.headers.addAll(
        _headers(idempotencyKey: idempotencyKey, version: version),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body ?? const <String, dynamic>{});
      return http.Response.fromStream(await _httpClient.send(request));
    }

    try {
      final result = await _withRefresh(
        send,
        _decodeData,
        allowRefresh: allowRefresh,
      );
      _pendingIdempotencyKeys.remove(operationSignature);
      return result;
    } on ApiException catch (error) {
      if (error.statusCode != 0 || !error.retryable) {
        _pendingIdempotencyKeys.remove(operationSignature);
      }
      rethrow;
    }
  }

  Future<String> uploadFile({
    required String purpose,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const ApiException('The selected file is empty.', 0);
    }
    if (bytes.lengthInBytes > 10 * 1024 * 1024) {
      throw const ApiException('Files must be 10 MB or smaller.', 0);
    }
    final contentType = _contentType(fileName, bytes);
    final idempotencyKey = _uuid.v4();
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', _uri('/files'));
      request.headers.addAll(_headers(idempotencyKey: idempotencyKey));
      request.fields['purpose'] = purpose;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: contentType,
        ),
      );
      return http.Response.fromStream(await _httpClient.send(request));
    }

    final data = await _withRefresh(send, _decodeData);
    if (data is! Map<String, dynamic> || data['id'] is! String) {
      throw const ApiException('The file upload response is invalid.', 0);
    }
    return data['id'] as String;
  }

  Future<Uint8List> downloadFile(String fileId) async {
    return _withRefresh(
      () => _httpClient.get(
        _uri('/files/${Uri.encodeComponent(fileId)}/content'),
        headers: {
          ..._headers(),
          'Accept': '*/*',
        },
      ),
      (response) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
        _decodeEnvelope(response);
        throw ApiException('Unable to download the file.', response.statusCode);
      },
    );
  }

  MediaType _contentType(String fileName, Uint8List bytes) {
    final extension = fileName.toLowerCase().split('.').last;
    final signatureMatches = switch (extension) {
      'pdf' => _startsWith(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2d]),
      'jpg' || 'jpeg' => bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff,
      'png' => _startsWith(
          bytes,
          const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
        ),
      'webp' => bytes.length >= 12 &&
          _startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50,
      _ => false,
    };
    if (!signatureMatches) {
      throw const ApiException(
        'Only valid PDF, JPEG, PNG, and WebP files are supported.',
        0,
      );
    }
    return switch (extension) {
      'pdf' => MediaType('application', 'pdf'),
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      _ => throw StateError('Unsupported file extension'),
    };
  }

  bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  Future<T> _withRefresh<T>(
    Future<http.Response> Function() send,
    T Function(http.Response) decode, {
    bool allowRefresh = true,
  }) async {
    try {
      var response = await send().timeout(_requestTimeout);
      if (allowRefresh &&
          _isTokenExpired(response) &&
          refreshAccessToken != null) {
        final refreshed = await refreshAccessToken!();
        if (refreshed) response = await send().timeout(_requestTimeout);
      }
      return decode(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.', 0,
          retryable: true);
    } on http.ClientException {
      throw const ApiException('Unable to connect to the server.', 0,
          retryable: true);
    } on FormatException {
      throw const ApiException('The server returned an invalid response.', 0);
    } on TypeError {
      throw const ApiException('The server returned an invalid response.', 0);
    } catch (_) {
      throw const ApiException('Unable to complete the request.', 0,
          retryable: false);
    }
  }

  bool _isTokenExpired(http.Response response) {
    if (response.statusCode != 401) return false;
    try {
      final envelope = jsonDecode(response.body) as Map<String, dynamic>;
      final error = envelope['error'];
      return error is Map<String, dynamic> && error['code'] == 'TOKEN_EXPIRED';
    } catch (_) {
      return false;
    }
  }

  dynamic _decodeData(http.Response response) {
    if (response.statusCode == 204) return null;
    final envelope = _decodeEnvelope(response);
    if (!envelope.containsKey('data')) {
      throw ApiException(
          'The server response is missing data.', response.statusCode);
    }
    return envelope['data'];
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
          'The server returned an invalid response.', response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorValue = envelope['error'];
      final error = errorValue is Map<String, dynamic> ? errorValue : null;
      final metaValue = envelope['meta'];
      final meta = metaValue is Map<String, dynamic> ? metaValue : null;
      final detailsValue = error?['details'];
      final details = detailsValue is List
          ? detailsValue.whereType<Map<String, dynamic>>().map((detail) {
              return ApiErrorDetail(
                field: detail['field'] as String?,
                code: detail['code'] as String?,
                message: detail['message'] as String? ?? 'Invalid value.',
              );
            }).toList()
          : const <ApiErrorDetail>[];
      final retryAfterSeconds = int.tryParse(
        response.headers['retry-after'] ?? '',
      );
      throw ApiException(
        error?['message'] as String? ?? 'Request failed.',
        response.statusCode,
        code: error?['code'] as String?,
        retryable: error?['retryable'] as bool? ?? false,
        details: details,
        requestId: meta?['requestId'] as String?,
        retryAfter: retryAfterSeconds == null
            ? null
            : Duration(seconds: retryAfterSeconds),
        etag: response.headers['etag'],
      );
    }
    return envelope;
  }
}
