import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

bool get platformCookiesEnabled => true;

http.Client createPlatformHttpClient() =>
    BrowserClient()..withCredentials = true;
