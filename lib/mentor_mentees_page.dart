import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart' show SchoolScheduleCatalog;
import 'school_account_service.dart';
import 'schedule_time.dart';

const _mentorDays = <int, String>{
  1: 'Понедельник', 2: 'Вторник', 3: 'Среда',
  4: 'Четверг', 5: 'Пятница', 6: 'Суббота',
};

class MentorPlanEntry {
  final String id;
  final int day;
  final String title;
  final String time;
  final String teacher;
  final String room;
  final String group;
  final String notes;

  const MentorPlanEntry({
    required this.id, required this.day, required this.title,
    required this.time, this.teacher = '', this.room = '',
    this.group = '', this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'day': day, 'title': title, 'time': time,
    'teacher': teacher, 'room': room, 'group': group, 'notes': notes,
  };

  factory MentorPlanEntry.fromJson(Map<String, dynamic> value) => MentorPlanEntry(
    id: (value['id'] ?? '').toString(),
    day: (value['day'] as num?)?.toInt() ?? 1,
    title: (value['title'] ?? '').toString(),
    time: (value['time'] ?? '').toString(),
    teacher: (value['teacher'] ?? '').toString(),
    room: (value['room'] ?? '').toString(),
    group: (value['group'] ?? '').toString(),
    notes: (value['notes'] ?? '').toString(),
  );
}

class MentorMentee {
  final String id, lastName, firstName, middleName, grade, letter, profile, notes;
  final Set<int> selectedDays;
  final List<MentorPlanEntry> lessons, supplements;

  const MentorMentee({
    required this.id, required this.lastName, required this.firstName,
    this.middleName = '', required this.grade, required this.letter,
    this.profile = '', this.notes = '', this.selectedDays = const {},
    this.lessons = const [], this.supplements = const [],
  });

  String get className => '$grade$letter';
  String get fullName => [lastName, firstName, middleName]
      .where((part) => part.trim().isNotEmpty).join(' ');

  MentorMentee copyWith({
    String? lastName, String? firstName, String? middleName,
    String? grade, String? letter, String? profile, String? notes,
    Set<int>? selectedDays, List<MentorPlanEntry>? lessons,
    List<MentorPlanEntry>? supplements,
  }) => MentorMentee(
    id: id, lastName: lastName ?? this.lastName,
    firstName: firstName ?? this.firstName,
    middleName: middleName ?? this.middleName,
    grade: grade ?? this.grade, letter: letter ?? this.letter,
    profile: profile ?? this.profile, notes: notes ?? this.notes,
    selectedDays: selectedDays ?? this.selectedDays,
    lessons: lessons ?? this.lessons,
    supplements: supplements ?? this.supplements,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'last_name': lastName, 'first_name': firstName,
    'middle_name': middleName, 'grade': grade, 'letter': letter,
    'profile': profile, 'notes': notes,
    'selected_days': selectedDays.toList()..sort(),
    'lessons': lessons.map((item) => item.toJson()).toList(),
    'supplements': supplements.map((item) => item.toJson()).toList(),
  };

  factory MentorMentee.fromJson(Map<String, dynamic> value) => MentorMentee(
    id: (value['id'] ?? '').toString(),
    lastName: (value['last_name'] ?? '').toString(),
    firstName: (value['first_name'] ?? '').toString(),
    middleName: (value['middle_name'] ?? '').toString(),
    grade: (value['grade'] ?? '').toString(),
    letter: (value['letter'] ?? '').toString(),
    profile: (value['profile'] ?? '').toString(),
    notes: (value['notes'] ?? '').toString(),
    selectedDays: (value['selected_days'] as List? ?? const [])
        .whereType<num>().map((day) => day.toInt())
        .where(_mentorDays.containsKey).toSet(),
    lessons: (value['lessons'] as List? ?? const []).whereType<Map>()
        .map((item) => MentorPlanEntry.fromJson(Map<String, dynamic>.from(item))).toList(),
    supplements: (value['supplements'] as List? ?? const []).whereType<Map>()
        .map((item) => MentorPlanEntry.fromJson(Map<String, dynamic>.from(item))).toList(),
  );
}

/// Локальная база наставника: персональные данные не отправляются в API.
class MentorMenteesPage extends StatefulWidget {
  const MentorMenteesPage({super.key});

  static Uri _permissionsUri(String rawBase) {
    final base = Uri.parse(rawBase.trim());
    var path = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/api/v2')) path = path.substring(0, path.length - 7);
    path = path.endsWith('/api') ? '$path/v2/auth/permissions' : '$path/api/v2/auth/permissions';
    return base.replace(path: path, query: null, fragment: '', userInfo: '');
  }

  static Future<bool> canAccessForCurrentUser() async {
    final service = SchoolAccountService();
    final user = await service.currentUser();
    if (user == null || (user['id'] ?? '').toString().trim().isEmpty) return false;
    if ((user['role'] ?? '').toString() == 'mentor' ||
        (user['position'] ?? '').toString() == 'mentor') return true;
    if ((user['role'] ?? '').toString() != 'teacher') return false;

    final prefs = await SharedPreferences.getInstance();
    final base = (prefs.getString('school_api_base_url_v1') ??
        prefs.getString('navigator_api_url') ?? '').trim();
    final token = await service.validAccessToken();
    if (base.isEmpty || token == null || token.isEmpty) return false;
    try {
      final response = await http.get(
        _permissionsUri(base),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body);
      return payload is Map && payload['position'] == 'mentor';
    } catch (_) {
      return false;
    }
  }

  @override
  State<MentorMenteesPage> createState() => _MentorMenteesPageState();
}

class _MentorMenteesPageState extends State<MentorMenteesPage> {
  List<MentorMentee> mentees = [];
  bool loading = true, allowed = false;
  String ownerId = '', query = '', error = '';
  String get storageKey => 'mentor_mentees_local_v1_$ownerId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = ''; });
    try {
      final service = SchoolAccountService();
      final user = await service.currentUser();
      final id = (user?['id'] ?? '').toString().trim();
      final hasAccess = id.isNotEmpty && await MentorMenteesPage.canAccessForCurrentUser();
      if (!mounted) return;
      if (!hasAccess) {
        setState(() { allowed = false; loading = false; mentees = []; });
        return;
      }
      await SchoolScheduleCatalog.load();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('mentor_mentees_local_v1_$id');
      final decoded = raw == null ? const [] : jsonDecode(raw);
      final items = decoded is List
          ? decoded.whereType<Map>().map((item) =>
              MentorMentee.fromJson(Map<String, dynamic>.from(item))).toList()
          : <MentorMentee>[];
      items.sort((a, b) => a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase()));
      setState(() {
        ownerId = id; mentees = items; allowed = true; loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { loading = false; error = 'Не удалось загрузить локальные данные: $e'; });
    }
  }

  Future<void> _save() async {
    if (ownerId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(mentees.map((item) => item.toJson()).toList()));
  }

  List<MentorMentee> get visible {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return mentees;
    return mentees.where((item) =>
      ('${item.fullName} ${item.className} ${item.profile}').toLowerCase().contains(q)
    ).toList();
  }

  Future<void> _addMentee() async {
    final result = await showDialog<MentorMentee>(
      context: context, builder: (_) => const _MenteeEditor(),
    );
    if (result == null || !mounted) return;
    setState(() {
      mentees.add(result);
      mentees.sort((a, b) => a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase()));
    });
    await _save();
  }

  Future<void> _editMentee(MentorMentee item) async {
    final result = await showDialog<MentorMentee>(
      context: context, builder: (_) => _MenteeEditor(initial: item),
    );
    if (result == null || !mounted) return;
    final index = mentees.indexWhere((value) => value.id == item.id);
    if (index < 0) return;
    setState(() {
      mentees[index] = result;
      mentees.sort((a, b) => a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase()));
    });
    await _save();
  }

  Future<void> _deleteMentee(MentorMentee item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить подопечного?'),
        content: Text('Карточка ${item.fullName}, расписание и ДОПы будут удалены с этого устройства.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => mentees.removeWhere((value) => value.id == item.id));
    await _save();
  }

  Future<void> _editPlan(MentorMentee mentee, {required bool dop, MentorPlanEntry? initial}) async {
    if (mentee.selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала выбери дни недели в данных ученика.')),
      );
      return;
    }
    final result = await showDialog<MentorPlanEntry>(
      context: context,
      builder: (_) => _PlanEditor(days: mentee.selectedDays, dop: dop, initial: initial),
    );
    if (result == null) return;
    final source = List<MentorPlanEntry>.from(dop ? mentee.supplements : mentee.lessons);
    if (initial == null) {
      source.add(result);
    } else {
      final i = source.indexWhere((entry) => entry.id == initial.id);
      if (i >= 0) source[i] = result;
    }
    final updated = dop ? mentee.copyWith(supplements: source) : mentee.copyWith(lessons: source);
    final i = mentees.indexWhere((item) => item.id == mentee.id);
    if (i < 0) return;
    setState(() => mentees[i] = updated);
    await _save();
  }

  Future<void> _deletePlan(MentorMentee mentee, MentorPlanEntry entry, {required bool dop}) async {
    final source = List<MentorPlanEntry>.from(dop ? mentee.supplements : mentee.lessons)
      ..removeWhere((value) => value.id == entry.id);
    final updated = dop ? mentee.copyWith(supplements: source) : mentee.copyWith(lessons: source);
    final i = mentees.indexWhere((item) => item.id == mentee.id);
    if (i < 0) return;
    setState(() => mentees[i] = updated);
    await _save();
  }

  Widget _planSection(MentorMentee mentee, {required bool dop, required ColorScheme scheme}) {
    final allItems = dop ? mentee.supplements : mentee.lessons;
    final items = allItems.where((entry) => mentee.selectedDays.contains(entry.day)).toList();
    final hiddenCount = allItems.length - items.length;
    final sectionTitle = dop ? 'ДОПы' : 'Уроки';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(dop ? Icons.auto_awesome_rounded : Icons.menu_book_rounded, color: scheme.primary, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text('$sectionTitle (${items.length})', style: const TextStyle(fontWeight: FontWeight.w900))),
            IconButton(
              tooltip: dop ? 'Добавить ДОП' : 'Добавить урок',
              onPressed: () => _editPlan(mentee, dop: dop),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Скрыто записей на невыбранных днях: $hiddenCount.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(dop ? 'ДОПы пока не добавлены.' : 'Уроки пока не добавлены.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            ...items.map((entry) => ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 17, child: Text('${entry.day}')),
              title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                _mentorDays[entry.day] ?? 'День не выбран', entry.time,
                if (entry.room.isNotEmpty) 'каб. ${entry.room}',
                if (entry.teacher.isNotEmpty) entry.teacher,
                if (entry.group.isNotEmpty) 'группа ${entry.group}',
                if (entry.notes.isNotEmpty) entry.notes,
              ].join(' • ')),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') _editPlan(mentee, dop: dop, initial: entry);
                  if (action == 'delete') _deletePlan(mentee, entry, dop: dop);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            )),
        ]),
      ),
    );
  }

  /// Расписание класса подопечного из школьных данных приложения: по выбранным
  /// дням, а если дни не выбраны, то на всю неделю.
  Widget _classSchedule(MentorMentee mentee, ColorScheme scheme) {
    final rows = SchoolScheduleCatalog.variants(mentee.className);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'Расписание класса ${mentee.className} не найдено в школьных данных.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final days = mentee.selectedDays.isEmpty
        ? const [1, 2, 3, 4, 5, 6]
        : (mentee.selectedDays.toList()..sort());
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        'Расписание класса ${mentee.className}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      children: [for (final day in days) ..._scheduleDay(rows, day, scheme)],
    );
  }

  List<Widget> _scheduleDay(List<Map<String, dynamic>> rows, int day, ColorScheme scheme) {
    final dayRows = rows
        .where((row) => (int.tryParse('${row['day']}') ?? 0) == day)
        .where((row) => SchoolScheduleCatalog.baseSubject('${row['subject'] ?? ''}').toLowerCase() != 'обед')
        .toList()
      ..sort((a, b) => compareLessonTimes('${a['time'] ?? ''}', '${b['time'] ?? ''}'));
    if (dayRows.isEmpty) return const [];
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(_mentorDays[day] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      for (final row in dayRows)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(SchoolScheduleCatalog.baseSubject('${row['subject'] ?? ''}')),
          subtitle: Text([
            SchoolScheduleCatalog.teacherFromSubject('${row['subject'] ?? ''}'),
            // The group is only worth showing when the same slot has several.
            if (dayRows.where((other) => other['time'] == row['time']).length > 1)
              'группа ${row['group'] ?? ''}',
          ].where((part) => part.trim().isNotEmpty).join(' • ')),
          trailing: Text('${row['time'] ?? ''}', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
    ];
  }

  Widget _menteeCard(MentorMentee item, ColorScheme scheme) {
    final days = item.selectedDays.toList()..sort();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(item.lastName.isEmpty ? '?' : item.lastName.substring(0, 1).toUpperCase()),
        ),
        title: Text(item.fullName, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${item.className}${item.profile.isEmpty ? '' : ' • ${item.profile}'}'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Align(alignment: Alignment.centerLeft, child: Wrap(
            spacing: 6, runSpacing: 4,
            children: days.isEmpty
              ? [const Chip(label: Text('Дни не выбраны'))]
              : days.map((day) => Chip(label: Text(_mentorDays[day] ?? ''))).toList(),
          )),
          if (item.notes.isNotEmpty)
            Align(alignment: Alignment.centerLeft, child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(item.notes, style: TextStyle(color: scheme.onSurfaceVariant)),
            )),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _editMentee(item),
              icon: const Icon(Icons.edit_outlined), label: const Text('Данные'),
            )),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Удалить подопечного', onPressed: () => _deleteMentee(item),
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
            ),
          ]),
          _classSchedule(item, scheme),
          _planSection(item, dop: false, scheme: scheme),
          _planSection(item, dop: true, scheme: scheme),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои подопечные'),
        actions: [IconButton(
          tooltip: 'Обновить доступ и данные',
          onPressed: loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        )],
      ),
      floatingActionButton: allowed ? FloatingActionButton.extended(
        onPressed: _addMentee,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Добавить ученика'),
      ) : null,
      body: loading ? const Center(child: CircularProgressIndicator()) :
        !allowed ? Center(child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 46, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            const Text('Раздел доступен учётным записям наставников.',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Войди через школьную учётную запись с ролью наставника. Список учеников хранится только на этом устройстве.',
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        )) : error.isNotEmpty ? Center(child: Padding(
          padding: const EdgeInsets.all(24), child: Text(error, textAlign: TextAlign.center),
        )) : Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Поиск по ФИО или классу',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(
              'Локальная база • только на этом устройстве • ${mentees.length} учеников',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )),
          ),
          Expanded(child: items.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(mentees.isEmpty
                    ? 'Добавь первого подопечного. Затем выбери дни и внеси его уроки и ДОПы.'
                    : 'По запросу ничего не найдено.',
                  textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: items.length,
                itemBuilder: (_, index) => _menteeCard(items[index], scheme),
              )),
        ]),
    );
  }
}

class _MenteeEditor extends StatefulWidget {
  final MentorMentee? initial;
  const _MenteeEditor({this.initial});
  @override
  State<_MenteeEditor> createState() => _MenteeEditorState();
}

class _MenteeEditorState extends State<_MenteeEditor> {
  late final TextEditingController lastName, firstName, middleName, letter, profile, notes;
  late String grade;
  late Set<int> days;
  String? error;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    lastName = TextEditingController(text: item?.lastName ?? '');
    firstName = TextEditingController(text: item?.firstName ?? '');
    middleName = TextEditingController(text: item?.middleName ?? '');
    letter = TextEditingController(text: item?.letter ?? '');
    profile = TextEditingController(text: item?.profile ?? '');
    notes = TextEditingController(text: item?.notes ?? '');
    grade = item?.grade ?? '8';
    days = {...?item?.selectedDays};
  }

  @override
  void dispose() {
    for (final c in [lastName, firstName, middleName, letter, profile, notes]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'Новый подопечный' : 'Данные ученика'),
    scrollable: true,
    content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: lastName, decoration: const InputDecoration(labelText: 'Фамилия *'), textCapitalization: TextCapitalization.words),
      TextField(controller: firstName, decoration: const InputDecoration(labelText: 'Имя *'), textCapitalization: TextCapitalization.words),
      TextField(controller: middleName, decoration: const InputDecoration(labelText: 'Отчество'), textCapitalization: TextCapitalization.words),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(flex: 2, child: DropdownButtonFormField<String>(
          value: grade, decoration: const InputDecoration(labelText: 'Класс'),
          items: [for (var i = 5; i <= 11; i++) DropdownMenuItem(value: '$i', child: Text('$i класс'))],
          onChanged: (value) => setState(() => grade = value ?? grade),
        )),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: letter, textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Буква', hintText: 'А'))),
      ]),
      if (grade == '10') TextField(controller: profile,
        decoration: const InputDecoration(labelText: 'Направление / профиль')),
      const SizedBox(height: 12),
      const Align(alignment: Alignment.centerLeft, child: Text('Выбери дни недели', style: TextStyle(fontWeight: FontWeight.w800))),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final entry in _mentorDays.entries)
          FilterChip(
            label: Text(entry.value.substring(0, 2)),
            selected: days.contains(entry.key),
            onSelected: (value) => setState(() {
              if (value) { days.add(entry.key); } else { days.remove(entry.key); }
            }),
          ),
      ]),
      TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Заметки наставника')),
      if (error != null) Align(alignment: Alignment.centerLeft,
        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () {
        final surname = lastName.text.trim(), name = firstName.text.trim();
        final groupLetter = letter.text.trim().toUpperCase();
        if (surname.isEmpty || name.isEmpty || groupLetter.isEmpty) {
          setState(() => error = 'Заполни фамилию, имя и букву класса.'); return;
        }
        if (!RegExp(r'^[А-ЯЁA-Z]$').hasMatch(groupLetter)) {
          setState(() => error = 'Буква класса должна быть одним символом.'); return;
        }
        Navigator.pop(context, MentorMentee(
          id: widget.initial?.id ?? 'mentee_${DateTime.now().microsecondsSinceEpoch}',
          lastName: surname, firstName: name, middleName: middleName.text.trim(),
          grade: grade, letter: groupLetter, profile: grade == '10' ? profile.text.trim() : '',
          notes: notes.text.trim(), selectedDays: Set<int>.from(days),
          lessons: widget.initial?.lessons ?? const [],
          supplements: widget.initial?.supplements ?? const [],
        ));
      }, child: const Text('Сохранить')),
    ],
  );
}

class _PlanEditor extends StatefulWidget {
  final Set<int> days;
  final bool dop;
  final MentorPlanEntry? initial;
  const _PlanEditor({required this.days, required this.dop, this.initial});
  @override
  State<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<_PlanEditor> {
  late int day;
  late final TextEditingController title, time, teacher, room, group, notes;
  String? error;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    final orderedDays = widget.days.toList()..sort();
    day = item?.day ?? (orderedDays.isEmpty ? 1 : orderedDays.first);
    title = TextEditingController(text: item?.title ?? '');
    time = TextEditingController(text: item?.time ?? '');
    teacher = TextEditingController(text: item?.teacher ?? '');
    room = TextEditingController(text: item?.room ?? '');
    group = TextEditingController(text: item?.group ?? '');
    notes = TextEditingController(text: item?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [title, time, teacher, room, group, notes]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderedDays = widget.days.toList()..sort();
    return AlertDialog(
      title: Text(widget.dop ? 'ДОП' : 'Урок'),
      scrollable: true,
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(
          value: orderedDays.contains(day) ? day : orderedDays.first,
          decoration: const InputDecoration(labelText: 'День недели'),
          items: [for (final d in orderedDays) DropdownMenuItem(value: d, child: Text(_mentorDays[d] ?? ''))],
          onChanged: (value) => setState(() => day = value ?? day),
        ),
        TextField(controller: title, decoration: InputDecoration(labelText: widget.dop ? 'Название ДОПа *' : 'Предмет *')),
        TextField(controller: time, decoration: const InputDecoration(labelText: 'Время *', hintText: '15:30–16:10')),
        TextField(controller: teacher, decoration: const InputDecoration(labelText: 'Преподаватель')),
        TextField(controller: room, decoration: const InputDecoration(labelText: 'Кабинет')),
        if (widget.dop) TextField(controller: group, decoration: const InputDecoration(labelText: 'Группа')),
        TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Примечание')),
        if (error != null) Align(alignment: Alignment.centerLeft,
          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () {
          final label = title.text.trim(), value = time.text.trim();
          if (label.isEmpty || value.isEmpty) { setState(() => error = 'Укажи название и время.'); return; }
          if (!RegExp(r'^\d{1,2}:\d{2}(?:\s*[-–—]\s*\d{1,2}:\d{2})?$').hasMatch(value)) {
            setState(() => error = 'Время укажи как 15:30 или 15:30–16:10.'); return;
          }
          Navigator.pop(context, MentorPlanEntry(
            id: widget.initial?.id ?? 'plan_${DateTime.now().microsecondsSinceEpoch}',
            day: day, title: label, time: value, teacher: teacher.text.trim(),
            room: room.text.trim(), group: widget.dop ? group.text.trim() : '',
            notes: notes.text.trim(),
          ));
        }, child: const Text('Сохранить')),
      ],
    );
  }
}
