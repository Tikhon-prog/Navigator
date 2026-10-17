import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';

class SchoolAccountService {
  static const _appAuth = FlutterAppAuth();
  static const _tokenKey = 'school_access_token_v1';
  static const _userKey = 'school_user_v1';
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _messageSubscription;

  static Uri _endpoint(String rawBase, String suffix) {
    final base = Uri.parse(rawBase.trim());
    var path = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) {
      path = path.substring(0, path.length - '/api/v2'.length);
    }
    if (path.endsWith('/api')) {
      path = '$path/v2/$suffix';
    } else {
      path = '$path/api/v2/$suffix';
    }
    return base.replace(path: path, query: null, fragment: '', userInfo: '');
  }

  Future<Map<String, dynamic>> _getConfig(String baseUrl) async {
    final response = await http.get(
      _endpoint(baseUrl, 'public/config'),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Сервер вернул HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) throw const FormatException('Неверный ответ конфигурации');
    return data;
  }

  Future<Map<String, dynamic>> signInWithSchoolAccount(String baseUrl) async {
    final config = await _getConfig(baseUrl);
    final sso = config['sso'];
    if (sso is! Map || sso['enabled'] != true) {
      throw Exception('Школьный SSO ещё не настроен администратором сервера.');
    }
    final clientId = '${sso['client_id'] ?? ''}'.trim();
    final issuer = '${sso['issuer'] ?? ''}'.trim();
    final redirectUri = '${sso['redirect_uri'] ?? ''}'.trim();
    if (clientId.isEmpty || issuer.isEmpty || redirectUri.isEmpty) {
      throw Exception('В конфигурации школьного входа не хватает обязательных параметров.');
    }

    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUri,
        issuer: issuer,
        scopes: const ['openid', 'profile', 'email'],
        promptValues: const ['login'],
      ),
    );
    final providerToken = result?.accessToken;
    if (providerToken == null || providerToken.isEmpty) {
      throw Exception('Школьный провайдер не вернул токен доступа.');
    }

    final response = await http.post(
      _endpoint(baseUrl, 'auth/sso'),
      headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': providerToken}),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = response.statusCode == 403
          ? 'Учётная запись ещё не связана с профилем Поколения. Обратись к школьному администратору.'
          : 'Сервер не принял школьный вход (HTTP ${response.statusCode}).';
      throw Exception(message);
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['access_token'] is! String) {
      throw const FormatException('Неверный ответ авторизации');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, payload['access_token'] as String);
    await prefs.setString(_userKey, jsonEncode(payload['user'] ?? {}));
    await prefs.setString('school_api_base_url_v1', baseUrl.trim());

    var pushRegistered = false;
    try {
      pushRegistered = await _initializePush(config, baseUrl, payload['access_token'] as String);
    } catch (_) {
      // Authentication must succeed even if Firebase/mobile notification setup
      // is not yet enabled by school IT.
    }
    return {
      'user': Map<String, dynamic>.from((payload['user'] as Map?) ?? const {}),
      'push_registered': pushRegistered,
    };
  }

  Future<bool> _initializePush(Map<String, dynamic> config, String baseUrl, String accessToken) async {
    final rawFirebase = config['firebase'];
    if (rawFirebase is! Map || rawFirebase['enabled'] != true) return false;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseOptions(
        apiKey: '${rawFirebase['api_key']}',
        appId: '${rawFirebase['app_id']}',
        messagingSenderId: '${rawFirebase['messaging_sender_id']}',
        projectId: '${rawFirebase['project_id']}',
      ));
    }
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return false;
    await _registerToken(baseUrl, accessToken, token);
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _registerToken(baseUrl, accessToken, newToken);
    });
    _messageSubscription = FirebaseMessaging.onMessage.listen((message) async {
      final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Поколение';
      final body = message.notification?.body ?? message.data['body']?.toString() ?? 'Новое школьное уведомление';
      await LocalNotificationService().showIncomingNotification(title: title, body: body);
    });
    return true;
  }

  Future<void> _registerToken(String baseUrl, String accessToken, String token) async {
    await http.post(
      _endpoint(baseUrl, 'devices/register'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'token': token, 'platform': 'android'}),
    ).timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>?> currentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setDopRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_tokenKey);
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    if (accessToken == null || accessToken.isEmpty || baseUrl.isEmpty) return false;
    final response = await http.put(
      _endpoint(baseUrl, 'notifications/preferences'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'dop_reminders_enabled': enabled}),
    ).timeout(const Duration(seconds: 10));
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_tokenKey);
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    if (accessToken != null && accessToken.isNotEmpty && baseUrl.isNotEmpty) {
      try {
        await http.delete(
          _endpoint(baseUrl, 'devices/me'),
          headers: {'Authorization': 'Bearer $accessToken', 'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = null;
    _messageSubscription = null;
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
