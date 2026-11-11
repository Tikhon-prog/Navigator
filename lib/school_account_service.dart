import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';
import 'desktop_sso_stub.dart' if (dart.library.io) 'desktop_sso_io.dart' as desktop_sso;

class SchoolAccountService {
  static const _appAuth = FlutterAppAuth();
  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'school_access_token_v1';
  static const _userKey = 'school_user_v1';
  static const _refreshKey = 'school_refresh_token_v1';
  static const _expiresKey = 'school_access_expires_at_v1';

  @visibleForTesting
  static String? resolveDevicePlatform({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    if (isWeb ?? kIsWeb) {
      // Web push needs a configured VAPID key and Firebase messaging service worker.
      // Neither is part of the current web client configuration.
      return null;
    }
    switch (platform ?? defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      default:
        // FCM is not supported by the current native Linux/Windows clients.
        return null;
    }
  }

  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static Future<String?>? _refreshInFlight;

  /// Reads a token from protected platform storage. Existing releases stored
  /// tokens in SharedPreferences, so migrate them once and remove the legacy
  /// plaintext copy immediately after a successful secure write.
  static Future<String?> _readToken(String key) async {
    try {
      final secure = await _secureStorage.read(key: key);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (_) {
      // Do not silently put newly issued credentials back into plaintext prefs.
      rethrow;
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy == null || legacy.isEmpty) return null;
    await _secureStorage.write(key: key, value: legacy);
    await prefs.remove(key);
    return legacy;
  }

  static Future<void> _writeToken(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> _deleteToken(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // Still clear legacy plaintext copies and let server-side revocation run.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

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

  static Uri _sheetUri(String rawBase, String sheet) {
    final base = Uri.parse(rawBase.trim());
    var path = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) path = path.substring(0, path.length - '/api/v2'.length);
    path = path.endsWith('/api') ? '$path/data/$sheet' : '$path/api/data/$sheet';
    return base.replace(path: path, query: null, fragment: '', userInfo: '');
  }

  Future<String> _resolveClassName(String baseUrl, String classId) async {
    try {
      final response = await http.get(_sheetUri(baseUrl, 'Classes'),
          headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return classId;
      final payload = jsonDecode(response.body);
      final rows = payload is Map ? payload['data'] : null;
      if (rows is! List) return classId;
      for (final raw in rows.whereType<Map>()) {
        final id = (raw['id'] ?? raw['class_id'] ?? raw['code'] ?? '').toString().trim();
        if (id != classId) continue;
        final name = (raw['name'] ?? raw['class_name'] ?? raw['title'] ?? raw['класс'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return classId;
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

  Future<Map<String, dynamic>> signInAsServerAdmin(
    String baseUrl, {required String username, required String password}
  ) async {
    final response = await http.post(
      _endpoint(baseUrl, 'auth/login'),
      headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(response.statusCode == 401
          ? 'Неверный логин или пароль технического администратора.'
          : 'Сервер не принял вход (HTTP ${response.statusCode}).');
    }
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['access_token'] is! String) {
      throw const FormatException('Неверный ответ авторизации');
    }
    final user = Map<String, dynamic>.from((payload['user'] as Map?) ?? const {});
    if (user['role'] != 'admin') {
      final refresh = payload['refresh_token']?.toString() ?? '';
      if (refresh.isNotEmpty) {
        try {
          await http.post(_endpoint(baseUrl, 'auth/logout'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refresh}));
        } catch (_) {}
      }
      throw Exception('Резервный вход разрешён только техническому администратору. Используй школьный SSO.');
    }
    final prefs = await SharedPreferences.getInstance();
    await _writeToken(_tokenKey, payload['access_token'] as String);
    await _writeToken(_refreshKey, payload['refresh_token']?.toString() ?? '');
    await prefs.setInt(_expiresKey, DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((payload['expires_in'] as num?)?.toInt() ?? 28800));
    await prefs.setString(_userKey, jsonEncode(user));
    await prefs.remove('student_class_id');
    await prefs.remove('student_class_name');
    await prefs.setString('school_api_base_url_v1', baseUrl.trim());
    if (user['id'] != null) {
      final preferenceKey = 'dop_reminders_enabled_${user['id']}';
      final reminderPreference = prefs.getBool(preferenceKey) ?? false;
      await prefs.setBool(preferenceKey, reminderPreference);
      await prefs.setBool('dop_reminders_enabled', reminderPreference);
    }
    var pushRegistered = false;
    try {
      pushRegistered = await _initializePush(await _getConfig(baseUrl), baseUrl, payload['access_token'] as String);
    } catch (_) {}
    return {'user': user, 'push_registered': pushRegistered};
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

    late final String? providerToken;
    late final String? providerIdToken;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final desktopRedirectUri = '${sso['desktop_redirect_uri'] ?? ''}'.trim();
      if (desktopRedirectUri.isEmpty) {
        throw Exception(
          'Для Windows не настроен NAVIGATOR_OIDC_DESKTOP_REDIRECT_URI на сервере. '
          'Добавь http://127.0.0.1:43827/oauth/callback в разрешённые адреса школьного OIDC.',
        );
      }
      final desktopTokens = await desktop_sso.authorizeAndExchangeCode(
        clientId: clientId,
        issuer: issuer,
        redirectUri: desktopRedirectUri,
      );
      providerToken = desktopTokens.accessToken;
      providerIdToken = desktopTokens.idToken;
    } else {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          issuer: issuer,
          scopes: const ['openid', 'profile', 'email'],
          promptValues: const ['login'],
        ),
      );
      providerToken = result.accessToken;
      providerIdToken = result.idToken;
    }
    if (providerToken == null || providerToken.isEmpty || providerIdToken == null || providerIdToken.isEmpty) {
      throw Exception('Школьный провайдер не вернул необходимые OIDC-токены.');
    }

    final response = await http.post(
      _endpoint(baseUrl, 'auth/sso'),
      headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': providerToken, 'id_token': providerIdToken}),
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
    await _writeToken(_tokenKey, payload['access_token'] as String);
    await _writeToken(_refreshKey, payload['refresh_token']?.toString() ?? '');
    await prefs.setInt(_expiresKey, DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((payload['expires_in'] as num?)?.toInt() ?? 28800));
    await prefs.setString(_userKey, jsonEncode(payload['user'] ?? {}));
    final userData = payload['user'];
    if (userData is Map && userData['id'] != null) {
      final preferenceKey = 'dop_reminders_enabled_${userData['id']}';
      final savedPreference = prefs.getBool(preferenceKey);
      final reminderPreference = savedPreference ?? (prefs.getBool('dop_reminders_enabled') ?? false);
      await prefs.setBool(preferenceKey, reminderPreference);
      await prefs.setBool('dop_reminders_enabled', reminderPreference);
    }
    if (userData is Map && userData['class_id'] != null && userData['class_id'].toString().trim().isNotEmpty) {
      final classId = userData['class_id'].toString().trim();
      final className = await _resolveClassName(baseUrl, classId);
      await prefs.setString('student_class_id', classId);
      await prefs.setString('student_class_name', className);
    } else {
      await prefs.remove('student_class_id');
      await prefs.remove('student_class_name');
    }
    await prefs.setString('school_api_base_url_v1', baseUrl.trim());
    // Keep server-side reminder scheduling aligned with the user's local choice.
    try {
      await setDopRemindersEnabled(prefs.getBool('dop_reminders_enabled') ?? false);
    } catch (_) {}

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
    // Do not attempt FCM on unsupported native desktop platforms.
    // The account session and other online features continue to work normally.
    final platform = resolveDevicePlatform();
    if (platform == null) return false;
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
    await _registerToken(baseUrl, accessToken, token, platform);
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final fresh = await validAccessToken();
      if (fresh != null) await _registerToken(baseUrl, fresh, newToken, platform);
    });
    _messageSubscription = FirebaseMessaging.onMessage.listen((message) async {
      final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Поколение';
      final body = message.notification?.body ?? message.data['body']?.toString() ?? 'Новое школьное уведомление';
      await LocalNotificationService().showIncomingNotification(title: title, body: body);
    });
    return true;
  }

  Future<void> _registerToken(
    String baseUrl,
    String accessToken,
    String token,
    String platform,
  ) async {
    await http.post(
      _endpoint(baseUrl, 'devices/register'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'token': token, 'platform': platform}),
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

  /// Restore server-backed notifications after an app restart without blocking
  /// Flutter startup. The stored refresh token is rotated before any network
  /// registration when the access token is close to expiry.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    final savedUser = await currentUser();
    if (baseUrl.isEmpty || savedUser == null) return false;
    final token = await validAccessToken();
    if (token == null || token.isEmpty) return false;
    try {
      final config = await _getConfig(baseUrl);
      return await _initializePush(config, baseUrl, token);
    } catch (_) {
      // Keep a valid offline session; the next explicit login/network operation
      // can recover Firebase registration when the school server comes back.
      return false;
    }
  }

  Future<int?> refreshMySupplements() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    final rawUser = prefs.getString(_userKey);
    final accessToken = await validAccessToken();
    if (accessToken == null || accessToken.isEmpty || baseUrl.isEmpty || rawUser == null) return null;
    try {
      final user = jsonDecode(rawUser);
      if (user is! Map || user['role'] != 'student' || user['id'] == null) return null;
      final response = await http.get(
        _endpoint(baseUrl, 'students/${user['id']}'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['supplements'] is! List) return null;
      final rows = <Map<String, dynamic>>[];
      for (final item in (payload['supplements'] as List).whereType<Map>()) {
        final weekday = (item['weekday'] as num?)?.toInt();
        if (weekday == null || weekday < 1 || weekday > 7) continue;
        rows.add({
          'id': 'server_${item['id'] ?? ''}',
          'title': item['title']?.toString() ?? 'ДОП',
          'weekday': weekday,
          'start': item['time']?.toString() ?? '',
          'end': '',
          'teacher': item['teacher']?.toString() ?? '',
          'room': item['room']?.toString() ?? '',
          'place': '',
          'group': '',
          'description': '',
        });
      }
      final cacheSuffix = user['id'].toString();
      await prefs.setString('school_supplements_cache_v1_$cacheSuffix', jsonEncode(rows));
      await prefs.setString('school_supplements_user_id_v1_$cacheSuffix', cacheSuffix);
      return rows.length;
    } catch (_) {
      return null;
    }
  }

  Future<bool> setDopRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null) {
      try {
        final user = jsonDecode(rawUser);
        if (user is Map && user['id'] != null) {
          await prefs.setBool('dop_reminders_enabled_${user['id']}', enabled);
        }
      } catch (_) {}
    }
    final accessToken = await validAccessToken();
    if (accessToken == null || accessToken.isEmpty || baseUrl.isEmpty) return false;
    final response = await http.put(
      _endpoint(baseUrl, 'notifications/preferences'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'dop_reminders_enabled': enabled}),
    ).timeout(const Duration(seconds: 10));
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  Future<String?> validAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final access = await _readToken(_tokenKey);
    if (access == null || access.isEmpty) return null;
    final expiresAt = prefs.getInt(_expiresKey);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt == null || expiresAt > now + 60) return access;
    return refreshSession();
  }

  Future<String?> refreshSession() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final pending = _performRefreshSession();
    _refreshInFlight = pending;
    return pending.whenComplete(() { _refreshInFlight = null; });
  }

  Future<String?> _performRefreshSession() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = (await _readToken(_refreshKey)) ?? '';
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    if (refreshToken.isEmpty || baseUrl.isEmpty) return null;
    try {
      final response = await http.post(
        _endpoint(baseUrl, 'auth/refresh'),
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['access_token'] is! String || payload['refresh_token'] is! String) return null;
      await _writeToken(_tokenKey, payload['access_token'] as String);
      await _writeToken(_refreshKey, payload['refresh_token'] as String);
      await prefs.setInt(_expiresKey, DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((payload['expires_in'] as num?)?.toInt() ?? 28800));
      if (payload['user'] != null) await prefs.setString(_userKey, jsonEncode(payload['user']));
      return payload['access_token'] as String;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = (prefs.getString('school_api_base_url_v1') ?? '').trim();
    final accessToken = await validAccessToken();
    final refreshToken = (await _readToken(_refreshKey)) ?? '';
    final rawUser = prefs.getString(_userKey);
    var currentUserId = '';
    if (rawUser != null) {
      try {
        final user = jsonDecode(rawUser);
        if (user is Map && user['id'] != null) {
          currentUserId = user['id'].toString().trim();
          await prefs.setBool('dop_reminders_enabled_${currentUserId}', prefs.getBool('dop_reminders_enabled') ?? false);
        }
      } catch (_) {}
    }
    await prefs.setBool('dop_reminders_enabled', false);
    try { await LocalNotificationService().cancelDopReminders(); } catch (_) {}
    String? deviceToken;
    try {
      deviceToken = Firebase.apps.isEmpty ? null : await FirebaseMessaging.instance.getToken();
    } catch (_) {}
    if (accessToken != null && accessToken.isNotEmpty && baseUrl.isNotEmpty && deviceToken != null && deviceToken.isNotEmpty) {
      try {
        await http.delete(
          _endpoint(baseUrl, 'devices/me'),
          headers: {'Authorization': 'Bearer $accessToken', 'Accept': 'application/json', 'Content-Type': 'application/json'},
          body: jsonEncode({'token': deviceToken}),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (refreshToken.isNotEmpty && baseUrl.isNotEmpty) {
      try {
        await http.post(
          _endpoint(baseUrl, 'auth/logout'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (accessToken != null && accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'refresh_token': refreshToken,
            if (deviceToken != null && deviceToken.isNotEmpty) 'device_token': deviceToken,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    _tokenSubscription = null;
    _messageSubscription = null;
    // Migrate a legacy shared DOP list only when its old sync marker proves
    // it belonged to this account; never assign an unknown user's offline
    // entries to the account that happens to be signed in at logout.
    try {
      final legacyDops = prefs.getString('supplements_local');
      final legacyOwner = prefs.getString('school_supplements_user_id_v1') ?? '';
      if (legacyDops != null && currentUserId.isNotEmpty && legacyOwner == currentUserId) {
        final rawRows = jsonDecode(legacyDops);
        if (rawRows is List) {
          final scopedKey = 'supplements_local_${currentUserId}';
          final existing = prefs.getString(scopedKey);
          final byId = <String, Map<String, dynamic>>{};
          if (existing != null) {
            try {
              for (final item in (jsonDecode(existing) as List).whereType<Map>()) {
                final map = Map<String, dynamic>.from(item);
                byId[(map['id'] ?? '').toString()] = map;
              }
            } catch (_) {}
          }
          for (final item in rawRows.whereType<Map>()) {
            final map = Map<String, dynamic>.from(item);
            final id = (map['id'] ?? '').toString();
            if (id.isEmpty || id.startsWith('server_')) continue;
            byId.putIfAbsent(id, () => map);
          }
          await prefs.setString(scopedKey, jsonEncode(byId.values.toList()));
        }
      }
    } catch (_) {}
    await prefs.remove('supplements_local');
    // Keep account-isolated manual/intranet entries, but drop stale server rows
    // which will be refreshed after the same account signs in again.
    if (currentUserId.isNotEmpty) {
      final scopedDopKey = 'supplements_local_$currentUserId';
      final scopedDops = prefs.getString(scopedDopKey);
      if (scopedDops != null) {
        try {
          final rows = (jsonDecode(scopedDops) as List).where((item) =>
              item is Map && !((item['id']?.toString() ?? '').startsWith('server_'))).toList();
          await prefs.setString(scopedDopKey, jsonEncode(rows));
        } catch (_) {}
      }
      await prefs.remove('school_announcements_cache_v2_$currentUserId');
      await prefs.remove('school_supplements_cache_v1_$currentUserId');
      await prefs.remove('school_supplements_user_id_v1_$currentUserId');
    }
    await prefs.remove('school_supplements_cache_v1');
    await prefs.remove('school_supplements_user_id_v1');
    for (final key in const [
      'student_last_name', 'student_first_name', 'student_class_number',
      'student_class_letter', 'student_class_name', 'student_class_id',
      'last_name', 'first_name', 'class_name', 'class_id', 'class_number',
      'class_letter', 'class_grade', 'profile_last_name', 'profile_first_name',
      'surname', 'name', 'student_profile', 'profile', 'student_profile_name',
    ]) {
      await prefs.remove(key);
    }
    await prefs.remove('dop_last_sync');
    await _deleteToken(_tokenKey);
    await _deleteToken(_refreshKey);
    await prefs.remove(_expiresKey);
    await prefs.remove(_userKey);
    await prefs.remove('student_class_id');
    await prefs.remove('student_class_name');
  }
}
