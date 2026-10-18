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
  throw UnsupportedError('Настольный вход через системный браузер на этой платформе недоступен.');
}
