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
  late final TabController _tabs = TabController(length: 5, vsync: this);
  bool loading = true;
  bool busy = false;
  String error = '';
  String baseUrl = '';
  String accessToken = '';
  Map<String, dynamic> user = {};
  Map<String, dynamic> counts = {};
  Map<String, dynamic> syncStatus = {};
  String? position;
  String? scopeClass;
  List<String> permissions = [];
  List<Map<String, dynamic>> students = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> notificationGroups = [];
  List<Map<String, dynamic>> auditEvents = [];

  bool get isAdmin => user['role'] == 'admin';
  bool get isLeadership => isAdmin || const {'director', 'deputy'}.contains(position);
  bool get canManageUsers => permissions.contains('*') || permissions.contains('staff.manage');
  bool get canManageDop => permissions.contains('*') || permissions.contains('dop.manage');
  bool get canManageGroups => permissions.contains('*') || permissions.contains('assignments.manage');
  bool get canReadUsers => permissions.contains('*') || permissions.contains('staff.read');
  bool get canSeeStaffList => canReadUsers || permissions.contains('assignments.manage');
  bool get canReadAudit => permissions.contains('*') || permissions.contains('audit.read');
  bool get canSendNotifications =>
      isLeadership ||
      const {'homeroom_teacher', 'dop_coordinator'}.contains(position) ||
      user['role'] == 'teacher' ||
      user['role'] == 'mentor';
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
    final parts = suffix.split('?');
    final endpoint = parts.first;
    final queryParameters = parts.length > 1 ? Uri.splitQueryString(parts.sublist(1).join('?')) : null;
    var path = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) {
      path = path.substring(0, path.length - '/api/v2'.length);
    }
    if (path.endsWith('/api')) {
      path = '$path/v2/$endpoint';
    } else {
      path = '$path/api/v2/$endpoint';
    }
    return base.replace(path: path, queryParameters: queryParameters, fragment: '', userInfo: '');
  }

  Future<dynamic> _request(String method, String suffix, {Map<String, dynamic>? body}) async {
    final freshToken = await SchoolAccountService().validAccessToken();
    if (freshToken != null && freshToken.isNotEmpty) accessToken = freshToken;
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
      if (canReadAudit) futures.add(_loadAudit());
      if (canManageGroups) futures.add(_loadGroups());
      if (permissions.contains('*') || permissions.contains('dop.read_all')) futures.add(_loadSyncStatus());
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

  Future<void> _loadSyncStatus() async {
    try {
      syncStatus = Map<String, dynamic>.from(await _request('GET', 'management/sync/status') as Map);
    } catch (_) { syncStatus = {}; }
  }

  Future<void> _loadAudit() async {
    try {
      final result = await _request('GET', 'management/audit?limit=100') as Map;
      auditEvents = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) { auditEvents = []; }
  }

  Future<void> _loadNotifications() async {
    try {
      final result = await _request('GET', 'notifications') as Map;
      notifications = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) { notifications = []; }
  }

  Future<void> _loadGroups() async {
    if (!canManageGroups) {
      notificationGroups = [];
      return;
    }
    try {
      final result = await _request('GET', 'admin/notification-groups') as Map;
      notificationGroups = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (_) {
      notificationGroups = [];
    }
  }

  Future<void> _createNotificationGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Создать группу рассылки'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Название группы', hintText: 'Например, Олимпиада по математике'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (controller.text.trim().isNotEmpty) Navigator.pop(dialogContext, controller.text.trim());
          }, child: const Text('Создать')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await _request('POST', 'admin/notification-groups', body: {'name': name.trim()});
      await _loadGroups();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Группа создана.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _addNotificationGroupMember(Map<String, dynamic> group) async {
    final candidatesById = <String, Map<String, dynamic>>{};
    for (final account in [...students, ...users]) {
      final id = (account['id'] ?? '').toString();
      final active = account['active'];
      if (id.isEmpty || (active != null && active != true && active != 1)) continue;
      candidatesById[id] = account;
    }
    final candidates = candidatesById.values.toList()
      ..sort((a, b) => (a['display_name'] ?? a['username'] ?? '')
          .toString().compareTo((b['display_name'] ?? b['username'] ?? '').toString()));
    if (candidates.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала загрузите список учеников и сотрудников.')));
      return;
    }
    String selectedId = candidates.first['id'].toString();
    final memberId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('Добавить участника • ${group['name'] ?? 'группа'}'),
        content: SizedBox(width: 460, child: DropdownButtonFormField<String>(
          value: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Ученик или сотрудник'),
          items: [for (final account in candidates)
            DropdownMenuItem(
              value: account['id'].toString(),
              child: Text(
                '${account['display_name'] ?? account['username'] ?? 'Пользователь'}'
                ' • ${account['role'] ?? '—'}'
                '${account['class_id'] == null ? '' : ' • ${account['class_id']}'}',
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            )],
          onChanged: (value) => setDialogState(() => selectedId = value ?? candidates.first['id'].toString()),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, selectedId), child: const Text('Добавить')),
        ],
      )),
    );
    if (memberId == null) return;
    try {
      await _request('POST', 'admin/notification-groups/${group['id']}/members', body: {'user_id': memberId});
      await _loadGroups();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Участник добавлен в группу.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _manageNotificationGroupMembers(Map<String, dynamic> group, void Function(void Function()) refreshDialog) async {
    List<Map<String, dynamic>> members = [];
    try {
      final result = await _request('GET', 'admin/notification-groups/${group['id']}/members') as Map;
      members = (result['data'] as List? ?? const []).whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setMemberState) => AlertDialog(
        title: Text('Участники • ${group['name'] ?? 'группа'}'),
        content: SizedBox(width: 480, height: MediaQuery.sizeOf(context).height * .55,
          child: members.isEmpty ? const Center(child: Text('В группе пока никого нет.')) : ListView(children: [
            for (final member in members)
              ListTile(
                leading: CircleAvatar(child: Icon(member['role'] == 'student' ? Icons.school_rounded : Icons.badge_rounded)),
                title: Text(member['display_name']?.toString() ?? member['username']?.toString() ?? 'Пользователь'),
                subtitle: Text('${member['role'] ?? ''}${member['class_id'] == null ? '' : ' • ${member['class_id']}'}'),
                trailing: IconButton(
                  tooltip: 'Удалить из группы',
                  icon: const Icon(Icons.person_remove_alt_1_rounded),
                  onPressed: () async {
                    try {
                      await _request('DELETE', 'admin/notification-groups/${group['id']}/members/${member['id']}');
                      members.removeWhere((item) => item['id'] == member['id']);
                      setMemberState(() {});
                      await _loadGroups();
                      refreshDialog(() {});
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                    }
                  },
                ),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
      )),
    );
  }

  Future<void> _deleteNotificationGroup(Map<String, dynamic> group, void Function(void Function()) refreshDialog) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: Text('Группа «${group['name'] ?? ''}» и её состав будут удалены. Уже отправленные сообщения не изменятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _request('DELETE', 'admin/notification-groups/${group['id']}');
      await _loadGroups();
      refreshDialog(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _manageNotificationGroups() async {
    await _loadGroups();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Группы рассылки'),
        content: SizedBox(width: 520, height: MediaQuery.sizeOf(context).height * .62,
          child: notificationGroups.isEmpty
              ? const Center(child: Text('Групп пока нет. Создай первую группу.'))
              : ListView(children: [
                  for (final group in notificationGroups)
                    Card(child: ListTile(
                      title: Text(group['name']?.toString() ?? 'Группа', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('Участников: ${group['member_count'] ?? 0}'),
                      trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'Добавить участника', onPressed: () async {
                          await _addNotificationGroupMember(group);
                          await _loadGroups();
                          setDialogState(() {});
                        }, icon: const Icon(Icons.person_add_alt_1_rounded)),
                        IconButton(tooltip: 'Состав группы', onPressed: () async {
                          await _manageNotificationGroupMembers(group, setDialogState);
                          await _loadGroups();
                          setDialogState(() {});
                        }, icon: const Icon(Icons.groups_rounded)),
                        IconButton(tooltip: 'Удалить группу', onPressed: () => _deleteNotificationGroup(group, setDialogState), icon: const Icon(Icons.delete_outline_rounded)),
                      ]),
                    )),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть')),
          FilledButton.icon(onPressed: () async {
            await _createNotificationGroup();
            setDialogState(() {});
          }, icon: const Icon(Icons.add_rounded), label: const Text('Создать группу')),
        ],
      )),
    );
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
      final action = await showDialog<String>(
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
                  trailing: canManageDop ? IconButton(
                    tooltip: 'Удалить ДОП',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => Navigator.pop(dialogContext, 'delete:${item['id']}'),
                  ) : null,
                ),
            ],
          ))),
          actions: [
            if (canManageDop)
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(dialogContext, 'add_dop'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить ДОП'),
              ),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Закрыть')),
          ],
        ),
      );
      if (action == 'add_dop' && canManageDop && mounted) {
        await _addSupplement(id);
        if (mounted) await _openStudent(student);
      } else if (action != null && action.startsWith('delete:') && canManageDop && mounted) {
        final supplementId = action.substring('delete:'.length);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Удалить ДОП?'),
            content: const Text('Запись будет удалена, а ожидающее серверное напоминание отменено.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
            ],
          ),
        );
        if (confirmed == true) {
          await _withBusy(() async {
            await _request('DELETE', 'management/supplements/$supplementId');
          });
          if (mounted) await _openStudent(student);
        } else if (mounted) {
          await _openStudent(student);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _addSupplement(String studentId) async {
    final title = TextEditingController();
    final time = TextEditingController();
    final teacher = TextEditingController();
    final room = TextEditingController();
    int weekday = 1;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Добавить дополнительное занятие'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Название занятия')),
          DropdownButtonFormField<int>(
            value: weekday,
            decoration: const InputDecoration(labelText: 'День недели'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Понедельник')),
              DropdownMenuItem(value: 2, child: Text('Вторник')),
              DropdownMenuItem(value: 3, child: Text('Среда')),
              DropdownMenuItem(value: 4, child: Text('Четверг')),
              DropdownMenuItem(value: 5, child: Text('Пятница')),
              DropdownMenuItem(value: 6, child: Text('Суббота')),
              DropdownMenuItem(value: 7, child: Text('Воскресенье')),
            ],
            onChanged: (v) => setDialogState(() => weekday = v ?? 1),
          ),
          TextField(controller: time, decoration: const InputDecoration(labelText: 'Время начала', hintText: '15:30')),
          TextField(controller: teacher, decoration: const InputDecoration(labelText: 'Педагог / наставник')),
          TextField(controller: room, decoration: const InputDecoration(labelText: 'Кабинет / место')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, {'title': title.text.trim(), 'weekday': weekday,
              'time': time.text.trim(), 'teacher': teacher.text.trim(), 'room': room.text.trim()});
          }, child: const Text('Сохранить')),
        ],
      )),
    );
    title.dispose(); time.dispose(); teacher.dispose(); room.dispose();
    if (result == null) return;
    await _withBusy(() async {
      await _request('POST', 'management/students/$studentId/supplements', body: result);
    });
  }

  Future<void> _composeNotification() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final targetId = TextEditingController();
    final classOptions = students
        .map((student) => student['class_id']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    String kind = 'targeted';
    final isLead = isLeadership;
    String targetType = isLead || const {'homeroom_teacher', 'dop_coordinator'}.contains(position) ? 'class' : 'user';
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
              final previousTarget = targetType;
              kind = v ?? 'targeted';
              if (kind == 'global' || kind == 'emergency') targetType = 'all';
              else if (kind == 'personal') targetType = 'user';
              else if (targetType == 'all') {
                targetType = isLead || const {'homeroom_teacher', 'dop_coordinator'}.contains(position)
                    ? 'class' : 'user';
              }
              if (targetType != previousTarget) targetId.clear();
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: targetType,
            decoration: const InputDecoration(labelText: 'Кому'),
            items: [
              if (isLead) const DropdownMenuItem(value: 'all', child: Text('Вся школа')),
              if (isLead || const {'homeroom_teacher', 'dop_coordinator'}.contains(position))
                const DropdownMenuItem(value: 'class', child: Text('Класс')),
              const DropdownMenuItem(value: 'user', child: Text('Один пользователь')),
              if (isLead || canManageGroups) const DropdownMenuItem(value: 'group', child: Text('Группа')),
            ],
            onChanged: kind == 'global' || kind == 'emergency' || kind == 'personal'
                ? null : (v) => setDialogState(() {
                    targetType = v ?? 'class';
                    targetId.clear();
                  }),
          ),
          if (targetType == 'group' && notificationGroups.isNotEmpty)
            DropdownButtonFormField<String>(
              value: notificationGroups.any((group) => group['id']?.toString() == targetId.text)
                  ? targetId.text : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Группа рассылки'),
              items: [for (final group in notificationGroups)
                DropdownMenuItem(
                  value: group['id'].toString(),
                  child: Text('${group['name'] ?? 'Группа'} • ${group['member_count'] ?? 0} участников'),
                )],
              onChanged: (value) => setDialogState(() => targetId.text = value ?? ''),
            )
          else if (targetType == 'class' && classOptions.isNotEmpty)
            DropdownButtonFormField<String>(
              value: classOptions.contains(targetId.text) ? targetId.text : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Класс-получатель'),
              items: [for (final className in classOptions)
                DropdownMenuItem(value: className, child: Text(className))],
              onChanged: (value) => setDialogState(() => targetId.text = value ?? ''),
            )
          else if (targetType == 'user' && students.isNotEmpty)
            DropdownButtonFormField<String>(
              value: students.any((student) => student['id']?.toString() == targetId.text)
                  ? targetId.text : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Получатель'),
              items: [for (final student in students)
                DropdownMenuItem(
                  value: student['id'].toString(),
                  child: Text('${student['display_name'] ?? student['username'] ?? 'Ученик'} • ${student['class_id'] ?? 'класс не указан'}'),
                )],
              onChanged: (value) => setDialogState(() => targetId.text = value ?? ''),
            )
          else if (targetType != 'all')
            TextField(controller: targetId,
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

  Future<void> _syncTeacherAssignments() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = Map<String, dynamic>.from(await _request('POST', 'management/sync/teacher-assignments') as Map);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Назначения учителей: импортировано ${result['imported'] ?? 0}, пропущено ${result['skipped'] ?? 0}.'),
          duration: const Duration(seconds: 6),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _linkScheduleTeacherName(Map<String, dynamic> account) async {
    final sourceName = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Сопоставить имя учителя в расписании'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Аккаунт: ${account['display_name'] ?? account['username'] ?? ''}'),
          const SizedBox(height: 8),
          TextField(controller: sourceName, decoration: const InputDecoration(
            labelText: 'Имя из BaseSchedule', helperText: 'Точное значение столбца «Учитель»',
          )),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (sourceName.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, sourceName.text.trim());
          }, child: const Text('Сохранить')),
        ],
      ),
    );
    sourceName.dispose();
    if (result == null) return;
    await _withBusy(() async {
      await _request('PUT', 'admin/schedule-teacher-aliases', body: {
        'source_name': result, 'staff_id': account['id'],
      });
    });
  }

  Future<void> _syncDops() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = Map<String, dynamic>.from(await _request('POST', 'management/sync/supplements') as Map);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Синхронизация ДОПов: обновлено ${result['imported_or_updated'] ?? 0}, пропущено ${result['skipped'] ?? 0}.'),
          duration: const Duration(seconds: 6),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
              if (isAdmin) const DropdownMenuItem(value: 'admin', child: Text('Технический администратор')),
            ],
            onChanged: (v) => setDialogState(() {
              role = v ?? 'teacher';
              const teacherPositions = {'director', 'deputy', 'homeroom_teacher', 'dop_coordinator', 'mentor_coordinator', 'teacher', 'librarian'};
              const mentorPositions = {'mentor', 'mentor_coordinator'};
              if (role == 'student' || role == 'admin' ||
                  (role == 'teacher' && staffPosition == 'mentor') ||
                  (role == 'mentor' && staffPosition.isNotEmpty && !mentorPositions.contains(staffPosition)) ||
                  (role == 'teacher' && staffPosition.isNotEmpty && !teacherPositions.contains(staffPosition))) {
                staffPosition = '';
              }
            })),
          if (role == 'student') TextField(controller: classId, decoration: const InputDecoration(labelText: 'Класс ученика')),
          if (role != 'student') ...[
            DropdownButtonFormField<String>(
              value: staffPosition,
              decoration: const InputDecoration(labelText: 'Должность / дополнительные права'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Обычный сотрудник')),
                if (role == 'teacher' && isAdmin) const DropdownMenuItem(value: 'director', child: Text('Директор')),
                if (role == 'teacher' && isAdmin) const DropdownMenuItem(value: 'deputy', child: Text('Завуч')),
                if (role == 'teacher') const DropdownMenuItem(value: 'homeroom_teacher', child: Text('Классный руководитель')),
                if (role == 'teacher') const DropdownMenuItem(value: 'dop_coordinator', child: Text('Координатор ДОПов')),
                if (role == 'mentor') const DropdownMenuItem(value: 'mentor_coordinator', child: Text('Координатор наставников')),
                if (role == 'teacher') const DropdownMenuItem(value: 'teacher', child: Text('Учитель-предметник')),
                if (role == 'teacher') const DropdownMenuItem(value: 'librarian', child: Text('Библиотекарь')),
                if (role == 'mentor') const DropdownMenuItem(value: 'mentor', child: Text('Наставник')),
                if (role == 'mentor') const DropdownMenuItem(value: 'mentor_coordinator', child: Text('Координатор наставников')),
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

  Future<void> _assignPosition(Map<String, dynamic> account) async {
    final username = (account['username'] ?? '').toString();
    final currentPosition = (account['position'] ?? '').toString();
    if (!isAdmin && const {'director', 'deputy'}.contains(currentPosition)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Высшие должности может менять только технический администратор.')));
      return;
    }
    final scopeClass = TextEditingController(text: (account['scope_class'] ?? '').toString());
    final accountRole = (account['role'] ?? '').toString();
    String position = currentPosition;
    final allowed = <String>{''};
    if (accountRole == 'teacher') {
      allowed.addAll({'teacher', 'homeroom_teacher', 'dop_coordinator', 'librarian'});
      if (isAdmin) allowed.addAll({'director', 'deputy'});
    } else if (accountRole == 'mentor') {
      allowed.addAll({'mentor', 'mentor_coordinator'});
    }
    if (!allowed.contains(position)) position = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text('Должность: ${account['display_name'] ?? username}'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: position,
            decoration: const InputDecoration(labelText: 'Должность'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Без отдельной должности')),
              if (accountRole == 'teacher') const DropdownMenuItem(value: 'teacher', child: Text('Учитель-предметник')),
              if (accountRole == 'teacher') const DropdownMenuItem(value: 'homeroom_teacher', child: Text('Классный руководитель')),
              if (accountRole == 'teacher') const DropdownMenuItem(value: 'dop_coordinator', child: Text('Координатор ДОПов')),
              if (accountRole == 'mentor') const DropdownMenuItem(value: 'mentor_coordinator', child: Text('Координатор наставников')),
              if (accountRole == 'mentor') const DropdownMenuItem(value: 'mentor', child: Text('Наставник')),
              if (accountRole == 'teacher') const DropdownMenuItem(value: 'librarian', child: Text('Библиотекарь')),
              if (isAdmin && accountRole == 'teacher') const DropdownMenuItem(value: 'director', child: Text('Директор')),
              if (isAdmin && accountRole == 'teacher') const DropdownMenuItem(value: 'deputy', child: Text('Завуч')),
            ],
            onChanged: (value) => setDialogState(() => position = value ?? ''),
          ),
          if (position == 'homeroom_teacher')
            TextField(controller: scopeClass, decoration: const InputDecoration(labelText: 'Закреплённый класс')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (position == 'homeroom_teacher' && scopeClass.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, {'position': position, 'scope_class': scopeClass.text.trim()});
          }, child: const Text('Сохранить')),
        ],
      )),
    );
    scopeClass.dispose();
    if (result == null) return;
    await _withBusy(() async {
      if ((result['position'] ?? '').isEmpty) {
        if (currentPosition.isNotEmpty) {
          await _request('DELETE', 'admin/staff-positions/$username');
        }
      } else {
        await _request('PUT', 'admin/staff-positions', body: {
          'username': username, 'position': result['position'],
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
            if (assignmentType == 'teacher') TextField(
              controller: subject,
              decoration: const InputDecoration(labelText: 'Предмет'),
              onChanged: (_) => setDialogState(() {}),
            ),
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
          FilledButton(onPressed: () {
            if (subject.text.trim().isEmpty) return;
            Navigator.pop(dialogContext, subject.text.trim());
          }, child: const Text('Связать')),
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
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Аудит'),
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
              _auditList(scheme),
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
    if (syncStatus.isNotEmpty) ...[
      Card(child: ListTile(
        leading: const Icon(Icons.sync_rounded),
        title: const Text('Источник школьных данных'),
        subtitle: Text(
          'Источник: ${syncStatus['configured_source'] ?? 'не указан'}'
          '\nАвтосинхронизация: ${(syncStatus['automatic_sync_interval_seconds'] as num?) == null || (syncStatus['automatic_sync_interval_seconds'] as num) <= 0 ? 'выключена' : 'каждые ${syncStatus['automatic_sync_interval_seconds']} с'}'
          '\nПоследний запуск: ${(syncStatus['last_run'] as Map?)?['created_at'] ?? 'ещё не выполнялась'}',
        ),
      )),
      for (final entry in [
        ('ДОПы', syncStatus['last_supplements']),
        ('Назначения учителей', syncStatus['last_teacher_assignments']),
        ('Автоматическая синхронизация', syncStatus['last_failure']),
      ])
        if (entry.$2 is Map)
          Card(child: ListTile(
            leading: Icon(
              (((entry.$2 as Map)['result_json']?.toString() ?? '').contains('failed'))
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
            ),
            title: Text(entry.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              'Последний запуск: ${(entry.$2 as Map)['created_at'] ?? '—'}'
              '\nИсточник: ${(entry.$2 as Map)['source'] ?? '—'}'
              '\nИмпортировано: ${(entry.$2 as Map)['imported'] ?? 0} • пропущено: ${(entry.$2 as Map)['skipped'] ?? 0}',
            ),
          )),
    ],
    if (permissions.contains('*') || permissions.contains('dop.manage'))
      Card(child: ListTile(
        leading: Icon(Icons.sync_rounded, color: scheme.primary),
        title: const Text('Синхронизировать ДОПы'),
        subtitle: const Text('Импортировать записи учеников из источника, заданного в .env'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: busy ? null : _syncDops,
      )),
    if (permissions.contains('*') || permissions.contains('assignments.manage'))
      Card(child: ListTile(
        leading: Icon(Icons.assignment_ind_rounded, color: scheme.primary),
        title: const Text('Синхронизировать назначения учителей'),
        subtitle: const Text('Связать учеников с учителями по классу и предмету из BaseSchedule'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: busy ? null : _syncTeacherAssignments,
      )),
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
    if (canManageGroups) Card(child: ListTile(
      leading: Icon(Icons.groups_rounded, color: scheme.primary),
      title: const Text('Группы рассылки'),
      subtitle: Text(notificationGroups.isEmpty ? 'Создать группы и назначить участников' : '${notificationGroups.length} групп • управление составом и получателями'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: _manageNotificationGroups,
    )),
    if (notifications.isEmpty) const Card(child: ListTile(title: Text('Новых оповещений нет.'))),
    for (final n in notifications) Card(child: ListTile(
      leading: Icon(n['kind'] == 'emergency' ? Icons.warning_amber_rounded : Icons.campaign_rounded,
        color: n['kind'] == 'emergency' ? scheme.error : scheme.primary),
      title: Text(n['title']?.toString() ?? 'Оповещение', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${n['body'] ?? ''}\n${n['delivery_status'] ?? ''}', maxLines: 4, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
    )),
  ]);

  Widget _auditList(ColorScheme scheme) => ListView(padding: const EdgeInsets.all(12), children: [
    if (!canReadAudit)
      const Card(child: ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Просмотр журнала доступен только уполномоченным сотрудникам.'))),
    if (canReadAudit && auditEvents.isEmpty)
      const Card(child: ListTile(title: Text('Записей аудита пока нет.'))),
    for (final event in auditEvents)
      Card(child: ListTile(
        leading: const Icon(Icons.history_rounded),
        title: Text(event['action']?.toString() ?? 'Событие', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${event['created_at'] ?? ''} • ${event['actor_id'] ?? 'system'}\nОбъект: ${event['target_id'] ?? '—'}',
          maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
      )),
  ]);

  Widget _userList(ColorScheme scheme) => ListView(padding: const EdgeInsets.all(12), children: [
    if (!canSeeStaffList) const Card(child: ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Список сотрудников недоступен.'))),
    if (canSeeStaffList && users.isEmpty) const Card(child: ListTile(title: Text('Список сотрудников недоступен или пока пуст.'))),
    for (final account in users) Card(child: ListTile(
      leading: CircleAvatar(child: Icon(account['role'] == 'student' ? Icons.person_rounded : Icons.badge_rounded)),
      title: Text(account['display_name']?.toString() ?? account['username']?.toString() ?? 'Аккаунт', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${account['role']} • ${account['position'] ?? 'без должности'}${account['class_id'] == null ? '' : ' • ${account['class_id']}'}'),
      trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
        if (isAdmin)
          IconButton(tooltip: 'Связать с школьным SSO', onPressed: busy ? null : () => _linkSsoIdentity(account), icon: const Icon(Icons.key_rounded)),
        if ((permissions.contains('*') || permissions.contains('assignments.manage')) && account['role'] == 'teacher')
          IconButton(tooltip: 'Сопоставить имя в расписании', onPressed: busy ? null : () => _linkScheduleTeacherName(account), icon: const Icon(Icons.badge_outlined)),
        if (canManageUsers && account['id']?.toString() != user['id']?.toString() &&
            const {'teacher', 'mentor'}.contains(account['role']) &&
            (isAdmin || !const {'director', 'deputy'}.contains(account['position'])))
          IconButton(tooltip: 'Изменить должность', onPressed: busy ? null : () => _assignPosition(account), icon: const Icon(Icons.manage_accounts_outlined)),
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
