import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

bool get platformCookiesEnabled => Platform.isAndroid;

http.Client createPlatformHttpClient() =>
    Platform.isAndroid ? AndroidCookieHttpClient() : http.Client();

class AndroidCookieHttpClient extends http.BaseClient {
  static const _channel = MethodChannel('warehouse/http');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final response = await _channel.invokeMapMethod<String, dynamic>('send', {
      'method': request.method,
      'url': request.url.toString(),
      'headers': request.headers,
      'body': body,
    });
    if (response == null) {
      throw http.ClientException('Native HTTP returned no response.');
    }
    final headers = (response['headers'] as Map<Object?, Object?>? ?? const {})
        .map((key, value) => MapEntry(key.toString(), value.toString()));
    final bytes = response['body'] as Uint8List? ?? Uint8List(0);
    return http.StreamedResponse(
      Stream.value(bytes),
      response['statusCode'] as int,
      headers: headers,
      reasonPhrase: response['reasonPhrase'] as String?,
      request: request,
    );
  }
}
