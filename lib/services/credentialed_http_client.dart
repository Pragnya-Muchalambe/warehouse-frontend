import 'package:http/http.dart' as http;

import 'credentialed_http_client_stub.dart'
    if (dart.library.html) 'credentialed_http_client_web.dart'
    if (dart.library.io) 'credentialed_http_client_io.dart' as platform;

class CredentialedHttpClient extends http.BaseClient {
  CredentialedHttpClient(this._delegate, {required this.cookiesEnabled});

  final http.Client _delegate;
  final bool cookiesEnabled;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _delegate.send(request);

  @override
  void close() => _delegate.close();
}

CredentialedHttpClient createCredentialedHttpClient() => CredentialedHttpClient(
      platform.createPlatformHttpClient(),
      cookiesEnabled: platform.platformCookiesEnabled,
    );
