import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_security.dart';
import 'school_account_service.dart';

class SchoolAnnouncement {
  final String id;
  final String title;
  final String body;
  final String publishedAt;
  final String targetClass;
  final String targetUserId;
  final String severity;
  final String expiresAt;

  const SchoolAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.publishedAt,
    required this.targetClass,
    required this.targetUserId,
    required this.severity,
    required this.expiresAt,
  });

  factory SchoolAnnouncement.fromJson(Map<String, dynamic> json) {
    String firstText(List<String> keys, {String fallback = ''}) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      return fallback;
    }

    return SchoolAnnouncement(
      id: firstText(['id', 'announcement_id'], fallback: jsonEncode(json.hashCode)),
      title: firstText(['title', 'name', 'subject'], fallback: 'Объявление школы'),
      body: firstText(['body', 'message', 'text', 'description'], fallback: 'Подробности не указаны.'),
      publishedAt: firstText(['published_at', 'created_at', 'date', 'updated_at']),
      targetClass: firstText(['target_class_id', 'class_id']),
      targetUserId: firstText(['target_user_id']),
      severity: firstText(['severity', 'type', 'priority'], fallback: 'info').toLowerCase(),
      expiresAt: firstText(['expires_at', 'expiry', 'expiration_date']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'published_at': publishedAt,
    'target_class_id': targetClass,
    'target_user_id': targetUserId,
    'severity': severity,
    'expires_at': expiresAt,
  };

  bool get isExpired {
    final expiry = DateTime.tryParse(expiresAt);
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  DateTime? get date => DateTime.tryParse(publishedAt);
}

class SchoolAnnouncementsPage extends StatefulWidget {
  const SchoolAnnouncementsPage({super.key});

  @override
  State<SchoolAnnouncementsPage> createState() => _SchoolAnnouncementsPageState();
}

class _SchoolAnnouncementsPageState extends State<SchoolAnnouncementsPage> {
  static const _legacyCacheKey = 'school_announcements_cache_v2';

  String _cacheKeyFor(String userId) =>
      userId.trim().isEmpty ? _legacyCacheKey : '${_legacyCacheKey}_${userId.trim()}';
  List<SchoolAnnouncement> _items = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _serverConfigured = false;
  bool _connectionFailed = false;
  String _status = 'Проверяю подключение…';
  String _classId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool manual = false}) async {
    if (_refreshing) return;
    setState(() {
      _loading = _items.isEmpty;
      _refreshing = true;
      _status = manual ? 'Обновляю объявления…' : 'Проверяю подключение…';
    });

    final prefs = await SharedPreferences.getInstance();
    final base = (prefs.getString('school_api_base_url_v1') ?? prefs.getString('navigator_api_url') ?? '').trim();
    // A successful school sign-in is enough to enable authenticated feeds even
    // when the older offline-data toggle is unset on this installation.
    final schoolToken = (await SchoolAccountService().validAccessToken() ?? '').trim();
    final enabled = (prefs.getBool('navigator_api_enabled') ?? false) || schoolToken.isNotEmpty;
    final storedClassId = (prefs.getString('student_class_id') ?? '').trim();
    final storedClassName = (prefs.getString('student_class_name') ?? '').trim();
    var currentUserId = '';
    var schoolClass = '';
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final schoolUser = jsonDecode(rawSchoolUser);
        if (schoolUser is Map) {
          currentUserId = (schoolUser['id'] ?? '').toString().trim();
          schoolClass = (schoolUser['class_id'] ?? '').toString().trim();
        }
      } catch (_) {}
    }
    _classId = storedClassId.isNotEmpty ? storedClassId
        : storedClassName.isNotEmpty ? storedClassName : schoolClass;

    final cacheKey = _cacheKeyFor(currentUserId);
    // Migrate the old shared cache only after filtering it by this session's
    // class/recipient scope. New writes are always account-scoped.
    final cached = prefs.getString(cacheKey) ??
        (currentUserId.isEmpty ? null : prefs.getString(_legacyCacheKey));
    if (_items.isEmpty && cached != null) {
      try {
        final decoded = jsonDecode(cached) as List;
        _items = decoded.map((item) => SchoolAnnouncement.fromJson(
          Map<String, dynamic>.from(item as Map),
        )).where((item) => !item.isExpired &&
            (item.targetUserId.isEmpty || item.targetUserId == currentUserId) &&
            (item.targetClass.isEmpty ||
                (_classId.isNotEmpty && _sameClass(item.targetClass, _classId)))).toList();
      } catch (_) {
        _items = [];
      }
      // Show cached announcements immediately while the online refresh continues.
      if (_items.isNotEmpty && mounted) {
        setState(() {
          _loading = false;
          _status = 'Сохранённая копия • проверяю обновления…';
        });
      }
    }

    if (!enabled || base.isEmpty) {
      if (mounted) setState(() {
        _serverConfigured = false;
        _loading = false;
        _refreshing = false;
        _status = _items.isEmpty
            ? 'Сервер ещё не настроен. Карта и расписание по-прежнему работают офлайн.'
            : 'Показана сохранённая копия. Для обновления настрой сервер в «Кабинете школы».';
      });
      return;
    }

    if (!isSecureApiBaseUrl(base)) {
      if (mounted) setState(() {
        _serverConfigured = false;
        _connectionFailed = true;
        _loading = false;
        _refreshing = false;
        _status = 'Адрес сервера должен использовать HTTPS без логина, пароля и параметров.';
      });
      return;
    }

    try {
      final parsed = <SchoolAnnouncement>[];
      var feedLoaded = false;
      try {
        final uri = _announcementsUri(base, _classId);
        final response = await http.get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 10));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          final rows = decoded is Map ? decoded['data'] : decoded;
          if (rows is List) {
            feedLoaded = true;
            for (final row in rows) {
              if (row is! Map) continue;
              final announcement = SchoolAnnouncement.fromJson(Map<String, dynamic>.from(row));
              if (announcement.isExpired) continue;
              if (announcement.targetClass.isNotEmpty &&
                  (_classId.isEmpty || !_sameClass(announcement.targetClass, _classId))) continue;
              parsed.add(announcement);
            }
          }
        }
      } catch (_) {
        // Authenticated v2 feeds may still work if the optional workbook feed is offline.
      }
      var securedLoaded = false;
      // Authenticated v2 feeds include targeted/personal notifications and
      // leadership announcements. The public workbook feed remains available
      // for offline-compatible school-wide announcements.
      if (schoolToken.isNotEmpty) {
        final seen = parsed.map((item) => item.id).toSet();
        for (final endpoint in const ['announcements', 'notifications', 'announcements/workbook']) {
          try {
            final secured = await http.get(
              _v2Uri(base, endpoint),
              headers: {'Accept': 'application/json', 'Authorization': 'Bearer $schoolToken'},
            ).timeout(const Duration(seconds: 8));
            if (secured.statusCode < 200 || secured.statusCode >= 300) continue;
            final payload = jsonDecode(secured.body);
            final secureRows = payload is Map ? payload['data'] : payload;
            if (secureRows is! List) continue;
            securedLoaded = true;
            for (final row in secureRows) {
              if (row is! Map) continue;
              final source = Map<String, dynamic>.from(row);
              final kind = (source['kind'] ?? '').toString().toLowerCase();
              final audience = (source['audience'] ?? '').toString().toLowerCase();
              final targetType = (source['target_type'] ?? '').toString().toLowerCase();
              final mapped = <String, dynamic>{
                ...source,
                'published_at': source['created_at'] ?? source['published_at'] ?? '',
                'target_class_id': targetType == 'class'
                    ? source['target_id']
                    : audience == 'class' ? source['class_id'] : (source['target_class_id'] ?? source['class_id'] ?? ''),
                'target_user_id': targetType == 'user' ? source['target_id'] : '',
                'severity': source['severity'] ?? (kind == 'emergency' ? 'emergency' : kind == 'warning' ? 'warning' : 'info'),
                'expires_at': source['expires_at'] ?? '',
              };
              final item = SchoolAnnouncement.fromJson(mapped);
              if (item.isExpired || seen.contains(item.id)) continue;
              if (item.targetUserId.isNotEmpty && item.targetUserId != currentUserId) continue;
              if (item.targetClass.isNotEmpty &&
                  (_classId.isEmpty || !_sameClass(item.targetClass, _classId))) continue;
              parsed.add(item);
              seen.add(item.id);
            }
          } catch (_) {
            // Keep already-loaded public/cache content if an authenticated feed
            // is unavailable or the session has expired.
          }
        }
      }

      if (!feedLoaded && !securedLoaded) throw Exception('No announcement feed is available');
      parsed.sort((a, b) {
        final aDate = a.date;
        final bDate = b.date;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      await prefs.setString(cacheKey, jsonEncode(parsed.map((e) => e.toJson()).toList()));
      if (mounted) setState(() {
        _items = parsed;
        _serverConfigured = true;
        _connectionFailed = false;
        _loading = false;
        _refreshing = false;
        _status = 'Обновлено с сервера • ${parsed.length}';
      });
    } catch (_) {
      if (mounted) setState(() {
        _serverConfigured = false;
        _connectionFailed = true;
        _loading = false;
        _refreshing = false;
        _status = _items.isEmpty
            ? 'Не удалось подключиться. Проверь адрес API и доступность школьной сети.'
            : 'Сервер недоступен. Показана последняя сохранённая копия.';
      });
    }
  }

  Uri _v2Uri(String raw, String endpoint) {
    final parsed = Uri.parse(raw);
    var path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) {
      path = '$path/$endpoint';
    } else if (path.endsWith('/api')) {
      path = '$path/v2/$endpoint';
    } else {
      path = '$path/api/v2/$endpoint';
    }
    return parsed.replace(path: path, query: null, fragment: '', userInfo: '');
  }

  Uri _announcementsUri(String raw, String classId) {
    final parsed = Uri.parse(raw);
    var path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    // Accept both a server root (https://school.example) and an API root
    // (https://school.example/api) without producing /api/api/announcements.
    if (path.endsWith('/api/v2')) {
      path = path.substring(0, path.length - '/api/v2'.length);
    }
    if (!path.endsWith('/api')) path = '$path/api';
    path = '$path/announcements';
    return parsed.replace(
      path: path,
      queryParameters: classId.isEmpty ? null : {'class_id': classId},
      fragment: '',
      userInfo: '',
    );
  }

  String _normalizeClass(String value) {
    const latinLookalikes = <String, String>{
      'А': 'A', 'В': 'B', 'С': 'C', 'Е': 'E', 'Н': 'H', 'К': 'K',
      'М': 'M', 'О': 'O', 'Р': 'P', 'Т': 'T', 'Х': 'X', 'У': 'Y',
    };
    return value.trim().toUpperCase().replaceAll(' ', '').split('')
        .map((letter) => latinLookalikes[letter] ?? letter).join();
  }

  bool _sameClass(String a, String b) => _normalizeClass(a) == _normalizeClass(b);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Объявления и оповещения', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _refreshing ? null : () => _load(manual: true),
            icon: _refreshing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [scheme.primaryContainer, scheme.surfaceContainerHigh],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)),
                          child: Icon(Icons.campaign_rounded, color: scheme.primary, size: 26),
                        ),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Новости школы', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 5),
                          Text(_status, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 12)),
                          if (_classId.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Класс: $_classId', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ])),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    if (_items.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(26),
                          child: Column(children: [
                            Icon(_serverConfigured ? Icons.cloud_off_rounded : Icons.campaign_outlined, size: 44, color: scheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              _connectionFailed ? 'Не удалось загрузить объявления' : _serverConfigured ? 'Объявлений пока нет' : 'Нет подключённого источника',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _connectionFailed
                                  ? 'Проверь адрес API и подключение к школьной сети, затем нажми «Повторить».'
                                  : _serverConfigured
                                      ? 'Когда школа опубликует объявление, оно появится здесь.'
                                      : 'В «Настройки → Кабинет школы → Синхронизация» можно указать адрес API. Без сервера Поколение продолжит работать офлайн.',
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: _refreshing ? null : () => _load(manual: true),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Повторить'),
                            ),
                          ]),
                        ),
                      )
                    else ...[
                      Row(children: [
                        Expanded(child: Text('Все объявления', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                        Text('${_items.length}', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 10),
                      for (final item in _items) ...[
                        _AnnouncementCard(item: item),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final SchoolAnnouncement item;
  const _AnnouncementCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = {'emergency', 'urgent', 'critical', 'экстренно', 'экстренное'}.contains(item.severity);
    final warning = urgent || {'warning', 'важно', 'предупреждение'}.contains(item.severity);
    final accent = urgent ? scheme.error : warning ? const Color(0xFFB7791F) : scheme.primary;
    final date = item.date;
    final dateLabel = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 5, color: accent),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, height: 1.25))),
              if (warning) ...[
                const SizedBox(width: 8),
                Icon(urgent ? Icons.warning_amber_rounded : Icons.priority_high_rounded, color: accent, size: 20),
              ],
            ]),
            const SizedBox(height: 8),
            Text(item.body, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5)),
            if (dateLabel.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.schedule_rounded, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(dateLabel, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ]),
            ],
          ]),
        )),
      ]),
    );
  }
}
