import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/api_security.dart';
import 'package:navigator/online_data_service.dart';

void main() {
  group('API base URL security', () {
    test('allows HTTPS for remote servers', () {
      expect(isSecureApiBaseUrl('https://api.example.org/navigator'), isTrue);
    });

    test('rejects all cleartext HTTP endpoints', () {
      expect(isSecureApiBaseUrl('http://localhost:8000/api'), isFalse);
      expect(isSecureApiBaseUrl('http://127.0.0.1:8000/api'), isFalse);
      expect(isSecureApiBaseUrl('http://api.example.org/api'), isFalse);
    });

    test('rejects unsupported schemes, credentials and query strings', () {
      expect(isSecureApiBaseUrl('ftp://api.example.org/data'), isFalse);
      expect(isSecureApiBaseUrl('https://user:pass@api.example.org/api'), isFalse);
      expect(isSecureApiBaseUrl('https://api.example.org/api?token=abc'), isFalse);
      expect(isSecureApiBaseUrl('https://api.example.org/api#fragment'), isFalse);
    });

    test('invalid remote HTTP configuration is not enabled', () {
      expect(
        const NavigatorApiConfig(baseUrl: 'http://api.example.org').enabled,
        isFalse,
      );
    });
  });
}
