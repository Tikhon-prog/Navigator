import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';
import 'school_account_service.dart';

/// Native Windows has no Firebase Messaging client. Poll the authenticated
/// in-app feed while the desktop app is running and convert only newly observed
/// notifications to Windows toast notifications.
class _DesktopNotificationPolling {
  static Timer? _timer;
  static bool _polling = false;
  static String _accountScope = '';
  static String _baseUrl = '';
  static final Set<String> _knownIds = <String>{};
  static bool _seeded = false;

  static Future<void> start() async {
    if (!Platform.isWindows) return;

    final prefs = await SharedPreferences.getInstance();
    final user = await SchoolAccountService().currentUser();
    final baseUrl = (prefs.getString('school_api_base_url_v1') ??
            prefs.getString('navigator_api_url') ??
            '').trim();
    if (user == null || baseUrl.isEmpty) {
      await stop();
      return;
    }

    final userId = (user['id'] ?? user['username'] ?? '').toString().trim();
    if (userId.isEmpty) {
      await stop();
      return;
    }

    final scope = '$baseUrl|$userId';
    if (_accountScope != scope) {
      _timer?.cancel();
      _timer = null;
      _knownIds.clear();
      _seeded = false;
      _accountScope = scope;
      _baseUrl = baseUrl;
      await _poll(showNew: false);
    }

    _timer ??= Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_poll(showNew: true)),
    );
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _accountScope = '';
    _baseUrl = '';
    _knownIds.clear();
    _seeded = false;
  }

  static Uri _endpoint(String rawBase, String suffix) {
    final base = Uri.parse(rawBase.trim());
    var path = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) {
      path = path.substring(0, path.length - '/api/v2'.length);
    }
    path = path.endsWith('/api')
        ? '$path/v2/$suffix'
        : '$path/api/v2/$suffix';
    return base.replace(path: path, query: null, fragment: '', userInfo: '');
  }

  static Future<void> _poll({required bool showNew}) async {
    if (!Platform.isWindows || _polling || _accountScope.isEmpty || _baseUrl.isEmpty) {
      return;
    }
    _polling = true;
    try {
      final token = await SchoolAccountService().validAccessToken();
      if (token == null || token.isEmpty) {
        await stop();
        return;
      }

      final response = await http.get(
        _endpoint(_baseUrl, 'notifications'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 401 || response.statusCode == 403) {
        await stop();
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final dynamic payload = jsonDecode(response.body);
      if (payload is! Map || payload['data'] is! List) return;

      final rows = (payload['data'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item['id'] ?? '').toString().trim().isNotEmpty)
          .toList();

      // API returns newest first. Keep known IDs bounded so the poller can run
      // for a long time without growing memory indefinitely.
      final newRows = rows.where((item) {
        final id = item['id'].toString();
        return !_knownIds.contains(id);
      }).toList();

      if (showNew && _seeded) {
        for (final item in newRows.reversed) {
          final kind = (item['kind'] ?? '').toString();
          if (kind == 'dop_reminder') continue; // Local DOP scheduling already handles this case.
          final title = (item['title'] ?? 'Школьное оповещение').toString().trim();
          final body = (item['body'] ?? '').toString().trim();
          await LocalNotificationService().showIncomingNotification(
            title: title.isEmpty ? 'Школьное оповещение' : title,
            body: body,
          );
        }
      }

      _knownIds.addAll(rows.map((item) => item['id'].toString()));
      _seeded = true;
      if (_knownIds.length > 500) {
        _knownIds
          ..clear()
          ..addAll(rows.take(200).map((item) => item['id'].toString()));
      }
    } catch (_) {
      // Keep the timer alive through temporary network/server failures.
    } finally {
      _polling = false;
    }
  }
}

Future<void> startDesktopNotificationPolling() =>
    _DesktopNotificationPolling.start();

Future<void> stopDesktopNotificationPolling() =>
    _DesktopNotificationPolling.stop();
