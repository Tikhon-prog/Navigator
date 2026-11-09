/// Browser-only fallback. Android/iOS use Flutter AppAuth and Windows uses
/// the native system-browser + loopback implementation in desktop_sso_io.dart.
class DesktopSsoTokens {
  final String accessToken;
  final String idToken;

  const DesktopSsoTokens({
    required this.accessToken,
    required this.idToken,
  });
}

Future<DesktopSsoTokens> authorizeAndExchangeCode({
  required String issuer,
  required String clientId,
  required String redirectUri,
}) async {
  throw UnsupportedError(
    'Школьный вход из браузера пока не поддерживается.',
  );
}
