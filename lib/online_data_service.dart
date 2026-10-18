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
    var basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    // Accept a site root, legacy API root (/api), or the versioned API root
    // (/api/v2) while keeping these workbook reads on the public /api routes.
    if (basePath.endsWith('/api/v2')) {
      basePath = basePath.substring(0, basePath.length - '/api/v2'.length);
    }
    if (!basePath.endsWith('/api')) {
      basePath = '$basePath/api';
    }
    final relativePath = cleanPath.startsWith('api/')
        ? cleanPath.substring('api/'.length)
        : cleanPath;
    return base.replace(path: '$basePath/$relativePath', query: null, fragment: '', userInfo: '');
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
