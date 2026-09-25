import 'api_client.dart';

class AuthSession {
  final String username;
  final String role;
  final String name;
  final String id;
  final String accountId;
  final int version;

  const AuthSession({
    required this.username,
    required this.role,
    required this.name,
    required this.id,
    this.accountId = '',
    this.version = 1,
  });

  factory AuthSession.fromApi(Map<String, dynamic> json) {
    final role = (json['role'] as String? ?? '').toLowerCase();
    if (!const {'viewer', 'admin', 'superadmin'}.contains(role)) {
      throw const ApiException('The server returned an invalid user role.', 0);
    }
    final id = json['id'];
    final accountId = json['accountId'];
    final username = json['username'];
    final name = json['name'];
    final version = json['version'];
    final status = json['status'];
    if (id is! String ||
        id.isEmpty ||
        accountId is! String ||
        accountId.isEmpty ||
        username is! String ||
        username.isEmpty ||
        name is! String ||
        name.isEmpty ||
        version is! int ||
        version < 1 ||
        status != 'ACTIVE') {
      throw const ApiException('The server returned an invalid user.', 0);
    }
    return AuthSession(
      username: username,
      role: role,
      name: name,
      id: id,
      accountId: accountId,
      version: version,
    );
  }
}

class AuthService {
  AuthService({ApiClient? api}) : _api = api ?? ApiClient.instance {
    _api.refreshAccessToken = _refreshAccessToken;
  }

  final ApiClient _api;
  Future<bool>? _refreshInProgress;
  String? lastErrorMessage;

  Future<AuthSession?> login(String username, String password) async {
    lastErrorMessage = null;
    try {
      final data = await _api.sendJson(
        'POST',
        '/auth/login',
        body: {'username': username.trim(), 'password': password},
        useIdempotencyKey: false,
        allowRefresh: false,
      ) as Map<String, dynamic>;
      final session = AuthSession.fromApi(
        data['user'] as Map<String, dynamic>,
      );
      _storeAccessToken(data);
      return session;
    } on ApiException catch (error) {
      await _clearTokensSafely();
      lastErrorMessage = error.message;
      return null;
    } catch (_) {
      await _clearTokensSafely();
      lastErrorMessage = 'The server returned an invalid login response.';
      return null;
    }
  }

  Future<AuthSession?> getSession() async {
    if (!await _refreshAccessToken()) return null;
    try {
      return await me();
    } catch (_) {
      await _clearTokens();
      return null;
    }
  }

  Future<AuthSession> me() async {
    final data = await _api.get('/auth/me') as Map<String, dynamic>;
    return AuthSession.fromApi(data);
  }

  Future<bool> _refreshAccessToken() {
    return _refreshInProgress ??= _performRefresh().whenComplete(
      () => _refreshInProgress = null,
    );
  }

  Future<bool> _performRefresh() async {
    try {
      final data = await _api.sendJson(
        'POST',
        '/auth/refresh',
        useIdempotencyKey: false,
        allowRefresh: false,
      ) as Map<String, dynamic>;
      _storeAccessToken(data);
      return true;
    } catch (_) {
      await _clearTokens();
      return false;
    }
  }

  void _storeAccessToken(Map<String, dynamic> data) {
    final accessToken = data['accessToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const ApiException(
          'The server returned an invalid access token.', 0);
    }
    _api.accessToken = accessToken;
  }

  Future<void> logout() async {
    await _api.sendJson(
      'POST',
      '/auth/logout',
      useIdempotencyKey: false,
      allowRefresh: false,
    );
    await _clearTokens();
  }

  Future<void> _clearTokens() async {
    _api.accessToken = null;
  }

  Future<void> _clearTokensSafely() async {
    _api.accessToken = null;
  }
}
