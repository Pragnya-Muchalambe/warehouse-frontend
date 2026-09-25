import 'package:http/http.dart' as http;

bool get platformCookiesEnabled => false;

http.Client createPlatformHttpClient() => http.Client();
