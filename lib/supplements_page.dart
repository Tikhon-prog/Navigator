import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'dop_parser.dart';
import 'dop_catalog_page.dart';
import 'local_notification_service.dart';
import 'school_account_service.dart';

class Supplement {
  final String id;
  final String title;
  final String teacher;
  final String room;
  final String place;
  final String groupName;
  final String description;
  final int weekday;
  final String start;
  final String end;

  const Supplement({
    required this.id,
    required this.title,
    required this.weekday,
    required this.start,
    required this.end,
    required this.teacher,
    required this.room,
    required this.place,
    required this.groupName,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'weekday': weekday,
        'start': start,
        'end': end,
        'teacher': teacher,
        'room': room,
        'place': place,
        'group': groupName,
        'description': description,
      };

  factory Supplement.fromJson(Map<String, dynamic> json) => Supplement(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        start: '${json['start'] ?? ''}',
        end: '${json['end'] ?? ''}',
        teacher: '${json['teacher'] ?? ''}',
        room: '${json['room'] ?? ''}',
        place: '${json['place'] ?? ''}',
        groupName: '${json['group'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

class SupplementsPage extends StatefulWidget {
  final VoidCallback onMenu;
  const SupplementsPage({super.key, required this.onMenu});

  @override
  State<SupplementsPage> createState() => _SupplementsPageState();
}

class _SupplementsPageState extends State<SupplementsPage> {
  int day = DateTime.now().weekday.clamp(1, 6);
  List<Supplement> items = [];
  bool loading = true;
  bool syncing = false;
  DopStudent? student;
  String lastSync = '';
  bool remindersEnabled = false;

  @override
  void initState() {
    super.initState();
    schoolLocalDataRevision.addListener(_reloadAfterLocalAiChange);
    _load();
  }

  void _reloadAfterLocalAiChange() {
    if (!mounted) return;
    setState(() => loading = true);
    _load();
  }

  @override
  void dispose() {
    schoolLocalDataRevision.removeListener(_reloadAfterLocalAiChange);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchoolUser = prefs.getString('school_user_v1');
    var currentSchoolUserId = '';
    final hasSchoolSession =
        rawSchoolUser != null && rawSchoolUser.trim().isNotEmpty;
    if (hasSchoolSession) {
      try {
        final account = jsonDecode(rawSchoolUser);
        final id = account is Map ? (account['id'] ?? '').toString().trim() : '';
        currentSchoolUserId = id.isNotEmpty ? id : 'invalid-school-session';
      } catch (_) {
        currentSchoolUserId = 'invalid-school-session';
      }
    }
    final storageKey = studentProfilePreferenceKey('supplements_local', userId: currentSchoolUserId);
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        items = (jsonDecode(raw) as List)
            .map((e) => Supplement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        items = [];
      }
    } else {
      // Do not import legacy global personal data into an authenticated profile.
      items = [];
    }
    student = await const NavigatorStudentProvider().load();
    lastSync = prefs.getString('dop_last_sync') ?? '';
    final remindersKey = studentProfilePreferenceKey(
      'dop_reminders_enabled',
      userId: currentSchoolUserId,
    );
    remindersEnabled = prefs.getBool(remindersKey) ??
        (!hasSchoolSession ? (prefs.getBool('dop_reminders_enabled') ?? false) : false);
    final cachedSchoolUserId = prefs.getString('school_supplements_user_id_v1_$currentSchoolUserId') ?? '';
    if (currentSchoolUserId.isNotEmpty && cachedSchoolUserId.isNotEmpty &&
        cachedSchoolUserId != currentSchoolUserId) {
      items = items.where((item) => !item.id.startsWith('server_')).toList();
      await prefs.setString(storageKey, jsonEncode(items.map((e) => e.toJson()).toList()));
      await prefs.remove('school_supplements_cache_v1_$currentSchoolUserId');
      await prefs.remove('school_supplements_user_id_v1_$currentSchoolUserId');
    }
    if (mounted) setState(() => loading = false);
    try { await _refreshServerSupplements(); } catch (_) {}
    if (remindersEnabled) {
      try { await _refreshDopReminders(); } catch (_) {}
    }
  }

  Future<void> _refreshServerSupplements() async {
    final service = SchoolAccountService();
    final count = await service.refreshMySupplements();
    if (count == null) return;
    final prefs = await SharedPreferences.getInstance();
    final rawSchoolUser = prefs.getString('school_user_v1');
    var currentSchoolUserId = '';
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        if (account is Map) currentSchoolUserId = (account['id'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (currentSchoolUserId.isEmpty) return;
    final raw = prefs.getString('school_supplements_cache_v1_$currentSchoolUserId');
    if (raw == null) return;
    try {
      final serverItems = (jsonDecode(raw) as List)
          .map((e) => Supplement.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final localItems = items.where((e) => !e.id.startsWith('server_')).toList();
      items = [...localItems, ...serverItems];
      if (mounted) setState(() {});
      await _save();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    var currentSchoolUserId = '';
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        if (account is Map) currentSchoolUserId = (account['id'] ?? '').toString().trim();
      } catch (_) {}
    }
    final storageKey = studentProfilePreferenceKey('supplements_local', userId: currentSchoolUserId);
    await prefs.setString(
      storageKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    if (remindersEnabled) {
      try { await _refreshDopReminders(); } catch (_) {}
    }
  }

  Future<void> _refreshDopReminders({bool clearWhenDisabled = false}) async {
    final service = LocalNotificationService();
    if (remindersEnabled) {
      await service.scheduleUpcomingSupplements(
        entries: items.map((item) => (
          id: item.id,
          day: item.weekday,
          time: item.start,
          title: item.title,
          room: item.room,
        )).toList(),
      );
    } else if (clearWhenDisabled) {
      await service.scheduleUpcomingSupplements(entries: const []);
    }
  }

  Future<void> _setReminders(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchoolUser = prefs.getString('school_user_v1');
    var currentSchoolUserId = '';
    final hasSchoolSession =
        rawSchoolUser != null && rawSchoolUser.trim().isNotEmpty;
    if (hasSchoolSession) {
      try {
        final account = jsonDecode(rawSchoolUser);
        final id = account is Map ? (account['id'] ?? '').toString().trim() : '';
        currentSchoolUserId = id.isNotEmpty ? id : 'invalid-school-session';
      } catch (_) {
        currentSchoolUserId = 'invalid-school-session';
      }
    }
    final remindersKey = studentProfilePreferenceKey(
      'dop_reminders_enabled',
      userId: currentSchoolUserId,
    );
    await prefs.setBool(remindersKey, value);
    if (!hasSchoolSession) {
      await prefs.setBool('dop_reminders_enabled', value);
    }
    if (mounted) setState(() => remindersEnabled = value);
    try {
      await _refreshDopReminders(clearWhenDisabled: !value);
      // When a school account is connected, mirror the preference to the server
      // so server-side reminders can also be delivered while the app is closed.
      try { await SchoolAccountService().setDopRemindersEnabled(value); } catch (_) {}
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить уведомления. Проверь разрешение на уведомления в настройках Android.')),
        );
      }
      return;
    }
    if (value && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напоминания включены для занятий с временем в формате ЧЧ:ММ.')),
      );
    }
  }

  Future<void> _editStudent() async {
    final result = await showDialog<DopStudent>(context: context, builder: (_) => _DopStudentDialog(initial: student));
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    var currentSchoolUserId = '';
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        if (account is Map) currentSchoolUserId = (account['id'] ?? '').toString().trim();
      } catch (_) {}
    }
    for (final entry in <String, String>{
      'student_last_name': result.lastName,
      'student_first_name': result.firstName,
      'student_class_number': result.classNumber,
      'student_class_letter': result.classLetter,
      'student_class_name': result.className,
      'student_profile': result.profile,
    }.entries) {
      await prefs.setString(
        studentProfilePreferenceKey(entry.key, userId: currentSchoolUserId),
        entry.value,
      );
    }
    student = result;
    if (mounted) setState(() {});
  }

  Future<void> _openDopCatalog() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DopCatalogPage(
          onEditStudent: _editStudent,
          onSelectionSubmitted: _syncFromIntranet,
        ),
      ),
    );
  }

  Future<void> _syncFromIntranet() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      if (student == null ||
          (student!.requiresProfile && !student!.hasValidProfile)) {
        await _editStudent();
      }
      if (student == null) {
        throw const DopParserException('Заполни профиль ученика.');
      }
      final result = await const DopParser().parse();
      final imported = <Supplement>[];
      for (final d in result.application.disciplines) {
        for (final slot in d.schedule) {
          imported.add(Supplement(
            id: 'intranet_${d.programId}_${d.subgroupId}_${Uri.encodeComponent(d.name)}_${slot.day}_${slot.start}_${slot.end}',
            title: d.name,
            weekday: slot.day,
            start: 'урок ${slot.start}',
            end: 'урок ${slot.end}',
            teacher: d.teacher,
            room: slot.room,
            place: '',
            groupName: '',
            description: d.supplies ?? '',
          ));
        }
      }
      if (imported.isEmpty) {
        throw const DopParserException('Страница intranet открылась, но расписание занятий не удалось извлечь. Сохранённые данные не изменены.');
      }
      // Preserve new manual IDs and older local entries created before the prefix existed.
      final manual = items.where((e) => !e.id.startsWith('intranet_')).toList();
      items = [...manual, ...imported];
      await _save();
      final prefs = await SharedPreferences.getInstance();
      lastSync = DateTime.now().toLocal().toString().substring(0, 16);
      await prefs.setString('dop_last_sync', lastSync);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Загружено записей ДОПов: ${imported.length}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка intranet: $e')));
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = items.where((e) => e.weekday == day).toList()
      ..sort((a, b) {
        int sortKey(String value) => int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '') ?? 999;
        return sortKey(a.start).compareTo(sortKey(b.start));
      });
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Дополнительные занятия'),
        actions: [
          IconButton(tooltip: 'Профиль ученика', onPressed: _editStudent, icon: const Icon(Icons.person_rounded)),
          IconButton(
            tooltip: syncing ? 'Обновление…' : 'Обновить с intranet',
            onPressed: syncing ? null : _syncFromIntranet,
            icon: syncing
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
          IconButton(tooltip: 'Добавить ДОП', onPressed: _add, icon: const Icon(Icons.add_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [scheme.primaryContainer, scheme.surfaceContainerHigh],
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)),
                            child: Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 26),
                          ),
                          const SizedBox(width: 13),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              student == null ? 'Профиль не заполнен' : '${student!.lastName} ${student!.firstName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              student == null
                                  ? 'Укажи ученика для загрузки занятий'
                                  : student!.requiresProfile
                                      ? 'Класс ${student!.className} • ' +
                                          (student!.hasValidProfile
                                              ? student!.profile
                                              : 'направление не выбрано')
                                      : 'Класс ${student!.className} • мои занятия',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            if (lastSync.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('Обновлено: $lastSync', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                            ],
                          ])),
                          if (syncing)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(onPressed: _editStudent, tooltip: 'Изменить профиль', icon: const Icon(Icons.edit_outlined)),
                        ]),
                      ),
                      if (student?.requiresProfile == true &&
                          !student!.hasValidProfile) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.warning_amber_rounded,
                              color: scheme.error,
                            ),
                            title: const Text(
                              'Для 10 класса нужно указать направление обучения',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Без профиля intranet не отдаёт список доступных ДОПов.',
                            ),
                            trailing: TextButton(
                              onPressed: _editStudent,
                              child: const Text('Выбрать'),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.explore_rounded,
                              color: scheme.primary,
                            ),
                          ),
                          title: const Text(
                            'Каталог новых ДОПов',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(
                            'Посмотри программы, направления и свободные группы',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _openDopCatalog,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: SwitchListTile.adaptive(
                          value: remindersEnabled,
                          onChanged: _setReminders,
                          secondary: Icon(
                            remindersEnabled ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                            color: scheme.primary,
                          ),
                          title: const Text('Напоминания о ДОПах', style: TextStyle(fontWeight: FontWeight.w900)),
                          subtitle: Text(
                            remindersEnabled
                                ? 'За 15 минут • только если указано реальное время'
                                : 'Получай напоминание за 15 минут до занятия',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: Text('Расписание ДОПов', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.3))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(30)),
                          child: Text('${items.length} записей', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1, label: Text('Пн')),
                            ButtonSegment(value: 2, label: Text('Вт')),
                            ButtonSegment(value: 3, label: Text('Ср')),
                            ButtonSegment(value: 4, label: Text('Чт')),
                            ButtonSegment(value: 5, label: Text('Пт')),
                            ButtonSegment(value: 6, label: Text('Сб')),
                          ],
                          selected: {day},
                          onSelectionChanged: (value) => setState(() => day = value.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: current.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Container(
                                      width: 72, height: 72,
                                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(24)),
                                      child: Icon(Icons.event_available_rounded, size: 34, color: scheme.primary),
                                    ),
                                    const SizedBox(height: 15),
                                    const Text('На этот день занятий нет', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 6),
                                    Text('Обнови список с intranet или добавь занятие вручную.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                                    const SizedBox(height: 16),
                                    Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                                      OutlinedButton.icon(onPressed: syncing ? null : _syncFromIntranet, icon: const Icon(Icons.sync_rounded), label: const Text('Обновить')),
                                      FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Добавить')),
                                    ]),
                                  ]),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.only(bottom: 20),
                                itemCount: current.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) => _card(current[index]),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _card(Supplement supplement) {
    final scheme = Theme.of(context).colorScheme;
    final isLessonNumber = supplement.start.startsWith('урок ');
    final startNumber = isLessonNumber ? supplement.start.replaceFirst('урок ', '') : '';
    final endNumber = isLessonNumber ? supplement.end.replaceFirst('урок ', '') : '';
    final timeLabel = isLessonNumber
        ? (endNumber.isEmpty ? 'Урок $startNumber' : 'Уроки $startNumber–$endNumber')
        : (supplement.start.isEmpty ? '' : '${supplement.start}${supplement.end.isNotEmpty ? '–${supplement.end}' : ''}');
    final details = <String>[
      if (supplement.teacher.isNotEmpty) supplement.teacher,
      if (supplement.room.isNotEmpty) 'каб. ${supplement.room}',
      if (supplement.place.isNotEmpty) supplement.place,
      if (supplement.groupName.isNotEmpty) supplement.groupName,
    ].join(' • ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(supplement),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 5, height: 70, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .11), borderRadius: BorderRadius.circular(15)),
              child: Icon(Icons.school_rounded, color: scheme.primary),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(supplement.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              if (timeLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(timeLabel, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
              ],
              if (details.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(details, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35)),
              ],
              if (supplement.description.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(supplement.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ])),
            PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (value) {
                if (value == 'edit') _edit(supplement);
                if (value == 'delete') _delete(supplement);
                if (value == 'route' && supplement.room.isNotEmpty) {
                  final route = RouteEngine.build(supplement.room);
                  final room = SchoolData.tryRoom(supplement.room);
                  if (route != null && room != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePage(room: room, route: route)));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Для этого кабинета пока нет маршрута.')));
                  }
                }
              },
              itemBuilder: (_) => [
                if (supplement.room.isNotEmpty) const PopupMenuItem(value: 'route', child: Text('Как пройти')),
                const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                const PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final result = await showDialog<Supplement>(
      context: context,
      builder: (_) => const _SupplementEditor(),
    );
    if (result != null) {
      setState(() => items.add(result));
      await _save();
    }
  }

  Future<void> _edit(Supplement old) async {
    final result = await showDialog<Supplement>(
      context: context,
      builder: (_) => _SupplementEditor(initial: old),
    );
    if (result != null) {
      final index = items.indexWhere((e) => e.id == old.id);
      if (index >= 0) {
        setState(() => items[index] = result);
        await _save();
      }
    }
  }

  Future<void> _delete(Supplement supplement) async {
    setState(() => items.removeWhere((e) => e.id == supplement.id));
    await _save();
  }
}

class _SupplementEditor extends StatefulWidget {
  final Supplement? initial;

  const _SupplementEditor({this.initial});

  @override
  State<_SupplementEditor> createState() => _SupplementEditorState();
}

class _SupplementEditorState extends State<_SupplementEditor> {
  late int day;
  late final TextEditingController title;
  late final TextEditingController start;
  late final TextEditingController end;
  late final TextEditingController teacher;
  late final TextEditingController room;
  late final TextEditingController place;
  late final TextEditingController group;
  late final TextEditingController description;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    day = item?.weekday ?? DateTime.now().weekday.clamp(1, 6);
    title = TextEditingController(text: item?.title ?? '');
    start = TextEditingController(text: item?.start ?? '');
    end = TextEditingController(text: item?.end ?? '');
    teacher = TextEditingController(text: item?.teacher ?? '');
    room = TextEditingController(text: item?.room ?? '');
    place = TextEditingController(text: item?.place ?? '');
    group = TextEditingController(text: item?.groupName ?? '');
    description = TextEditingController(text: item?.description ?? '');
  }

  @override
  void dispose() {
    for (final controller in [title, start, end, teacher, room, place, group, description]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Новый ДОП' : 'Изменить ДОП'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            children: [
              DropdownButtonFormField<int>(
                initialValue: day,
                decoration: const InputDecoration(labelText: 'День'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Понедельник')),
                  DropdownMenuItem(value: 2, child: Text('Вторник')),
                  DropdownMenuItem(value: 3, child: Text('Среда')),
                  DropdownMenuItem(value: 4, child: Text('Четверг')),
                  DropdownMenuItem(value: 5, child: Text('Пятница')),
                  DropdownMenuItem(value: 6, child: Text('Суббота')),
                ],
                onChanged: (value) => setState(() => day = value ?? day),
              ),
              const SizedBox(height: 8),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
              TextField(controller: start, decoration: const InputDecoration(labelText: 'Начало', hintText: '16:00')),
              TextField(controller: end, decoration: const InputDecoration(labelText: 'Конец', hintText: '17:30')),
              TextField(controller: teacher, decoration: const InputDecoration(labelText: 'Учитель')),
              TextField(controller: room, decoration: const InputDecoration(labelText: 'Кабинет')),
              TextField(controller: place, decoration: const InputDecoration(labelText: 'Место / зона')),
              TextField(controller: group, decoration: const InputDecoration(labelText: 'Группа')),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              Supplement(
                id: widget.initial?.id ?? 'manual_${DateTime.now().microsecondsSinceEpoch}',
                title: title.text.trim(),
                weekday: day,
                start: start.text.trim(),
                end: end.text.trim(),
                teacher: teacher.text.trim(),
                room: room.text.trim(),
                place: place.text.trim(),
                groupName: group.text.trim(),
                description: description.text.trim(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _DopStudentDialog extends StatefulWidget {
  final DopStudent? initial;
  const _DopStudentDialog({this.initial});
  @override
  State<_DopStudentDialog> createState() => _DopStudentDialogState();
}

class _DopStudentDialogState extends State<_DopStudentDialog> {
  late final TextEditingController lastName;
  late final TextEditingController firstName;
  late final TextEditingController classNumber;
  late final TextEditingController classLetter;
  String selectedProfile = '';
  List<String> availableProfiles = DopStudent.grade10Profiles;
  bool profileError = false;
  bool profilesLoading = false;
  bool profilesRequested = false;

  @override
  void initState() {
    super.initState();
    final student = widget.initial;
    lastName = TextEditingController(text: student?.lastName ?? '');
    firstName = TextEditingController(text: student?.firstName ?? '');
    classNumber = TextEditingController(text: student?.classNumber ?? '');
    classLetter = TextEditingController(text: student?.classLetter ?? '');
    if (DopStudent.grade10Profiles.contains(student?.profile)) {
      selectedProfile = student!.profile;
    }
    if (_isGrade10) _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    if (profilesRequested) return;
    profilesRequested = true;
    if (mounted) setState(() => profilesLoading = true);
    final profiles = await const DopParser().loadGrade10Profiles();
    if (!mounted) return;
    final saved = widget.initial?.profile.trim() ?? '';
    setState(() {
      availableProfiles = profiles;
      if (saved.isNotEmpty && profiles.contains(saved)) {
        selectedProfile = saved;
      } else if (!profiles.contains(selectedProfile)) {
        selectedProfile = '';
      }
      profilesLoading = false;
    });
  }

  @override
  void dispose() {
    lastName.dispose();
    firstName.dispose();
    classNumber.dispose();
    classLetter.dispose();
    super.dispose();
  }

  bool get _isGrade10 => classNumber.text.trim() == '10';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Профиль ученика для ДОПов'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Фамилия'),
                ),
                TextField(
                  controller: firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Имя'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: classNumber,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Класс'),
                        onChanged: (value) {
                          setState(() => profileError = false);
                          if (value.trim() == '10') {
                            _loadProfiles();
                          } else {
                            profilesRequested = false;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: classLetter,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'Буква'),
                      ),
                    ),
                  ],
                ),
                if (_isGrade10) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedProfile.isEmpty ? null : selectedProfile,
                    decoration: InputDecoration(
                      labelText: 'Направление обучения (10 класс)',
                      helperText: profilesLoading
                          ? 'Загружаю список направлений школы…'
                          : 'Выбери значение из списка intranet',
                      errorText: profileError ? 'Нужно выбрать направление' : null,
                    ),
                    items: availableProfiles
                        .map((profile) => DropdownMenuItem<String>(
                              value: profile,
                              child: Text(
                                DopStudent.grade10ProfileLabel(profile),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: profilesLoading
                        ? null
                        : (value) => setState(() {
                              selectedProfile = value ?? '';
                              profileError = false;
                            }),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Тип проживания Поколение определит автоматически.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: profilesLoading
                ? null
                : () {
              final grade10 = _isGrade10;
              final validProfile =
                  !grade10 || selectedProfile.trim().isNotEmpty;
              if (lastName.text.trim().isEmpty ||
                  firstName.text.trim().isEmpty ||
                  classNumber.text.trim().isEmpty ||
                  classLetter.text.trim().isEmpty ||
                  !validProfile) {
                setState(() => profileError = grade10 && !validProfile);
                return;
              }
              Navigator.pop(
                context,
                DopStudent(
                  lastName: lastName.text.trim(),
                  firstName: firstName.text.trim(),
                  classNumber: classNumber.text.trim(),
                  classLetter: classLetter.text.trim().toUpperCase(),
                  profile: grade10 ? selectedProfile : '',
                  residenceType: 'auto',
                ),
              );
            },
            child: const Text('Сохранить'),
          ),
        ],
      );
}
