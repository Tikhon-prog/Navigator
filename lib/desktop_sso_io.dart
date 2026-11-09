import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Tokens returned by a native Windows OIDC authorization-code flow.
/// The backend verifies the ID-token signature and the school's UserInfo
/// response before issuing a local school session.
class DesktopSsoTokens {
  final String accessToken;
  final String idToken;

  const DesktopSsoTokens({
    required this.accessToken,
    required this.idToken,
  });
}

/// Runs Authorization Code + PKCE using the system browser and a loopback
/// redirect registered with the school's identity provider.
Future<DesktopSsoTokens> authorizeAndExchangeCode({
  required String issuer,
  required String clientId,
  required String redirectUri,
}) async {
  final issuerUri = Uri.tryParse(issuer.trim());
  if (issuerUri == null ||
      issuerUri.scheme != 'https' ||
      issuerUri.host.isEmpty ||
      issuerUri.userInfo.isNotEmpty ||
      issuerUri.hasFragment) {
    throw const FormatException('Адрес школьного OIDC должен быть корректным HTTPS URL.');
  }
  if (clientId.trim().isEmpty) {
    throw const FormatException('Не задан client_id школьного OIDC.');
  }

  final callbackBase = Uri.tryParse(redirectUri.trim());
  if (callbackBase == null ||
      callbackBase.scheme != 'http' ||
      callbackBase.host != '127.0.0.1' ||
      callbackBase.port < 1 ||
      callbackBase.path.isEmpty ||
      callbackBase.hasQuery ||
      callbackBase.hasFragment ||
      callbackBase.userInfo.isNotEmpty) {
    throw const FormatException(
      'Для Windows настрой NAVIGATOR_OIDC_DESKTOP_REDIRECT_URI как '
      'http://127.0.0.1:43827/oauth/callback и зарегистрируй его у школьного OIDC-провайдера.',
    );
  }

  final discoveryUri = Uri.parse(
    '${issuer.replaceFirst(RegExp(r'/+$'), '')}/.well-known/openid-configuration',
  );
  final discoveryResponse = await http
      .get(discoveryUri, headers: const {'Accept': 'application/json'})
      .timeout(const Duration(seconds: 10));
  if (discoveryResponse.statusCode != 200) {
    throw Exception('Не удалось получить OIDC discovery (HTTP ${discoveryResponse.statusCode}).');
  }

  final dynamic discoveryPayload = jsonDecode(discoveryResponse.body);
  if (discoveryPayload is! Map<String, dynamic> ||
      discoveryPayload['issuer']?.toString() != issuer) {
    throw const FormatException('OIDC discovery не совпадает с настроенным issuer.');
  }
  final authorizationEndpoint = _secureEndpoint(discoveryPayload['authorization_endpoint'], 'authorization_endpoint');
  final tokenEndpoint = _secureEndpoint(discoveryPayload['token_endpoint'], 'token_endpoint');

  final verifier = _randomUrlSafe(48);
  final state = _randomUrlSafe(32);
  final nonce = _randomUrlSafe(32);
  final challenge = base64Url.encode(
    crypto.sha256.convert(utf8.encode(verifier)).bytes,
  ).replaceAll('=', '');

  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    callbackBase.port,
    shared: false,
  );
  final callbackCompleter = Completer<Uri>();
  final serverSubscription = server.listen((request) async {
    if (request.uri.path != callbackBase.path || request.method != 'GET') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><html><meta charset="utf-8"><title>Поколение</title>'
        '<body><h2>Поколение</h2><p>Неверный адрес возврата. Вернитесь в приложение.</p></body></html>',
      );
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.html;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    request.response.write(
      '<!doctype html><html lang="ru"><meta charset="utf-8">'
      '<title>Поколение — вход</title><body>'
      '<h2>Поколение</h2><p>Ответ получен. Вернитесь в приложение «Поколение».</p>'
      '</body></html>',
    );
    await request.response.close();
    if (!callbackCompleter.isCompleted) {
      callbackCompleter.complete(request.uri);
    }
  });

  try {
    final authUri = authorizationEndpoint.replace(
      queryParameters: {
        ...authorizationEndpoint.queryParameters,
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': callbackBase.toString(),
        'scope': 'openid profile email',
        'state': state,
        'nonce': nonce,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );
    await _openSystemBrowser(authUri);

    final callback = await callbackCompleter.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw TimeoutException(
        'Время ожидания школьного входа истекло. Попробуй войти ещё раз.',
      ),
    );
    if (callback.queryParameters['state'] != state) {
      throw const FormatException('OIDC state не совпал; вход отменён для безопасности.');
    }
    final providerError = callback.queryParameters['error'];
    if (providerError != null && providerError.isNotEmpty) {
      throw Exception('Школьный провайдер отклонил вход: $providerError.');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const FormatException('Школьный провайдер не вернул authorization code.');
    }

    final tokenResponse = await http
        .post(
          tokenEndpoint,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'grant_type': 'authorization_code',
            'client_id': clientId,
            'redirect_uri': callbackBase.toString(),
            'code': code,
            'code_verifier': verifier,
          },
        )
        .timeout(const Duration(seconds: 12));
    if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
      throw Exception('OIDC token exchange завершился ошибкой (HTTP ${tokenResponse.statusCode}).');
    }
    final dynamic tokenPayload = jsonDecode(tokenResponse.body);
    if (tokenPayload is! Map ||
        tokenPayload['access_token'] is! String ||
        tokenPayload['id_token'] is! String) {
      throw const FormatException('OIDC token endpoint не вернул access_token и id_token.');
    }
    final accessToken = (tokenPayload['access_token'] as String).trim();
    final idToken = (tokenPayload['id_token'] as String).trim();
    if (accessToken.isEmpty || idToken.isEmpty) {
      throw const FormatException('OIDC вернул пустые токены.');
    }

    // Parse nonce only as a consistency check. Trust is established by the
    // backend, which validates the ID-token signature, issuer, audience and
    // expiry using the configured OIDC signing keys.
    final jwtParts = idToken.split('.');
    if (jwtParts.length != 3) {
      throw const FormatException('OIDC вернул ID token неизвестного формата.');
    }
    final dynamic claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(jwtParts[1]))),
    );
    if (claims is! Map || claims['nonce'] != nonce) {
      throw const FormatException('OIDC nonce не совпал; вход отменён для безопасности.');
    }

    return DesktopSsoTokens(accessToken: accessToken, idToken: idToken);
  } finally {
    await serverSubscription.cancel();
    await server.close(force: true);
  }
}

Uri _secureEndpoint(dynamic raw, String label) {
  final uri = Uri.tryParse(raw?.toString() ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw FormatException('OIDC $label должен использовать HTTPS.');
  }
  return uri;
}

String _randomUrlSafe(int byteCount) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

Future<void> _openSystemBrowser(Uri uri) async {
  if (Platform.isWindows) {
    await Process.start(
      'rundll32.exe',
      ['url.dll,FileProtocolHandler', uri.toString()],
      mode: ProcessStartMode.detached,
    );
    return;
  }
  if (Platform.isMacOS) {
    await Process.start('open', [uri.toString()], mode: ProcessStartMode.detached);
    return;
  }
  if (Platform.isLinux) {
    await Process.start('xdg-open', [uri.toString()], mode: ProcessStartMode.detached);
    return;
  }
  throw UnsupportedError('Вход через системный браузер доступен только в настольной сборке.');
}
