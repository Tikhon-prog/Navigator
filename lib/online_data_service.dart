import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_security.dart';

class NavigatorApiConfig {
  final String baseUrl;
  /// This is a public client identifier, not a secret or an authorization token.
  final String clientKey;

  const NavigatorApiConfig({this.baseUrl = '', this.clientKey = ''});

  bool get enabled => baseUrl.trim().isNotEmpty && isSecureApiBaseUrl(baseUrl);
}

class OnlineDataService {
  final NavigatorApiConfig config;
  const OnlineDataService(this.config);

  Uri? _uriFor(String path) {
    if (!config.enabled) return null;
    final cleanPath = path.trim().replaceFirst(RegExp(r'^/+'), '');
    if (cleanPath.isEmpty || cleanPath.split('/').contains('..')) return null;

    final base = Uri.parse(config.baseUrl.trim());
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    return base.replace(path: '$basePath/$cleanPath');
  }

  Future<Map<String, dynamic>?> get(String path) async {
    final uri = _uriFor(path);
    if (uri == null) return null;

    try {
      final response = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uriFor(path);
    if (uri == null) return null;

    try {
      final response = await http
          .post(uri, headers: _headers(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (config.clientKey.isNotEmpty) 'X-Navigator-Key': config.clientKey,
      };
}
