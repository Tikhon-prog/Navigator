import 'dart:convert';
import 'package:http/http.dart' as http;

class NavigatorApiConfig {
  final String baseUrl;
  final String clientKey;
  const NavigatorApiConfig({this.baseUrl = '', this.clientKey = ''});
  bool get enabled => baseUrl.trim().isNotEmpty;
}

class OnlineDataService {
  final NavigatorApiConfig config;
  const OnlineDataService(this.config);

  Future<Map<String, dynamic>?> get(String path) async {
    if (!config.enabled) return null;
    final uri = Uri.parse('${config.baseUrl.replaceFirst(RegExp(r'/$'), '')}/$path');
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body) async {
    if (!config.enabled) return null;
    final uri = Uri.parse('${config.baseUrl.replaceFirst(RegExp(r'/$'), '')}/$path');
    final response = await http.post(uri, headers: _headers(), body: jsonEncode(body));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Map<String, String> _headers() => {
    'Content-Type': 'application/json',
    if (config.clientKey.isNotEmpty) 'X-Navigator-Key': config.clientKey,
  };
}
