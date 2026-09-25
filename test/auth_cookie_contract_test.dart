import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warehouse_poc/services/api_client.dart';
import 'package:warehouse_poc/services/auth_service.dart';
import 'package:warehouse_poc/services/credentialed_http_client.dart';

void main() {
  test('credentialed transport exposes capability, never cookie values', () {
    final transport = CredentialedHttpClient(
      MockClient((_) async => http.Response('', 204)),
      cookiesEnabled: true,
    );

    expect(transport.cookiesEnabled, isTrue);
    expect(
      transport.runtimeType.toString().toLowerCase(),
      isNot(contains('cookiejar')),
    );
  });

  test('login ignores refresh-token response fields and stores access only',
      () async {
    late http.Request loginRequest;
    final api = ApiClient(
      httpClient: MockClient((request) async {
        loginRequest = request;
        return _dataResponse({
          'accessToken': 'access-token',
          'refreshToken': 'must-be-ignored',
          'user': _user,
        });
      }),
    );
    final auth = AuthService(api: api);

    final session = await auth.login('employee', 'password');

    expect(session?.username, 'employee');
    expect(api.accessToken, 'access-token');
    expect(jsonDecode(loginRequest.body), {
      'username': 'employee',
      'password': 'password',
    });
    expect(loginRequest.headers.containsKey('X-Client-Type'), isFalse);
  });

  test('refresh and logout send no refresh-token field', () async {
    final authBodies = <String, Map<String, dynamic>>{};
    final api = ApiClient(
      httpClient: MockClient((request) async {
        final jsonRequest = request;
        if (jsonRequest.body.isNotEmpty) {
          authBodies[request.url.path] =
              jsonDecode(jsonRequest.body) as Map<String, dynamic>;
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          return _dataResponse({'accessToken': 'access-token'});
        }
        if (request.url.path.endsWith('/auth/me')) {
          return _dataResponse(_user);
        }
        return http.Response('', 204);
      }),
    );
    final auth = AuthService(api: api);

    expect(await auth.getSession(), isNotNull);
    await auth.logout();

    expect(authBodies['/api/v1/auth/refresh'], isEmpty);
    expect(authBodies['/api/v1/auth/logout'], isEmpty);
    expect(
      authBodies.values.any((body) => body.containsKey('refreshToken')),
      isFalse,
    );
    expect(api.accessToken, isNull);
  });

  test('failed logout keeps the active session instead of claiming success',
      () async {
    final api = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'UNAVAILABLE', 'message': 'Try again.'},
            'meta': {},
          }),
          503,
        ),
      ),
    )..accessToken = 'access-token';
    final auth = AuthService(api: api);

    await expectLater(auth.logout(), throwsA(isA<ApiException>()));
    expect(api.accessToken, 'access-token');
  });

  test('concurrent expired requests share one refresh', () async {
    var refreshes = 0;
    var expiredRequests = 0;
    final bothExpired = Completer<void>();
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          await bothExpired.future;
          return _dataResponse({'accessToken': 'new-access-token'});
        }
        if (request.headers['Authorization'] == 'Bearer old-access-token') {
          expiredRequests++;
          if (expiredRequests == 2 && !bothExpired.isCompleted) {
            bothExpired.complete();
          }
          return _errorResponse('TOKEN_EXPIRED', 401);
        }
        expect(request.headers['Authorization'], 'Bearer new-access-token');
        return _dataResponse({'id': request.url.path});
      }),
    )..accessToken = 'old-access-token';
    AuthService(api: api);

    await Future.wait([
      api.get('/inventory'),
      api.get('/factories'),
    ]);

    expect(expiredRequests, 2);
    expect(refreshes, 1);
  });
}

const _user = <String, dynamic>{
  'id': 'user-id',
  'accountId': 'EMPLOYEE',
  'username': 'employee',
  'name': 'Employee',
  'role': 'VIEWER',
  'status': 'ACTIVE',
  'version': 1,
};

http.Response _dataResponse(Object? data) => http.Response(
      jsonEncode({
        'data': data,
        'meta': {'requestId': 'request-id'},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _errorResponse(String code, int status) => http.Response(
      jsonEncode({
        'error': {
          'code': code,
          'message': 'Authentication failed.',
          'retryable': false,
        },
        'meta': {'requestId': 'request-id'},
      }),
      status,
      headers: {'content-type': 'application/json'},
    );
