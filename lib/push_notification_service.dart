import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:http/http.dart' as http;

import 'api_security.dart';

/// Client-side Firebase Cloud Messaging adapter.
///
/// Call this only after the school identity provider has authenticated the user
/// and supplied a short-lived Navigator API access token. Firebase project
/// configuration is supplied by the school's generated FirebaseOptions;
/// no Firebase credentials are embedded in this source file.
///
/// The UI decides how to show foreground messages and where to navigate when a
/// user taps an alert. Do not put student details or precise location in FCM
/// payloads: notifications may appear on a locked screen.
class PushNotificationService {
  PushNotificationService._({
    required FirebaseMessaging messaging,
    required Uri registrationUri,
    required String accessToken,
  })  : _messaging = messaging,
        _registrationUri = registrationUri,
        _accessToken = accessToken;

  final FirebaseMessaging _messaging;
  final Uri _registrationUri;
  final String _accessToken;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  bool _disposed = false;

  static Future<PushNotificationService?> initialize({
    required String apiBaseUrl,
    required String accessToken,
    FirebaseOptions? firebaseOptions,
    String? webVapidKey,
    void Function(RemoteMessage message)? onForegroundMessage,
    void Function(RemoteMessage message)? onNotificationTap,
    void Function(String message)? onError,
  }) async {
    if (!isSecureApiBaseUrl(apiBaseUrl) || accessToken.trim().isEmpty) {
      onError?.call('Для уведомлений нужен HTTPS-адрес API и действующий сеанс.');
      return null;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: firebaseOptions);
      }
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        onError?.call('Уведомления отключены в настройках устройства.');
        return null;
      }

      final base = Uri.parse(apiBaseUrl.trim());
      final service = PushNotificationService._(
        messaging: messaging,
        registrationUri: base.resolve('/api/v1/devices/register'),
        accessToken: accessToken,
      );

      service._foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (message) => onForegroundMessage?.call(message),
      );
      service._openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => onNotificationTap?.call(message),
      );

      final initial = await messaging.getInitialMessage();
      if (initial != null) onNotificationTap?.call(initial);

      final token = await messaging.getToken(vapidKey: webVapidKey);
      if (token != null && token.isNotEmpty) {
        await service._registerToken(token);
      }
      service._tokenSubscription = messaging.onTokenRefresh.listen((newToken) {
        service._registerToken(newToken).catchError((Object error) {
          onError?.call('Не получилось обновить регистрацию устройства.');
        });
      });
      return service;
    } catch (_) {
      // Firebase is deliberately optional until the school configures a project.
      onError?.call('Firebase пока не настроен или недоступен. Приложение продолжает работать.');
      return null;
    }
  }

  Future<void> _registerToken(String token) async {
    if (_disposed) return;
    final response = await http
        .post(
          _registrationUri,
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'token': token,
            'platform': _platformName(),
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Device registration failed: HTTP \${response.statusCode}');
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'unknown',
    };
  }

  /// Removes listeners. Server-side device removal should be called by the
  /// authenticated account/session manager before that session is discarded.
  Future<void> dispose() async {
    _disposed = true;
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }
}
