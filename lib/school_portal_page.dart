import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'school_account_service.dart';

class SchoolPortalPage extends StatefulWidget {
  const SchoolPortalPage({super.key});

  @override
  State<SchoolPortalPage> createState() => _SchoolPortalPageState();
}

class _SchoolPortalPageState extends State<SchoolPortalPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool loading = true;
  bool busy = false;
  String error = '';
  String baseUrl = '';
  String accessToken = '';
  Map<String, dynamic> user = {};
  Map<String, dynamic> counts = {};
  String? position;
  String? scopeClass;
  List<String> permissions = [];
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> notifications = [];

  bool get isAdmin => user['role'] == 'admin';
  bool get isLeadership => isAdmin || const {'director', 'deputy'}.contains(position);
  bool get canManageUsers => permissions.contains('*') || permissions.contains('staff.manage');
  bool get canReadUsers => permissions.contains('*') || permissions.contains('staff.read');
  bool get canSendNotifications => isLeadership || const {'homeroom_teacher', 'dop_coordinator'}.contains(position) || user['role'] == 'teacher';
  bool get canReadStudents => user['role'] != 'student' && user['role'] != null;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    _load();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Uri _uri(String suffix) {
    final base = Uri.parse(baseUrl);
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

  Future<dynamic> _request(String method, String suffix, {Map<String, dynamic>? body}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $accessToken',
      if (body != null) 'Content-Type': 'application/json',
    };
    final uri = _uri(suffix);
    late http.Response response;
    if (method == 'POST') {
      response = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
    } else if (method == 'PATCH') {
      response = await http.patch(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
    } else if (method == 'PUT') {
      response = await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
    } else if (method == 'DELETE') {
      response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 12));
    } else {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Ошибка сервера: HTTP ${response.statusCode}';
      try {
        final payload = jsonDecode(response.body);
        if (payload is Map && payload['detail'] != null) message = payload['detail'].toString();
      } catch (_) {}
      throw Exception(message);
    }
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body);
  }

  Future<void> _load() async {
    setState(() { loading = true; error = ''; });
    try {
      final prefs = await SharedPreferences.getInstance();
      baseUrl = (prefs.getString('school_api_base_url_v1') ?? prefs.getString('navigator_api_url') ?? '').trim();
      accessToken = prefs.getString('school_access_token_v1') ?? '';
      final rawUser = prefs.getString('school_user_v1');
      if (rawUser != null) {
        final decoded = jsonDecode(rawUser);
        if (decoded is Map) user = Map<String, dynamic>.from(decoded);
      }
      if (baseUrl.isEmpty || accessToken.isEmpty) {
        throw Exception('Сначала войди через школьную учётную запись в настройках.');
      }
      final access = Map<String, dynamic>.from(await _request('GET', 'auth/permissions') as Map);
      user = Map<String, dynamic>.from(access['user'] as Map? ?? user);
      position = access['position']?.toString();
      scopeClass = access['scope_class']?.toString();
      permissions = (access['permissions'] as List? ?? const []).map((e) => e.toString()).toList();

      final futures = <Future<void>>[
        _loadNotifications(),
      ];
      if (canReadStudents) futures.add(_loadStudents());
      if (permissions.contains('*') || permissions.contains('dashboard.read')) futures.add(_loadDashboard());
      if (canReadUsers || permissions.contains('assignments.manage')) futures.add(_loadUsers());
      await Future.wait(futures);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadDashboard() async {
    try {
      final result = await _request('GET', 'management/dashboard') as Map;
      counts = Map<String, dynamic>.from(result['counts'] as Map? ?? const {});
    } catch (_) { counts = {}; }
  }

  Future<void> _loadStudents() async {
    try {
      final result = await _request('GET', 'management/students') as Map;
      students = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) { students = []; }
  }

  Future<void> _loadUsers() async {
    try {
      final endpoint = canReadUsers ? 'admin/users' : 'management/staff';
      final result = await _request('GET', endpoint) as Map;
      users = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) { users = []; }
  }

  Future<void> _loadNotifications() async {
    try {
      final result = await _request('GET', 'notifications') as Map;
      notifications = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) { notifications = []; }
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Изменения сохранены.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openStudent(Map<String, dynamic> student) async {
    final id = student['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final isStudent = user['role'] == 'student';
      final endpoint = isStudent ? 'students/$id' : 'management/students/$id/supplements';
      final result = Map<String, dynamic>.from(await _request('GET', endpoint) as Map);
      final profile = Map<String, dynamic>.from((result['student'] as Map?) ?? student);
      final supplements = (result['supplements'] as List?) ?? (result['data'] as List?) ?? const [];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(profile['display_name']?.toString() ?? 'Ученик'),
          content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Класс: ${profile['class_id'] ?? 'не указан'}'),
              const SizedBox(height: 12),
              const Text('Дополнительные занятия', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              if (supplements.isEmpty) const Text('Нет доступных записей или у этой роли нет прав на просмотр.'),
              for (final item in supplements.whereType<Map>())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['title']?.toString() ?? 'ДОП'),
                  subtitle: Text([
                    if (item['weekday'] != null) 'День: ${item['weekday']}',
                    if ('${item['time'] ?? ''}'.isNotEmpty) '${item['time']}',
                    if ('${item['room'] ?? ''}'.isNotEmpty) 'Кабинет ${item['room']}',
                  ].join(' • ')),
                ),
            ],
          ))),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _composeNotification() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final targetId = TextEditingController();
    String kind = 'targeted';
    final isLead = isLeadership;
    String targetType = isLead || position == 'homeroom_teacher' ? 'class' : 'user';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Новое оповещение'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Заголовок'), maxLength: 180),
          TextField(controller: body, decoration: const InputDecoration(labelText: 'Текст сообщения'), minLines: 2, maxLines: 5, maxLength: 4000),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: kind,
            decoration: const InputDecoration(labelText: 'Тип'),
            items: [
              const DropdownMenuItem(value: 'targeted', child: Text('Целевое')),
              const DropdownMenuItem(value: 'personal', child: Text('Личное')),
              if (isLead) const DropdownMenuItem(value: 'global', child: Text('Общее для всех')),
              if (isLead) const DropdownMenuItem(value: 'emergency', child: Text('Экстренное')),
            ],
            onChanged: (v) => setDialogState(() {
              kind = v ?? 'targeted';
              if (kind == 'global' || kind == 'emergency') targetType = 'all';
              else if (kind == 'personal') targetType = 'user';
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: targetType,
            decoration: const InputDecoration(labelText: 'Кому'),
            items: [
              if (isLead) const DropdownMenuItem(value: 'all', child: Text('Вся школа')),
              if (isLead || position == 'homeroom_teacher')
                const DropdownMenuItem(value: 'class', child: Text('Класс')),
              const DropdownMenuItem(value: 'user', child: Text('Один пользователь')),
              if (isLead) const DropdownMenuItem(value: 'group', child: Text('Группа')),
            ],
            onChanged: kind == 'global' || kind == 'emergency' || kind == 'personal'
                ? null : (v) => setDialogState(() => targetType = v ?? 'class'),
          ),
          if (targetType != 'all') TextField(controller: targetId,
            decoration: InputDecoration(labelText: targetType == 'class' ? 'Класс, например 8А' : targetType == 'user' ? 'ID пользователя' : 'ID группы')),
          const SizedBox(height: 6),
          const Text('Экстренное оповещение — дополнительный канал, а не замена школьной системы тревоги.', style: TextStyle(fontSize: 12)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (title.text.trim().isEmpty || body.text.trim().isEmpty || (targetType != 'all' && targetId.text.trim().isEmpty)) return;
            Navigator.pop(dialogContext, {'title': title.text.trim(), 'body': body.text.trim(), 'kind': kind,
              'target_type': targetType, 'target_id': targetType == 'all' ? '' : targetId.text.trim()});
          }, child: const Text('Отправить')),
        ],
      )),
    );
    title.dispose(); body.dispose(); targetId.dispose();
    if (result == null) return;
    await _withBusy(() async {
      final payload = <String, dynamic>{
        'title': result['title'], 'body': result['body'], 'kind': result['kind'],
        'target_type': result['target_type'],
        if ((result['target_id'] ?? '').isNotEmpty) 'target_id': result['target_id'],
      };
      await _request('POST', 'admin/notifications', body: payload);
    });
  }

  Future<void> _createUser() async {
    final login = TextEditingController();
    final password = TextEditingController();
    final name = TextEditingController();
    final classId = TextEditingController();
    final scopeClass = TextEditingController();
    String role = 'teacher';
    String staffPosition = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Создать школьную учётную запись'),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'ФИО / отображаемое имя')),
          TextField(controller: login, decoration: const InputDecoration(labelText: 'Логин школьной системы')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Временный локальный пароль', helperText: 'Минимум 14 символов')),
          DropdownButtonFormField<String>(value: role, decoration: const InputDecoration(labelText: 'Тип аккаунта'),
            items: const [
              DropdownMenuItem(value: 'student', child: Text('Ученик')),
              DropdownMenuItem(value: 'teacher', child: Text('Учитель / сотрудник')),
              DropdownMenuItem(value: 'mentor', child: Text('Наставник')),
              DropdownMenuItem(value: 'admin', child: Text('Администратор')),
            ],
            onChanged: (v) => setDialogState(() {
              role = v ?? 'teacher';
              if (role == 'student') staffPosition = '';
            })),
          if (role == 'student') TextField(controller: classId, decoration: const InputDecoration(labelText: 'Класс ученика')),
          if (role != 'student') ...[
            DropdownButtonFormField<String>(
              value: staffPosition,
              decoration: const InputDecoration(labelText: 'Должность / дополнительные права'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Обычный сотрудник')),
                if (isAdmin) const DropdownMenuItem(value: 'director', child: Text('Директор')),
                if (isAdmin) const DropdownMenuItem(value: 'deputy', child: Text('Завуч')),
                const DropdownMenuItem(value: 'homeroom_teacher', child: Text('Классный руководитель')),
                const DropdownMenuItem(value: 'dop_coordinator', child: Text('Координатор ДОПов')),
                const DropdownMenuItem(value: 'mentor_coordinator', child: Text('Координатор наставников')),
                const DropdownMenuItem(value: 'teacher', child: Text('Учитель-предметник')),
                const DropdownMenuItem(value: 'mentor', child: Text('Наставник')),
                const DropdownMenuItem(value: 'librarian', child: Text('Библиотекарь')),
              ],
              onChanged: (v) => setDialogState(() => staffPosition = v ?? ''),
            ),
            if (staffPosition == 'homeroom_teacher')
              TextField(controller: scopeClass, decoration: const InputDecoration(labelText: 'Закреплённый класс')),
          ],
          const SizedBox(height: 8),
          const Text('Для школьного SSO администратор отдельно связывает логин с неизменяемым идентификатором школьной учётной записи.', style: TextStyle(fontSize: 12)),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (name.text.trim().isEmpty || login.text.trim().length < 3 || password.text.length < 14 || (role == 'student' && classId.text.trim().isEmpty)) return;
            if (role == 'student' && staffPosition.isNotEmpty) return;
            if (staffPosition == 'homeroom_teacher' && scopeClass.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, {'display_name': name.text.trim(), 'username': login.text.trim(),
              'password': password.text, 'role': role, 'class_id': classId.text.trim(),
              'position': staffPosition, 'scope_class': scopeClass.text.trim()});
          }, child: const Text('Создать')),
        ],
      )),
    );
    login.dispose(); password.dispose(); name.dispose(); classId.dispose(); scopeClass.dispose();
    if (result == null) return;
    await _withBusy(() async {
      await _request('POST', 'management/users', body: {
        'display_name': result['display_name'], 'username': result['username'],
        'password': result['password'], 'role': result['role'],
        if ((result['class_id'] ?? '').isNotEmpty) 'class_id': result['class_id'],
      });
      if ((result['position'] ?? '').isNotEmpty) {
        await _request('PUT', 'admin/staff-positions', body: {
          'username': result['username'], 'position': result['position'],
          if ((result['scope_class'] ?? '').isNotEmpty) 'scope_class': result['scope_class'],
        });
      }
    });
  }

  Future<void> _assignStudent(Map<String, dynamic> student) async {
    final subject = TextEditingController();
    String assignmentType = 'mentor';
    String staffId = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) {
        final eligible = users.where((u) => u['role'] == assignmentType && (u['active'] == true || u['active'] == 1)).toList();
        if (staffId.isEmpty || !eligible.any((u) => u['id'].toString() == staffId)) {
          staffId = eligible.isEmpty ? '' : eligible.first['id'].toString();
        }
        return AlertDialog(
          title: Text('Назначить сотрудника: ${student['display_name'] ?? 'ученик'}'),
          content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: assignmentType,
              decoration: const InputDecoration(labelText: 'Тип назначения'),
              items: const [
                DropdownMenuItem(value: 'mentor', child: Text('Наставник')),
                DropdownMenuItem(value: 'teacher', child: Text('Учитель-предметник')),
              ],
              onChanged: (v) => setDialogState(() { assignmentType = v ?? 'mentor'; staffId = ''; }),
            ),
            const SizedBox(height: 10),
            if (eligible.isEmpty)
              const Text('Нет активных сотрудников с выбранным типом аккаунта.')
            else DropdownButtonFormField<String>(
              value: staffId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Сотрудник'),
              items: [for (final staff in eligible) DropdownMenuItem(
                value: staff['id'].toString(),
                child: Text('${staff['display_name'] ?? staff['username']}'),
              )],
              onChanged: (v) => setDialogState(() => staffId = v ?? ''),
            ),
            if (assignmentType == 'teacher') TextField(controller: subject, decoration: const InputDecoration(labelText: 'Предмет')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(onPressed: eligible.isEmpty || staffId.isEmpty || (assignmentType == 'teacher' && subject.text.trim().isEmpty)
                ? null
                : () => Navigator.pop(dialogContext, {'staff_id': staffId, 'assignment_type': assignmentType, 'subject': subject.text.trim()}),
              child: const Text('Назначить')),
          ],
        );
      }),
    );
    subject.dispose();
    if (result == null) return;
    await _withBusy(() async {
      await _request('POST', 'admin/assignments', body: {
        'student_id': student['id'], 'staff_id': result['staff_id'],
        'assignment_type': result['assignment_type'], 'subject': result['subject'] ?? '',
      });
    });
  }

  Future<void> _linkSsoIdentity(Map<String, dynamic> account) async {
    final subject = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Связать школьный SSO'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Аккаунт: ${account['username'] ?? ''}'),
          const SizedBox(height: 8),
          TextField(controller: subject, decoration: const InputDecoration(
            labelText: 'OIDC subject (sub)', helperText: 'Стабильный идентификатор из школьного UserInfo, не email',
          )),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: subject.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, subject.text.trim()), child: const Text('Связать')),
        ],
      ),
    );
    subject.dispose();
    if (result == null) return;
    await _withBusy(() async {
      await _request('POST', 'admin/sso-identities', body: {
        'username': account['username'], 'subject': result,
      });
    });
  }

  Future<void> _toggleUser(Map<String, dynamic> account) async {
    final active = account['active'] == true || account['active'] == 1;
    await _withBusy(() async {
      await _request('PATCH', 'admin/users/${account['id']}', body: {'active': !active});
    });
  }

  String get positionLabel => switch (position) {
    'director' => 'Директор',
    'deputy' => 'Завуч',
    'homeroom_teacher' => 'Классный руководитель',
    'dop_coordinator' => 'Координатор ДОПов',
    'mentor_coordinator' => 'Координатор наставников',
    'teacher' => 'Учитель',
    'mentor' => 'Наставник',
    'librarian' => 'Библиотекарь',
    _ => isAdmin ? 'Администратор' : (user['role']?.toString() ?? 'Сотрудник'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Кабинет школы', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Обновить', onPressed: loading || busy ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
        bottom: loading || error.isNotEmpty ? null : TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'Обзор'),
            Tab(icon: Icon(Icons.groups_rounded), text: 'Ученики'),
            Tab(icon: Icon(Icons.campaign_rounded), text: 'Оповещения'),
            Tab(icon: Icon(Icons.manage_accounts_rounded), text: 'Аккаунты'),
          ],
        ),
      ),
      body: loading ? const Center(child: CircularProgressIndicator())
          : error.isNotEmpty ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline_rounded, size: 48),
                const SizedBox(height: 12),
                Text(error, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Повторить')),
              ]),
            ))
          : TabBarView(controller: _tabs, children: [
              _overview(scheme),
              _studentList(scheme),
              _notificationList(scheme),
              _userList(scheme),
            ]),
      floatingActionButton: busy ? const FloatingActionButton(onPressed: null, child: CircularProgressIndicator())
          : canSendNotifications && _tabs.index == 2
              ? FloatingActionButton.extended(onPressed: _composeNotification, icon: const Icon(Icons.add_alert_rounded), label: const Text('Создать'))
              : canManageUsers && _tabs.index == 3
                  ? FloatingActionButton.extended(onPressed: _createUser, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Аккаунт'))
                  : null,
    );
  }

  Widget _overview(ColorScheme scheme) => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
      CircleAvatar(radius: 26, child: Icon(isAdmin ? Icons.admin_panel_settings_rounded : Icons.school_rounded, size: 28)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(user['display_name']?.toString() ?? user['username']?.toString() ?? 'Пользователь', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(positionLabel, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
        if (scopeClass != null && scopeClass!.isNotEmpty) Text('Зона доступа: класс $scopeClass'),
      ])),
    ]))),
    const SizedBox(height: 12),
    if (counts.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: [
      _stat('Ученики', counts['students']),
      _stat('Сотрудники', counts['staff']),
      if (counts['active_dop_records'] != null) _stat('Активные ДОПы', counts['active_dop_records']),
      _stat('Объявления', counts['announcements']),
    ]),
    const SizedBox(height: 12),
    Card(child: ListTile(leading: const Icon(Icons.security_rounded), title: const Text('Права доступа'), subtitle: Text(permissions.contains('*') ? 'Полный административный доступ' : permissions.isEmpty ? 'Специальные права не назначены' : permissions.join(' • ')))),
    Card(child: ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('Важно'), subtitle: const Text('Доступ к ученикам и дополнительным занятиям ограничивается назначениями. Экстренные сообщения не заменяют школьную систему тревоги.'))),
  ]);

  Widget _stat(String title, dynamic value) => SizedBox(width: 155, child: Card(child: Padding(
    padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value?.toString() ?? '—', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3), Text(title, style: const TextStyle(fontSize: 12)),
    ]),
  )));

  Widget _studentList(ColorScheme scheme) => ListView(padding: const EdgeInsets.all(12), children: [
    if (!canReadStudents) const Card(child: ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Список учеников недоступен для этой роли.'))),
    if (canReadStudents && students.isEmpty) const Card(child: ListTile(title: Text('Нет учеников в назначенной области доступа.'))),
    for (final student in students) Card(child: ListTile(
      leading: CircleAvatar(child: Text((student['display_name']?.toString().isNotEmpty ?? false) ? student['display_name'].toString()[0].toUpperCase() : 'У')),
      title: Text(student['display_name']?.toString() ?? 'Ученик', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('Класс: ${student['class_id'] ?? 'не указан'}'),
      trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
        if (permissions.contains('*') || permissions.contains('assignments.manage'))
          IconButton(tooltip: 'Назначить наставника или учителя', onPressed: busy ? null : () => _assignStudent(student), icon: const Icon(Icons.person_add_alt_1_rounded)),
        const Icon(Icons.chevron_right_rounded),
      ]),
      onTap: () => _openStudent(student),
    )),
  ]);

  Widget _notificationList(ColorScheme scheme) => ListView(padding: const EdgeInsets.all(12), children: [
    if (canSendNotifications) Card(child: ListTile(leading: Icon(Icons.add_alert_rounded, color: scheme.primary), title: const Text('Создать оповещение'), subtitle: const Text('Общее, целевое или личное сообщение с проверкой прав'), onTap: _composeNotification)),
    if (notifications.isEmpty) const Card(child: ListTile(title: Text('Новых оповещений нет.'))),
    for (final n in notifications) Card(child: ListTile(
      leading: Icon(n['kind'] == 'emergency' ? Icons.warning_amber_rounded : Icons.campaign_rounded,
        color: n['kind'] == 'emergency' ? scheme.error : scheme.primary),
      title: Text(n['title']?.toString() ?? 'Оповещение', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${n['body'] ?? ''}\n${n['delivery_status'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
    )),
  ]);

  Widget _userList(ColorScheme scheme) => ListView(padding: const EdgeInsets.all(12), children: [
    if (!canReadUsers) const Card(child: ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Управление аккаунтами недоступно.'))),
    if (canReadUsers && users.isEmpty) const Card(child: ListTile(title: Text('Список аккаунтов недоступен или пока пуст.'))),
    for (final account in users) Card(child: ListTile(
      leading: CircleAvatar(child: Icon(account['role'] == 'student' ? Icons.person_rounded : Icons.badge_rounded)),
      title: Text(account['display_name']?.toString() ?? account['username']?.toString() ?? 'Аккаунт', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${account['role']} • ${account['position'] ?? 'без должности'}${account['class_id'] == null ? '' : ' • ${account['class_id']}'}'),
      trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
        if (isAdmin)
          IconButton(tooltip: 'Связать с школьным SSO', onPressed: busy ? null : () => _linkSsoIdentity(account), icon: const Icon(Icons.key_rounded)),
        if (canManageUsers && account['role'] != 'admin')
          IconButton(
            tooltip: (account['active'] == true || account['active'] == 1) ? 'Отключить аккаунт' : 'Включить аккаунт',
            onPressed: busy ? null : () => _toggleUser(account),
            icon: Icon((account['active'] == true || account['active'] == 1) ? Icons.person_off_rounded : Icons.person_add_alt_1_rounded),
          ),
      ]),
    )),
  ]);
}
