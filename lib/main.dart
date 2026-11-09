import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'local_ai_chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bell_countdown.dart';
import 'notes_page.dart';
import 'admin_panel.dart';
import 'announcements_page.dart';
import 'door_points.dart';
import 'corridor_roads.dart';
import 'local_notification_service.dart';
import 'security_service.dart';
import 'supplements_page.dart';
import 'school_account_service.dart';
import 'dop_parser.dart';
import 'school_portal_page.dart';
import 'online_data_service.dart';
import 'desktop_notification_polling_stub.dart' if (dart.library.io) 'desktop_notification_polling_io.dart' as desktop_polling;

const String _configuredApiBase = String.fromEnvironment('POKOLENIE_API_BASE_URL');

Future<void> _seedOnlineSettings() async {
  final base = _configuredApiBase.trim();
  if (!NavigatorApiConfig(baseUrl: base).enabled) return;
  final prefs = await SharedPreferences.getInstance();
  final savedBase = (prefs.getString('navigator_api_url') ?? '').trim();
  // A build-time URL is a default for new installs. Respect a user's explicit
  // existing configuration (including disabling online mode).
  if (savedBase.isEmpty) {
    await prefs.setString('navigator_api_url', base);
    if (prefs.getBool('navigator_api_enabled') == null) {
      await prefs.setBool('navigator_api_enabled', true);
    }
  }
  final selectedBase = (prefs.getString('navigator_api_url') ?? base).trim();
  if ((prefs.getString('school_api_base_url_v1') ?? '').trim().isEmpty &&
      NavigatorApiConfig(baseUrl: selectedBase).enabled) {
    await prefs.setString('school_api_base_url_v1', selectedBase);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // This is a mobile-only system UI preference; desktop startup must proceed.
    }
  }
  try { await _seedOnlineSettings(); } catch (_) {}
  try { await LocalNotificationService().initialize(); } catch (_) {}
  runApp(const PokolenieApp());
  // Re-register FCM token/listeners in the background after a prior SSO login.
  unawaited(SchoolAccountService().restoreSession());
  unawaited(desktop_polling.startDesktopNotificationPolling());
}

enum AppThemeType { yellow, turquoise, darkBlue, violet, coral, green }

/// Desktop users can scroll with the wheel/trackpad and also drag scrollable
/// lists with the mouse, matching the expected Windows interaction.
class _PokolenieScrollBehavior extends MaterialScrollBehavior {
  const _PokolenieScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}

class AppPalette {
  static const yellow = [Color(0xFFFFC94D), Color(0xFFEADCC7)];
  static const turquoise = [Color(0xFF00BFAE), Color(0xFF79E2A0)];
  static const darkBlue = [Color(0xFF0B1633), Color(0xFF173A78), Color(0xFF3657B8)];
  static const violet = [Color(0xFF6D28D9), Color(0xFF9333EA), Color(0xFFC084FC)];
  static const coral = [Color(0xFFFF5B5B), Color(0xFFFF8A65), Color(0xFFFFC371)];
  static const green = [Color(0xFF087F5B), Color(0xFF12B886), Color(0xFF96F2D7)];

  static List<Color> gradient(AppThemeType type) => switch (type) {
    AppThemeType.yellow => yellow,
    AppThemeType.turquoise => turquoise,
    AppThemeType.darkBlue => darkBlue,
    AppThemeType.violet => violet,
    AppThemeType.coral => coral,
    AppThemeType.green => green,
  };

  static String name(AppThemeType type) => switch (type) {
    AppThemeType.yellow => 'Жёлтая',
    AppThemeType.turquoise => 'Бирюзовая',
    AppThemeType.darkBlue => 'Тёмно-синяя',
    AppThemeType.violet => 'Фиолетовая',
    AppThemeType.coral => 'Коралловая',
    AppThemeType.green => 'Зелёная',
  };
}

class RoomInfo {
  final String id;
  final int floor;
  final String name;
  final Offset point;
  final String corridor;

  const RoomInfo(this.id, this.floor, this.name, this.point, this.corridor);
}



// Специализированные пространства со схем этажей. Номер кабинета не требуется:
// они являются полноценными точками назначения для поиска и маршрутизации.
class SchoolPlaces {
  static const places = <RoomInfo>[
    RoomInfo('place_canteen', 1, 'Столовая', Offset(.245, .565), 'f1_central'),
    RoomInfo('place_food', 1, 'Пищеблок', Offset(.285, .680), 'f1_lower'),
    RoomInfo('place_pool', 1, 'Бассейн', Offset(.395, .700), 'f1_lower'),
    RoomInfo('place_engineering', 1, 'Междисциплинарный инженерный цех', Offset(.515, .590), 'f1_lower'),
    RoomInfo('place_drone', 1, 'Трасса для дрон-рейсинга', Offset(.570, .625), 'f1_lower'),
    RoomInfo('place_gym', 1, 'Тренажёрный зал', Offset(.570, .705), 'f1_lower'),
    RoomInfo('place_choreo', 1, 'Зал хореографии', Offset(.570, .825), 'f1_lower'),
    RoomInfo('place_bio_lab', 1, 'Лаборатория бактериальных экспериментов', Offset(.061, .181), 'f1_left'),
    RoomInfo('place_auditorium', 2, 'Актовый зал', Offset(.285, .600), 'f2_lower'),
    RoomInfo('place_stage', 2, 'Сцена', Offset(.335, .535), 'f2_lower'),
    RoomInfo('place_dressing', 2, 'Гримерная', Offset(.250, .620), 'f2_lower'),
    RoomInfo('place_sport', 2, 'Спортивный зал', Offset(.575, .700), 'f2_lower'),
    RoomInfo('place_library', 3, 'Информационно-библиотечный центр', Offset(.490, .640), 'f3_lower'),
    RoomInfo('place_terrace', 3, 'Терраса', Offset(.420, .735), 'f3_lower'),
  ];
}

class RouteNode {
  final String id;
  final int floor;
  final Offset point;
  final String label;

  const RouteNode(this.id, this.floor, this.point, this.label);
}

class RouteEdge {
  final String a;
  final String b;
  final double cost;
  const RouteEdge(this.a, this.b, this.cost);
}

class RouteResult {
  final List<RouteNode> nodes;
  final RoomInfo destination;
  final double distance;
  final int startFloor;
  final String? startLocationId;

  const RouteResult(this.nodes, this.destination, this.distance, this.startFloor, this.startLocationId);

  bool get changesFloor => nodes.map((n) => n.floor).toSet().length > 1;
}

class RouteStep {
  final int floor;
  final String text;
  final IconData icon;
  const RouteStep(this.floor, this.text, this.icon);
}

class ScheduleEntry {
  final String id;
  final int day;
  final String time;
  final String subject;
  final String room;
  final String teacher;
  final int group;

  const ScheduleEntry({required this.id, required this.day, required this.time, required this.subject, required this.room, this.teacher = '', this.group = 1});
  Map<String, dynamic> toJson() => {'id': id, 'day': day, 'time': time, 'subject': subject, 'room': room, 'teacher': teacher, 'group': group};
  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
    id: '${json['id']}', day: (json['day'] as num?)?.toInt() ?? 1, time: '${json['time'] ?? ''}', subject: '${json['subject'] ?? ''}', room: '${json['room'] ?? ''}',
    teacher: '${json['teacher'] ?? ''}', group: (json['group'] as num?)?.toInt() ?? 1,
  );
}

class SchoolScheduleCatalog {
  static Map<String, dynamic>? _data;
  static Future<void> load() async {
    if (_data != null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('school_schedule_cache_v1');
    if (cached != null) {
      try {
        _data = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        return;
      } catch (_) {}
    }
    final raw = await rootBundle.loadString('assets/data/school_schedule_2026-10-05.json');
    _data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Map<String, dynamic> _normalizedScheduleRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = entry.key.trim().toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9а-я]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      normalized[key] = entry.value;
    }
    return normalized;
  }

  static String _rowText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && value.toString().trim().isNotEmpty) return value.toString().trim();
    }
    return '';
  }

  static int? _rowDay(String raw) {
    final n = int.tryParse(raw.trim());
    if (n != null && n >= 1 && n <= 7) return n;
    const days = <String, int>{
      'пн': 1, 'понедельник': 1, 'mon': 1, 'monday': 1,
      'вт': 2, 'вторник': 2, 'tue': 2, 'tuesday': 2,
      'ср': 3, 'среда': 3, 'wed': 3, 'wednesday': 3,
      'чт': 4, 'четверг': 4, 'thu': 4, 'thursday': 4,
      'пт': 5, 'пятница': 5, 'fri': 5, 'friday': 5,
      'сб': 6, 'суббота': 6, 'sat': 6, 'saturday': 6,
      'вс': 7, 'воскресенье': 7, 'sun': 7, 'sunday': 7,
    };
    return days[raw.trim().toLowerCase()];
  }

  /// Refreshes the existing schedule catalog from the configured source while
  /// retaining the bundled schedule as an offline fallback.
  static Future<int> refreshOnline() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('navigator_api_enabled') ?? false)) return 0;
    final base = (prefs.getString('navigator_api_url') ?? '').trim();
    if (!NavigatorApiConfig(baseUrl: base).enabled) return 0;
    // Use the configured URL rather than a compile-time API address.
    final service = OnlineDataService(NavigatorApiConfig(baseUrl: base));
    final response = await service.get('data/BaseSchedule');
    if (response == null) return 0;
    final rawRows = response['data'];
    if (rawRows is! List) return 0;
    final classNames = <String, String>{};
    try {
      final classPayload = await service.get('data/Classes');
      final classRows = classPayload?['data'];
      if (classRows is List) {
        for (final rawClass in classRows.whereType<Map>()) {
          final item = _normalizedScheduleRow(Map<String, dynamic>.from(rawClass));
          final id = _rowText(item, ['id', 'class_id', 'code']);
          final name = _rowText(item, ['name', 'class_name', 'title', 'класс']);
          if (id.isNotEmpty && name.isNotEmpty) classNames[id] = name;
        }
      }
    } catch (_) {}
    final variantsByClass = <String, List<Map<String, dynamic>>>{};
    for (final raw in rawRows) {
      if (raw is! Map) continue;
      final row = _normalizedScheduleRow(Map<String, dynamic>.from(raw));
      final classRef = _rowText(row, ['class_id', 'class', 'класс_id']);
      final classLabel = _rowText(row, ['class_name', 'class_label', 'class_display_name', 'класс']);
      final className = classLabel.isNotEmpty ? classLabel : (classNames[classRef] ?? classRef);
      final subject = _rowText(row, ['subject', 'subject_name', 'discipline', 'discipline_name', 'lesson', 'предмет', 'дисциплина']);
      final day = _rowDay(_rowText(row, ['day', 'weekday', 'day_of_week', 'день', 'день_недели']));
      final time = _rowText(row, ['time', 'lesson_time', 'time_slot', 'start_time', 'lesson_start', 'время', 'время_урока', 'время_начала', 'время_начала_урока']);
      if (className.isEmpty || subject.isEmpty || day == null || time.isEmpty) continue;
      final group = int.tryParse(_rowText(row, ['group', 'group_number', 'subgroup', 'подгруппа', 'группа'])) ?? 1;
      variantsByClass.putIfAbsent(className, () => <Map<String, dynamic>>[]).add({
        'day': day, 'time': time, 'subject': subject,
        'room': _rowText(row, ['room', 'room_name', 'cabinet', 'room_id', 'кабинет']),
        'teacher': _rowText(row, ['teacher', 'teacher_name', 'педагог', 'учитель']),
        'group': group,
      });
    }
    if (variantsByClass.isEmpty) return 0;
    final baseData = Map<String, dynamic>.from(_data ?? const {});
    final classes = Map<String, dynamic>.from(baseData['classes'] as Map? ?? const {});
    final classOrder = <String, dynamic>{};
    for (final entry in (baseData['class_order'] as Map? ?? const {}).entries) {
      classOrder[entry.key.toString()] = List<String>.from(entry.value as List);
    }
    for (final entry in variantsByClass.entries) {
      classes[entry.key] = {'variants': entry.value};
      final grade = RegExp(r'^\d+').firstMatch(entry.key)?.group(0) ?? 'Другие';
      final list = List<String>.from(classOrder[grade] as List? ?? const <String>[]);
      if (!list.contains(entry.key)) list.add(entry.key);
      list.sort();
      classOrder[grade] = list;
    }
    _data = {...baseData, 'classes': classes, 'class_order': classOrder};
    await prefs.setString('school_schedule_cache_v1', jsonEncode(_data));
    return variantsByClass.values.fold<int>(0, (sum, rows) => sum + rows.length);
  }
  static List<String> grades() => List<String>.from((_data?['class_order'] as Map? ?? {}).keys);
  static List<String> classesForGrade(String grade) => List<String>.from(((_data?['class_order'] as Map?)?[grade] as List?) ?? const []);
  static String _normalizeClassName(String value) {
    const lookalikes = <String, String>{
      'А': 'A', 'В': 'B', 'С': 'C', 'Е': 'E', 'Н': 'H', 'К': 'K',
      'М': 'M', 'О': 'O', 'Р': 'P', 'Т': 'T', 'Х': 'X', 'У': 'Y',
    };
    return value.trim().toUpperCase().replaceAll(' ', '').split('')
        .map((letter) => lookalikes[letter] ?? letter).join();
  }

  static List<Map<String, dynamic>> variants(String className) {
    final classes = _data?['classes'] as Map? ?? const {};
    dynamic classData = classes[className];
    if (classData == null) {
      final wanted = _normalizeClassName(className);
      for (final entry in classes.entries) {
        if (_normalizeClassName(entry.key.toString()) == wanted) {
          classData = entry.value;
          break;
        }
      }
    }
    final raw = (classData as Map?)?['variants'];
    return raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
  }
  static String baseSubject(String value) {
    var subject = value.trim();
    subject = subject.replaceFirst(RegExp(r'\s+[А-ЯЁ][а-яё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.(?:,\s*[А-ЯЁ][а-яё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.)?,?$'), '');
    return subject.trim().replaceFirst(RegExp(r',$'), '').trim();
  }
  static RegExp get _teacherSuffix => RegExp(
        r'\s+([А-ЯЁ][а-яё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.(?:,\s*[А-ЯЁ][а-яё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.)?)\s*$',
      );
  static String teacherFromSubject(String value) =>
      _teacherSuffix.firstMatch(value.trim())?.group(1)?.trim() ?? '';

  /// Возвращает варианты групп только для предметов, у которых в одном
  /// и том же временном слоте реально присутствуют разные группы.
  static Map<String, Set<int>> subjectGroups(String className) {
    final result = <String, Set<int>>{};
    final slots = <String, Map<String, Set<int>>>{};
    for (final e in variants(className)) {
      final subject = baseSubject('${e['subject'] ?? ''}');
      if (subject.isEmpty) continue;
      final slot = '${e['day']}|${e['time']}|$subject';
      (slots[slot] ??= <String, Set<int>>{})
          .putIfAbsent(subject, () => <int>{})
          .add(int.tryParse('${e['group']}') ?? 1);
    }
    for (final slot in slots.values) {
      for (final entry in slot.entries) {
        if (entry.value.length > 1) {
          (result[entry.key] ??= <int>{}).addAll(entry.value);
        }
      }
    }
    return result;
  }

  static Set<String> splitSubjects(String className) =>
      subjectGroups(className).keys.toSet();

  static bool isMathSubject(String subject) {
    final value = subject.toLowerCase();
    return value.contains('математик') || value.contains('алгебр') || value.contains('геометр') || value.contains('вероятност') || value.contains('статистик');
  }

  static int mathLessonCount(String className, int day) {
    final times = variants(className).where((e) => (int.tryParse('${e['day']}') ?? 1) == day && isMathSubject(baseSubject('${e['subject'] ?? ''}'))).map((e) => '${e['time'] ?? ''}'.trim()).where((t) => t.isNotEmpty).toSet();
    return times.length;
  }

  static List<ScheduleEntry> buildPersonal(
    String className,
    Map<String, int> selected, {
    Map<int, List<String>> mathNamesByDay = const {},
  }) {
    final all = variants(className);
    final result = <ScheduleEntry>[];
    final seen = <String>{};
    final mathSlots = <int, List<String>>{};
    for (final e in all) {
      final raw = baseSubject('${e['subject'] ?? ''}');
      if (isMathSubject(raw)) {
        final day = int.tryParse('${e['day']}') ?? 1;
        final time = '${e['time'] ?? ''}';
        final slots = mathSlots.putIfAbsent(day, () => <String>[]);
        if (!slots.contains(time)) slots.add(time);
      }
    }
    for (final slots in mathSlots.values) { slots.sort(); }
    for (final e in all) {
      final rawSubject = '${e['subject'] ?? ''}'.trim();
      final subject = baseSubject(rawSubject);
      if (subject.isEmpty) continue;
      final group = int.tryParse('${e['group']}') ?? 1;
      final wanted = selected[subject] ?? 1;
      final slotGroups = all
          .where((x) =>
              '${x['day']}' == '${e['day']}' &&
              '${x['time']}' == '${e['time']}' &&
              baseSubject('${x['subject'] ?? ''}') == subject)
          .map((x) => int.tryParse('${x['group']}') ?? 1)
          .toSet();
      if (slotGroups.length > 1 && group != wanted) continue;
      final day = int.tryParse('${e['day']}') ?? 1;
      final time = '${e['time'] ?? ''}'.trim();
      var displaySubject = subject;
      if (isMathSubject(subject)) {
        final slots = mathSlots[day] ?? const <String>[];
        final ordinal = slots.indexOf(time);
        final names = mathNamesByDay[day] ?? const <String>[];
        if (ordinal >= 0 && ordinal < names.length && names[ordinal].isNotEmpty) {
          displaySubject = names[ordinal];
        }
      }
      final room = '${e['room'] ?? ''}'.trim();
      final storedTeacher = '${e['teacher'] ?? ''}'.trim();
      final teacher = storedTeacher.isNotEmpty
          ? storedTeacher
          : teacherFromSubject(rawSubject);
      final key = '$day|$time|$displaySubject|$room|$teacher';
      if (!seen.add(key)) continue;
      result.add(ScheduleEntry(
        id: '${className}_${day}_${time}_${displaySubject}_${group}'.replaceAll(
          RegExp(r'[^A-Za-zА-Яа-яЁё0-9_-]'), '_'),
        day: day, time: time, subject: displaySubject, room: room,
        teacher: teacher, group: group,
      ));
    }
    result.sort((a, b) => a.day != b.day
        ? a.day.compareTo(b.day)
        : a.time.compareTo(b.time));
    return result;
  }
}

class _StudentClassDialog extends StatefulWidget {
  final bool requiredChoice;
  const _StudentClassDialog({this.requiredChoice = false});
  @override State<_StudentClassDialog> createState() => _StudentClassDialogState();
}
class _StudentClassDialogState extends State<_StudentClassDialog> {
  String? grade;
  @override Widget build(BuildContext context) {
    final grades = SchoolScheduleCatalog.grades();
    final classes = grade == null ? const <String>[] : SchoolScheduleCatalog.classesForGrade(grade!);
    return AlertDialog(title: const Text('Выбери класс'), content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Расписание встроено в приложение.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: grade, decoration: const InputDecoration(labelText: 'Параллель'), items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(), onChanged: (v) => setState(() => grade = v)),
      if (classes.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: classes.map((c) => ActionChip(label: Text(c), onPressed: () => Navigator.pop(context, c))).toList())],
    ])), actions: widget.requiredChoice ? null : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена'))]);
  }
}
String _studentScopedPreferenceKey(SharedPreferences prefs, String key) {
  var userId = '';
  final raw = prefs.getString('school_user_v1');
  if (raw != null) {
    try {
      final account = jsonDecode(raw);
      if (account is Map && account['id'] != null) {
        userId = account['id'].toString().trim();
      }
    } catch (_) {}
  }
  // Keeps the old keys for offline-only installs, while separating group
  // choices for signed-in students sharing the same device.
  return studentProfilePreferenceKey(key, userId: userId);
}

Future<void> showStudentGroupSelection(BuildContext context, String className) async {
  await SchoolScheduleCatalog.load();
  final subjects = SchoolScheduleCatalog.splitSubjects(className).toList()..sort();
  if (subjects.isEmpty || !context.mounted) return;
  final prefs = await SharedPreferences.getInstance();
  final values = <String, int>{for (final s in subjects) s: prefs.getInt(_studentScopedPreferenceKey(prefs, 'student_group_${className}_$s')) ?? 1};
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _StudentGroupsDialog(className: className, subjects: subjects, values: values));
}
class _StudentGroupsDialog extends StatefulWidget {
  final String className; final List<String> subjects; final Map<String, int> values;
  const _StudentGroupsDialog({required this.className, required this.subjects, required this.values});
  @override State<_StudentGroupsDialog> createState() => _StudentGroupsDialogState();
}
class _StudentGroupsDialogState extends State<_StudentGroupsDialog> {
  late final values = Map<String, int>.of(widget.values);
  late final available = SchoolScheduleCatalog.subjectGroups(widget.className);
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text('Группы • ${widget.className}'),
    content: SizedBox(width: MediaQuery.sizeOf(context).width * .82, child: ListView(shrinkWrap: true, children: widget.subjects.map((s) {
      final groups = (available[s] ?? <int>{1}).toList()..sort();
      String groupLabel(int group) {
        final teacherNames = SchoolScheduleCatalog.variants(widget.className)
            .where((e) => SchoolScheduleCatalog.baseSubject('${e['subject'] ?? ''}') == s && (int.tryParse('${e['group']}') ?? 1) == group)
            .map((e) => SchoolScheduleCatalog.teacherFromSubject('${e['subject'] ?? ''}').split(' ').first)
            .where((name) => name.isNotEmpty).toSet();
        return teacherNames.isEmpty ? 'Группа $group' : teacherNames.join(' / ');
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s, softWrap: true, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Группа / преподаватель',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              initialValue: values[s] ?? groups.first,
              items: groups.map((g) => DropdownMenuItem(
                value: g,
                child: Text(groupLabel(g), maxLines: 1, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) { if (value != null) setState(() => values[s] = value); },
            ),
          ],
        ),
      );
    }).toList())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          for (final entry in values.entries) {
            await prefs.setInt(
              _studentScopedPreferenceKey(
                prefs,
                'student_group_${widget.className}_${entry.key}',
              ),
              entry.value,
            );
          }
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}
class SchoolData {
  static const rooms = <RoomInfo>[
RoomInfo('101', 1, 'Приёмная', Offset(.335, .404), 'f1_central'),
RoomInfo('101.1', 1, 'Кабинет директора', Offset(.360, .404), 'f1_central'),
RoomInfo('102', 1, 'Универсальный учебный кабинет', Offset(.369, .358), 'f1_central'),
RoomInfo('103', 1, 'Универсальный учебный кабинет', Offset(.369, .316), 'f1_central'),
RoomInfo('104', 1, 'Учительская', Offset(.369, .276), 'f1_central'),
RoomInfo('105', 1, 'Универсальный учебный кабинет', Offset(.369, .235), 'f1_central'),
RoomInfo('106', 1, 'Кабинет физики', Offset(.369, .194), 'f1_central'),
RoomInfo('107', 1, 'Универсальный учебный кабинет', Offset(.369, .428), 'f1_central'),
RoomInfo('108', 1, 'Лекторий', Offset(.338, .428), 'f1_central'),
RoomInfo('109', 1, 'Административный кабинет', Offset(.305, .562), 'f1_lower'),
RoomInfo('110', 1, 'Административный кабинет', Offset(.330, .562), 'f1_lower'),
RoomInfo('111', 1, 'Административный кабинет', Offset(.352, .562), 'f1_lower'),
RoomInfo('112', 1, 'Административный кабинет', Offset(.372, .562), 'f1_lower'),
RoomInfo('113', 1, 'Административный кабинет', Offset(.392, .562), 'f1_lower'),
RoomInfo('114', 1, 'Инструментальная мастерская', Offset(.411, .562), 'f1_lower'),
RoomInfo('115', 1, 'Инструментальная мастерская', Offset(.440, .562), 'f1_lower'),
RoomInfo('116', 1, 'Столярная мастерская', Offset(.474, .562), 'f1_lower'),
RoomInfo('117', 1, 'Слесарная мастерская', Offset(.535, .562), 'f1_lower'),
RoomInfo('118', 1, 'Слесарная мастерская', Offset(.562, .562), 'f1_lower'),
RoomInfo('119', 1, 'Медицинский пункт', Offset(.500, .706), 'f1_lower'),
RoomInfo('120', 1, 'Тренерская', Offset(.465, .675), 'f1_lower'),
RoomInfo('121', 1, 'Универсальный учебный кабинет', Offset(.101, .458), 'f1_left'),
RoomInfo('122', 1, 'Кабинет химии', Offset(.080, .458), 'f1_left'),
RoomInfo('123', 1, 'Лаборатория кабинета химии', Offset(.048, .458), 'f1_left'),
RoomInfo('124', 1, 'Универсальный учебный кабинет', Offset(.049, .399), 'f1_left'),
RoomInfo('125', 1, 'Универсальный учебный кабинет', Offset(.049, .352), 'f1_left'),
RoomInfo('126', 1, 'Кабинет иностранного языка', Offset(.049, .303), 'f1_left'),
RoomInfo('127', 1, 'Кабинет химии', Offset(.049, .258), 'f1_left'),
RoomInfo('128', 1, 'Лаборатория кабинета химии', Offset(.049, .219), 'f1_left'),
RoomInfo('129', 1, 'Лаборатория физико-химических испытаний', Offset(.049, .181), 'f1_left'),
RoomInfo('130', 1, 'Кабинет информатики', Offset(.113, .414), 'f1_left'),
RoomInfo('201', 2, 'Универсальный учебный кабинет', Offset(.335, .404), 'f2_central'),
RoomInfo('202', 2, 'Универсальный учебный кабинет', Offset(.365, .404), 'f2_central'),
RoomInfo('203', 2, 'Учительская', Offset(.369, .353), 'f2_central'),
RoomInfo('204', 2, 'Учительская', Offset(.369, .314), 'f2_central'),
RoomInfo('205', 2, 'Административный кабинет', Offset(.369, .275), 'f2_central'),
RoomInfo('206', 2, 'Административный кабинет', Offset(.369, .257), 'f2_central'),
RoomInfo('207', 2, 'Административный кабинет', Offset(.369, .238), 'f2_central'),
RoomInfo('208', 2, 'Кабинет математики', Offset(.369, .207), 'f2_central'),
RoomInfo('209', 2, 'Кабинет физики', Offset(.369, .176), 'f2_central'),
RoomInfo('210', 2, 'Кабинет географии', Offset(.564, .429), 'f2_central'),
RoomInfo('211', 2, 'Кабинет черчения', Offset(.525, .429), 'f2_central'),
RoomInfo('212', 2, 'Комната психологической разгрузки', Offset(.375, .562), 'f2_lower'),
RoomInfo('213', 2, 'Дизайн-мастерская', Offset(.411, .562), 'f2_lower'),
RoomInfo('214', 2, 'Кулинария', Offset(.449, .562), 'f2_lower'),
RoomInfo('215', 2, 'Тренерская', Offset(.494, .756), 'f2_lower'),
RoomInfo('216', 2, 'Административный кабинет', Offset(.499, .659), 'f2_lower'),
RoomInfo('217', 2, 'Центр космических технологий', Offset(.290, .651), 'f2_lower'),
RoomInfo('218', 2, 'Телестудия', Offset(.230, .616), 'f2_lower'),
RoomInfo('219', 2, 'Универсальный учебный кабинет', Offset(.101, .472), 'f2_left'),
RoomInfo('220', 2, 'Кабинет биологии и естествознания', Offset(.080, .472), 'f2_left'),
RoomInfo('221', 2, 'Кабинет русского языка и литературы', Offset(.049, .365), 'f2_left'),
RoomInfo('222', 2, 'Кабинет русского языка и литературы', Offset(.049, .326), 'f2_left'),
RoomInfo('223', 2, 'Кабинет математики', Offset(.049, .286), 'f2_left'),
RoomInfo('224', 2, 'Кабинет биологии', Offset(.049, .245), 'f2_left'),
RoomInfo('225', 2, 'Универсальный учебный кабинет', Offset(.049, .195), 'f2_left'),
RoomInfo('226', 2, 'Кабинет информатики. Лаборатория киберспорта', Offset(.113, .414), 'f2_left'),
RoomInfo('227', 2, 'Кабинет физики', Offset(.183, .444), 'f2_central'),
RoomInfo('228', 2, 'Кабинет физики. Лаборатория', Offset(.231, .444), 'f2_central'),
RoomInfo('301', 3, 'Кабинет основ безопасности и защиты Родины', Offset(.335, .404), 'f3_central'),
RoomInfo('302', 3, 'Лабораторская кабинета основ безопасности и защиты Родины', Offset(.365, .404), 'f3_central'),
RoomInfo('303', 3, 'Кабинет географии', Offset(.369, .354), 'f3_central'),
RoomInfo('304', 3, 'Кабинет русского языка и литературы', Offset(.369, .315), 'f3_central'),
RoomInfo('305', 3, 'Административный кабинет', Offset(.369, .275), 'f3_central'),
RoomInfo('306', 3, 'Административный кабинет', Offset(.369, .257), 'f3_central'),
RoomInfo('307', 3, 'Административный кабинет', Offset(.369, .238), 'f3_central'),
RoomInfo('308', 3, 'Кабинет математики', Offset(.369, .207), 'f3_central'),
RoomInfo('309', 3, 'Кабинет физики', Offset(.369, .176), 'f3_central'),
RoomInfo('310', 3, 'Лаборатория точного земледелия и анализа данных', Offset(.562, .429), 'f3_central'),
RoomInfo('311', 3, 'Центр информационных технологий и искусственного интеллекта', Offset(.525, .429), 'f3_central'),
RoomInfo('312', 3, 'Лаборатория робототехники и беспилотных систем', Offset(.396, .562), 'f3_lower'),
RoomInfo('313', 3, 'Музей науки и технологий Краснодарского края', Offset(.433, .562), 'f3_lower'),
RoomInfo('314', 3, 'Издательский центр', Offset(.475, .575), 'f3_lower'),
RoomInfo('315', 3, 'Учительская', Offset(.346, .604), 'f3_lower'),
RoomInfo('316', 3, 'Кабинет основ безопасности и защиты Родины', Offset(.315, .632), 'f3_lower'),
RoomInfo('317', 3, 'Театральная студия', Offset(.266, .641), 'f3_lower'),
RoomInfo('318', 3, 'Кабинет математики', Offset(.222, .607), 'f3_lower'),
RoomInfo('319', 3, 'Лаборатория медицинской физики', Offset(.103, .472), 'f3_left'),
RoomInfo('320', 3, 'Кабинет медицинской физики', Offset(.080, .472), 'f3_left'),
RoomInfo('321', 3, 'Лаборатория селенции и агротехнологий', Offset(.049, .365), 'f3_left'),
RoomInfo('322', 3, 'Кабинет истории и обществознания', Offset(.049, .326), 'f3_left'),
RoomInfo('323', 3, 'Кабинет иностранного языка', Offset(.049, .286), 'f3_left'),
RoomInfo('324', 3, 'Кабинет биологии', Offset(.049, .245), 'f3_left'),
RoomInfo('325', 3, 'Лаборатория биотехнологий и микробного синтеза', Offset(.049, .195), 'f3_left'),
RoomInfo('326', 3, 'Медицинский класс', Offset(.049, .154), 'f3_left'),
RoomInfo('327', 3, 'Административный кабинет', Offset(.113, .414), 'f3_left'),
RoomInfo('328', 3, 'Центр детских инициатив', Offset(.151, .414), 'f3_left'),
RoomInfo('329', 3, 'Лекторий', Offset(.181, .414), 'f3_central'),
RoomInfo('330', 3, 'Художественная студия', Offset(.216, .444), 'f3_central'),
RoomInfo('331', 3, 'Лаборатория генетики и наук о жизни', Offset(.266, .444), 'f3_central'),
  ];

  static List<RoomInfo> get locations => [...rooms, ...SchoolPlaces.places];
  static RoomInfo room(String id) => locations.firstWhere((r) => r.id == id);
  static RoomInfo? tryRoom(String id) {
    for (final location in locations) {
      if (location.id == id) return location;
    }
    return null;
  }
  static List<RoomInfo> roomsOnFloor(int floor) => rooms.where((r) => r.floor == floor).toList();
  static List<RoomInfo> locationsOnFloor(int floor) => locations.where((r) => r.floor == floor).toList();
  static bool isPlace(RoomInfo r) => r.id.startsWith('place_');
  static String title(RoomInfo r) => isPlace(r) ? r.name : 'Кабинет ${r.id}';
  static String typeLabel(RoomInfo r) => isPlace(r) ? 'Место' : 'Кабинет';
  static Offset point(RoomInfo r) => DoorPoints.of(r.id, r.point);
}

class RouteEngine {
  // Маршрутизация строится по реальным линиям коридоров из corridor_roads.dart.
  // Двери и лестницы подключаются к ближайшему отрезку перпендикулярной связью.
  // Близкие концы отрезков (< 25 px исходной карты) считаются одним узлом.
  static const double _mapW = 7016.0;
  static const double _mapH = 4960.0;
  static const double _snapPx = 32.0;
  // A room/stair anchor must be close to a mapped corridor. Without this limit,
  // an incorrectly placed door can be connected through a wall to a distant wing.
  static const double _maxAnchorConnectorPx = 450.0;
  // A stair transition is intentionally more expensive than any plausible
  // horizontal route across a school floor. This minimizes floor changes first;
  // within the same number of transitions, A* minimizes real map-pixel distance.
  static const double _stairTransitionPenaltyPx = 100000.0;

  // Переводим нормализованные координаты обратно в пиксели исходной карты.
  // Важно учитывать обе оси: карта 7016x4960, поэтому умножать
  // евклидово расстояние только на ширину было неточно по Y.
  static double _pxDistance(Offset a, Offset b) {
    final dx = (a.dx - b.dx) * _mapW;
    final dy = (a.dy - b.dy) * _mapH;
    return math.sqrt(dx * dx + dy * dy);
  }

  static final Map<String, Offset> _anchors = {
    'entry': DoorPoints.all['place_entrance']!,
    ...DoorPoints.all,
  };

  // Эти места нельзя использовать как транзитные узлы: через них не прокладываем
  // маршрут, но ими можно начать или закончить маршрут.
  static const Set<String> _blockedTransit = {
    'place_canteen',
    'place_pool',
    'place_sport',
    'place_auditorium',
  };

  static List<List<String>> _verticalStairs() => const [
    ['stair_green_upper', 'stair_green_2_upper', 'stair_green_3_upper'],
    ['stair_green_121', 'stair_green_2_lower', 'stair_green_3_lower'],
    ['stair_blue_center', 'stair_blue_2_center', 'stair_blue_3_center'],
    ['stair_purple_108', 'stair_purple_2_lower', 'stair_purple_3_lower'],
    ['stair_purple_upper', 'stair_purple_2_upper', 'stair_purple_3_upper'],
    ['stair_turquoise_lower', 'stair_turquoise_2', 'stair_turquoise_3'],
    // The bottom turquoise stair connects floors 1↔2, but not floor 3.
    ['stair_turquoise_bottom', 'stair_turquoise_2_closed'],
  ];

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  static Offset _project(Offset p, Offset a, Offset b) {
    // Projection must be perpendicular in source-map pixels. The map is 7016×4960,
    // so projecting directly in normalized 0..1 coordinates distorts the angle.
    final pp = Offset(p.dx * _mapW, p.dy * _mapH);
    final aa = Offset(a.dx * _mapW, a.dy * _mapH);
    final bb = Offset(b.dx * _mapW, b.dy * _mapH);
    final v = bb - aa;
    final len2 = v.dx * v.dx + v.dy * v.dy;
    if (len2 <= 1e-12) return a;
    final t = (((pp.dx - aa.dx) * v.dx) + ((pp.dy - aa.dy) * v.dy)) / len2;
    final clamped = t.clamp(0.0, 1.0);
    final projected = Offset(aa.dx + v.dx * clamped, aa.dy + v.dy * clamped);
    return Offset(projected.dx / _mapW, projected.dy / _mapH);
  }

  static Offset? _intersection(Offset a, Offset b, Offset c, Offset d) {
    final r = b - a;
    final s = d - c;
    final den = _cross(r, s);
    if (den.abs() < 1e-10) return null;
    final qmp = c - a;
    final t = _cross(qmp, s) / den;
    final u = _cross(qmp, r) / den;
    if (t < -1e-8 || t > 1.00000001 || u < -1e-8 || u > 1.00000001) return null;
    return Offset(a.dx + r.dx * t, a.dy + r.dy * t);
  }

  static Offset _nearestPointOnSegment(Offset p, CorridorSegment s) => _project(p, s.a, s.b);

  static RouteResult? build(String destinationId, {int startFloor = 1, String? startLocationId}) {
    // startFloor is kept for callers that also select which floor to browse;
    // the real origin is the main entrance unless an explicit location is saved.
    assert(startFloor >= 1 && startFloor <= 3);
    final destination = SchoolData.tryRoom(destinationId);
    if (destination == null) return null;
    final startRoom = startLocationId == null ? null : SchoolData.tryRoom(startLocationId);
    if (startLocationId != null && startRoom == null) return null;
    final effectiveStartFloor = startRoom?.floor ?? 1;

    // A same-location request must succeed even when that point has no corridor
    // connector, and should not build the full graph or show walking directions.
    if (startRoom != null && startRoom.id == destination.id) {
      final point = DoorPoints.of(destination.id, destination.point);
      return RouteResult(
        [RouteNode('same_start', destination.floor, point, 'Точка назначения')],
        destination, 0, destination.floor, startLocationId,
      );
    }

    final segments = CorridorRoads.all;
    final nodes = <String, RouteNode>{};
    final segmentNodeIds = <int, List<String>>{};
    var serial = 0;

    String addNode(int floor, Offset point, String label, {String? preferredId}) {
      final id = preferredId ?? 'road_${serial++}';
      // Snap nearby graph points so tiny coordinate errors do not create holes.
      for (final existing in nodes.values) {
        if (existing.floor == floor && _pxDistance(existing.point, point) <= _snapPx) {
          return existing.id;
        }
      }
      nodes[id] = RouteNode(id, floor, point, label);
      return id;
    }

    String addPointToSegment(int floor, Offset point, String label, int segIndex, {String? preferredId}) {
      final id = addNode(floor, point, label, preferredId: preferredId);
      segmentNodeIds.putIfAbsent(segIndex, () => <String>[]).add(id);
      return id;
    }

    // Every road endpoint is a graph node.
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      addPointToSegment(s.floor, s.a, s.label, i);
      addPointToSegment(s.floor, s.b, s.label, i);
    }

    // Split roads at every true intersection.
    for (var i = 0; i < segments.length; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        final a = segments[i];
        final b = segments[j];
        if (a.floor != b.floor) continue;
        final p = _intersection(a.a, a.b, b.a, b.b);
        if (p == null) continue;
        final id = addNode(a.floor, p, 'Перекрёсток');
        segmentNodeIds.putIfAbsent(i, () => <String>[]).add(id);
        segmentNodeIds.putIfAbsent(j, () => <String>[]).add(id);
      }
    }

    // Add perpendicular connectors from doors/places/stairs to roads.
    // Transit-restricted spaces stay disconnected unless they are the explicit
    // start or destination of this route.
    final anchorNode = <String, String>{};
    final anchorRoadNode = <String, String>{};
    final requestedAnchors = <String>{destination.id};
    if (startLocationId != null) requestedAnchors.add(startLocationId);
    // Keep the hand-mapped door points, but do not make routing depend on every
    // room already having an explicit DoorPoints entry: use its catalog point
    // as a safe, bounded fallback for the requested origin/destination.
    final routeAnchors = <String, Offset>{..._anchors};
    routeAnchors.putIfAbsent(destination.id, () => DoorPoints.of(destination.id, destination.point));
    if (startRoom != null) {
      routeAnchors.putIfAbsent(startRoom.id, () => DoorPoints.of(startRoom.id, startRoom.point));
    }
    for (final entry in routeAnchors.entries) {
      final id = entry.key;
      if (_blockedTransit.contains(id) && !requestedAnchors.contains(id)) continue;
      final p = entry.value;
      final floor = _anchorFloor(id);
      if (floor == null) continue;
      var bestDistance = double.infinity;
      var bestSegment = -1;
      var bestPoint = p;
      for (var i = 0; i < segments.length; i++) {
        final s = segments[i];
        if (s.floor != floor) continue;
        final q = _nearestPointOnSegment(p, s);
        final d = _pxDistance(p, q);
        if (d < bestDistance) {
          bestDistance = d;
          bestSegment = i;
          bestPoint = q;
        }
      }
      // Do not invent a corridor connection when the nearest mapped corridor is
      // too far away: that usually means the door anchor or corridor graph is wrong.
      if (bestSegment < 0 || bestDistance > _maxAnchorConnectorPx) continue;
      final roadId = addPointToSegment(floor, bestPoint, 'Подключение: $id', bestSegment);
      final aId = addNode(floor, p, 'Точка: $id', preferredId: 'anchor_$id');
      anchorNode[id] = aId;
      anchorRoadNode[id] = roadId;
    }

    // Build bidirectional graph from each ordered set of points on a segment.
    final graph = <String, List<RouteEdge>>{};
    void connect(String a, String b, double cost) {
      if (a == b) return;
      graph.putIfAbsent(a, () => []).add(RouteEdge(a, b, cost));
      graph.putIfAbsent(b, () => []).add(RouteEdge(b, a, cost));
    }

    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final ids = <String>{...(segmentNodeIds[i] ?? const <String>[])}.toList();
      ids.sort((a, b) {
        final pa = nodes[a]!.point;
        final pb = nodes[b]!.point;
        final v = s.b - s.a;
        final ta = ((pa.dx - s.a.dx) * v.dx + (pa.dy - s.a.dy) * v.dy);
        final tb = ((pb.dx - s.a.dx) * v.dx + (pb.dy - s.a.dy) * v.dy);
        return ta.compareTo(tb);
      });
      for (var k = 1; k < ids.length; k++) {
        final a = nodes[ids[k - 1]]!;
        final b = nodes[ids[k]]!;
        connect(a.id, b.id, _pxDistance(a.point, b.point));
      }
    }

    // Connect every anchor to its own perpendicular projection on the road.
    for (final entry in anchorNode.entries) {
      final anchorId = entry.value;
      final roadId = anchorRoadNode[entry.key];
      if (roadId == null || anchorId == roadId) continue;
      final anchorPoint = nodes[anchorId]!.point;
      final roadPoint = nodes[roadId]!.point;
      connect(anchorId, roadId, _pxDistance(anchorPoint, roadPoint));
    }

    // Vertical stair links. The closed turquoise stair is deliberately omitted from 2↔3.
    for (final chain in _verticalStairs()) {
      for (var i = 0; i + 1 < chain.length; i++) {
        final aId = anchorNode[chain[i]];
        final bId = anchorNode[chain[i + 1]];
        if (aId == null || bId == null) continue;
        final a = nodes[aId]!;
        final b = nodes[bId]!;
        // Смена этажа должна стоить заметно дороже обычного участка коридора,
      // иначе алгоритм выбирает лестницу даже для маршрута на том же этаже.
      connect(a.id, b.id, _stairTransitionPenaltyPx + _pxDistance(a.point, b.point));
      }
    }

    // Main entrance is always on floor 1. A browsing-floor selection must not
    // fabricate an origin point on the second or third floor.
    final sourceAnchor = startRoom == null ? 'entry' : startRoom.id;
    final source = anchorNode[sourceAnchor];
    final target = anchorNode[destination.id];
    if (source == null || target == null) return null;

    // Prefer a fully same-floor path whenever one exists. A large stair penalty
    // alone is not a guarantee: bad/overlapping map geometry can make a valid
    // same-floor path appear more expensive than a stair shortcut.
    (Map<String, double>, Map<String, String?>) search({required bool sameFloorOnly}) {
      final distance = <String, double>{source: 0};
      final previous = <String, String?>{source: null};
      final open = <_QueueItem>[_QueueItem(source, 0, 0)];

      double heuristic(String id) {
        final a = nodes[id];
        final b = nodes[target];
        if (a == null || b == null) return 0;
        return _pxDistance(a.point, b.point) +
            (sameFloorOnly ? 0 : (a.floor - b.floor).abs() * _stairTransitionPenaltyPx);
      }

      while (open.isNotEmpty) {
        open.sort((a, b) => a.priority.compareTo(b.priority));
        final current = open.removeAt(0);
        final best = distance[current.id];
        if (best == null || current.g > best + 1e-9) continue;
        if (current.id == target) break;
        for (final edge in graph[current.id] ?? const <RouteEdge>[]) {
          if (sameFloorOnly && nodes[edge.a]!.floor != nodes[edge.b]!.floor) continue;
          final nextG = best + edge.cost;
          if (nextG < (distance[edge.b] ?? double.infinity)) {
            distance[edge.b] = nextG;
            previous[edge.b] = current.id;
            open.add(_QueueItem(edge.b, nextG, nextG + heuristic(edge.b)));
          }
        }
      }
      return (distance, previous);
    }

    final preferSameFloor = effectiveStartFloor == destination.floor;
    final firstSearch = search(sameFloorOnly: preferSameFloor);
    final selectedSearch = firstSearch.$1.containsKey(target)
        ? firstSearch
        : search(sameFloorOnly: false);
    final distance = selectedSearch.$1;
    final previous = selectedSearch.$2;
    if (!distance.containsKey(target)) return null;

    final ids = <String>[];
    String? cursor = target;
    while (cursor != null) {
      ids.add(cursor);
      cursor = previous[cursor];
    }
    final path = ids.reversed.map((id) => nodes[id]!).toList();

    // Graph anchor nodes exactly represent the same doorway points added below
    // for display. Drop those duplicates so the route has one clean start and end.
    if (path.isNotEmpty && path.first.id == source) path.removeAt(0);
    if (path.isNotEmpty && path.last.id == target) path.removeLast();

    // Replace technical anchor nodes with readable door/start labels.
    if (startRoom != null) {
      path.insert(0, RouteNode('start_room_${startRoom.id}', startRoom.floor, DoorPoints.of(startRoom.id, startRoom.point), SchoolData.title(startRoom)));
    }
    if (startRoom == null) {
      path.insert(0, RouteNode('start_entry', effectiveStartFloor, DoorPoints.all['place_entrance']!, 'Главный вход'));
    }
    path.add(RouteNode('destination_door_${destination.id}', destination.floor, DoorPoints.of(destination.id, destination.point), SchoolData.title(destination)));

    final displayPath = _simplifyPath(path);
    return RouteResult(displayPath, destination, distance[target]!, effectiveStartFloor, startLocationId);
  }

  static List<RouteNode> _simplifyPath(List<RouteNode> input) {
    if (input.length < 3) return List<RouteNode>.unmodifiable(input);
    final points = List<RouteNode>.from(input);
    var changed = true;
    // Remove only geometry nodes that sit on a straight continuation. Semantic
    // endpoints and stair anchors are retained; topology itself is never edited.
    while (changed) {
      changed = false;
      for (var i = 1; i < points.length - 1; i++) {
        final prev = points[i - 1];
        final current = points[i];
        final next = points[i + 1];
        if (prev.floor != current.floor || current.floor != next.floor) continue;
        if (!current.id.startsWith('road_')) continue;
        final v1 = Offset(
          (current.point.dx - prev.point.dx) * _mapW,
          (current.point.dy - prev.point.dy) * _mapH,
        );
        final v2 = Offset(
          (next.point.dx - current.point.dx) * _mapW,
          (next.point.dy - current.point.dy) * _mapH,
        );
        final len1 = v1.distance;
        final len2 = v2.distance;
        if (len1 < 2 || len2 < 2) continue;
        final cross = _cross(v1, v2).abs();
        final dot = v1.dx * v2.dx + v1.dy * v2.dy;
        // Only collapse forward collinear points, not U-turns or tight corners.
        if (dot <= 0 || cross / (len1 * len2) > 0.035) continue;
        // Compute the projection in original map pixels. Projecting in normalized
        // 0..1 coordinates would distort the result because the source map is not square.
        final prevPx = Offset(prev.point.dx * _mapW, prev.point.dy * _mapH);
        final currentPx = Offset(current.point.dx * _mapW, current.point.dy * _mapH);
        final nextPx = Offset(next.point.dx * _mapW, next.point.dy * _mapH);
        final chord = nextPx - prevPx;
        final chordLength2 = chord.dx * chord.dx + chord.dy * chord.dy;
        if (chordLength2 <= 1e-12) continue;
        final t = (((currentPx.dx - prevPx.dx) * chord.dx) +
                ((currentPx.dy - prevPx.dy) * chord.dy)) /
            chordLength2;
        final projectedPx = Offset(
          prevPx.dx + chord.dx * t,
          prevPx.dy + chord.dy * t,
        );
        final projected = Offset(projectedPx.dx / _mapW, projectedPx.dy / _mapH);
        if (_pxDistance(current.point, projected) > 10) continue;
        points.removeAt(i);
        changed = true;
        break;
      }
    }
    return List<RouteNode>.unmodifiable(points);
  }

  static int? _anchorFloor(String id) {
    if (id == 'entry') return 1;
    final r = SchoolData.tryRoom(id);
    if (r != null) return r.floor;
    if (id.contains('_2_') || id.endsWith('_2')) return 2;
    if (id.contains('_3_') || id.endsWith('_3')) return 3;
    if (id == 'stair_green_upper' || id == 'stair_green_121' || id == 'stair_blue_center' || id == 'stair_purple_108' || id == 'stair_purple_upper' || id == 'stair_turquoise_lower' || id == 'stair_turquoise_bottom') return 1;
    return null;
  }

  static List<RouteStep> instructions(RouteResult result) {
    final path = _simplifyPath(result.nodes);
    if (path.isEmpty) return const [];
    if (path.any((node) => node.id == 'same_start')) {
      return [RouteStep(
        result.destination.floor,
        'Вы уже находитесь у места «${SchoolData.title(result.destination)}».',
        Icons.check_circle_outline_rounded,
      )];
    }
    final steps = <RouteStep>[];
    if (result.startLocationId == null) {
      steps.add(RouteStep(1, 'Начните от главного входа на 1-м этаже.', Icons.directions_walk_rounded));
    } else {
      final start = SchoolData.tryRoom(result.startLocationId!);
      if (start == null) return const [];
      steps.add(RouteStep(start.floor, 'Выйдите из ${SchoolData.title(start)} через дверь в коридор.', Icons.exit_to_app_rounded));
    }
    for (var i = 1; i < path.length; i++) {
      final prev = path[i - 1];
      final cur = path[i];
      if (cur.floor != prev.floor) {
        steps.add(RouteStep(cur.floor, cur.floor > prev.floor
            ? 'Поднимитесь по лестнице на ${cur.floor}-й этаж.'
            : 'Спуститесь по лестнице на ${cur.floor}-й этаж.', Icons.stairs_rounded));
        continue;
      }
      if (cur.id.startsWith('destination_door_')) {
        steps.add(RouteStep(cur.floor, 'Вы прибыли: ${SchoolData.title(result.destination)}.', Icons.flag_rounded));
        continue;
      }
      if (i + 1 < path.length) {
        final next = path[i + 1];
        final v1 = Offset(
          (cur.point.dx - prev.point.dx) * _mapW,
          (cur.point.dy - prev.point.dy) * _mapH,
        );
        final v2 = Offset(
          (next.point.dx - cur.point.dx) * _mapW,
          (next.point.dy - cur.point.dy) * _mapH,
        );
        if (v1.distance < 2 || v2.distance < 2) continue;
        final cross = _cross(v1, v2);
        final dot = v1.dx * v2.dx + v1.dy * v2.dy;
        final angle = math.atan2(cross, dot) * 180 / math.pi;
        if (angle.abs() < 28) continue;
        if (angle.abs() >= 150) {
          steps.add(RouteStep(cur.floor, 'Развернитесь и двигайтесь в обратном направлении.', Icons.turn_left_rounded));
        } else {
          final right = angle > 0;
          steps.add(RouteStep(
            cur.floor,
            '${right ? 'Поверните направо' : 'Поверните налево'} и продолжайте по коридору.',
            right ? Icons.turn_right_rounded : Icons.turn_left_rounded,
          ));
        }
      }
    }
    return _dedupe(steps);
  }

  static List<RouteStep> _dedupe(List<RouteStep> source) {
    final out = <RouteStep>[];
    for (final step in source) {
      if (out.isNotEmpty && out.last.floor == step.floor && out.last.text == step.text) continue;
      out.add(step);
    }
    return out;
  }
}

class _QueueItem {
  final String id;
  final double g;
  final double priority;
  const _QueueItem(this.id, this.g, this.priority);
}

class PokolenieApp extends StatefulWidget {
  const PokolenieApp({super.key});
  @override State<PokolenieApp> createState()=>_PokolenieAppState();
}
class _PokolenieAppState extends State<PokolenieApp>{
  AppThemeType theme=AppThemeType.turquoise; String userName=''; bool ready=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{final p=await SharedPreferences.getInstance();await SchoolScheduleCatalog.load();userName=p.getString('user_name')??'';final t=p.getString('theme');theme=AppThemeType.values.firstWhere((x)=>x.name==t,orElse:()=>AppThemeType.turquoise);if(mounted)setState(()=>ready=true);}
  Future<void> setName(String v)async{v=v.trim();if(v.isEmpty)return;final p=await SharedPreferences.getInstance();await p.setString('user_name',v);if(mounted)setState(()=>userName=v);}
  Future<void> setTheme(AppThemeType v)async{final p=await SharedPreferences.getInstance();await p.setString('theme',v.name);if(mounted)setState(()=>theme=v);}
  @override Widget build(BuildContext context){if(!ready)return MaterialApp(debugShowCheckedModeBanner:false,scrollBehavior:const _PokolenieScrollBehavior(),home:Scaffold(body:Center(child:CircularProgressIndicator(color:AppPalette.gradient(theme).first))));return MaterialApp(debugShowCheckedModeBanner:false,title:'Поколение',scrollBehavior:const _PokolenieScrollBehavior(),theme:_theme(theme),home:AppShell(userName:userName,theme:theme,onThemeChanged:setTheme,onNameChanged:setName));}
  ThemeData _theme(AppThemeType type) {
    final dark = type == AppThemeType.darkBlue;
    final seed = AppPalette.gradient(type).first;
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: dark ? const Color(0xFF8CA7FF) : seed,
      secondary: dark ? const Color(0xFFB0C0FF) : AppPalette.gradient(type).last,
      surface: dark ? const Color(0xFF0B1220) : const Color(0xFFF6F8FC),
      surfaceContainer: dark ? const Color(0xFF111D30) : Colors.white,
      surfaceContainerHigh: dark ? const Color(0xFF17253B) : const Color(0xFFEEF2F8),
      surfaceContainerHighest: dark ? const Color(0xFF1D2E48) : const Color(0xFFE8EDF5),
      onSurface: dark ? const Color(0xFFF2F5FC) : const Color(0xFF172033),
      onSurfaceVariant: dark ? const Color(0xFFB5C2D8) : const Color(0xFF647087),
      outlineVariant: dark ? const Color(0xFF2A3A53) : const Color(0xFFDDE4EE),
    );
    final border = BorderSide(color: colors.outlineVariant.withValues(alpha: .8));
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      dividerColor: colors.outlineVariant,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(color: colors.onSurface, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.35),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: border),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide(color: colors.primary, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(46, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), side: border),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.primary.withValues(alpha: dark ? .24 : .13),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500)),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }
}
class AppShell extends StatefulWidget{
  final String userName;final AppThemeType theme;final ValueChanged<AppThemeType> onThemeChanged;final ValueChanged<String> onNameChanged;
  const AppShell({super.key,required this.userName,required this.theme,required this.onThemeChanged,required this.onNameChanged});
  @override State<AppShell> createState()=>_AppShellState();
}
class _AppShellState extends State<AppShell>{
  int index=0;String? selectedRoom;final key=GlobalKey<ScaffoldState>();
  void go(int i){setState(()=>index=i);key.currentState?.closeDrawer();}
  Future<void> _openAnnouncements() async {
    key.currentState?.closeDrawer();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
  }
  Future<void> _openNotes() async {
    key.currentState?.closeDrawer();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PersonalNotesPage()));
  }
  Future<String> _loadLocalAiSchoolContext(String question) async {
    final prefs = await SharedPreferences.getInstance();
    await SchoolScheduleCatalog.load();

    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final tomorrow = now.add(const Duration(days: 1));
    const dayNames = [
      '',
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
    ];
    String dayName(int weekday) =>
        weekday == DateTime.sunday ? 'Воскресенье' : dayNames[weekday];
    String dateLabel(DateTime date) =>
        '${dayName(date.weekday)} ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
    final timeLabel = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final query = question.toLowerCase();
    final selectedDates = <DateTime>{};

    if (query.contains('сегодня')) {
      selectedDates.add(DateTime(now.year, now.month, now.day));
    }
    if (query.contains('послезавтра')) {
      selectedDates.add(DateTime(
        now.year,
        now.month,
        now.day + 2,
      ));
    } else if (query.contains('завтра')) {
      selectedDates.add(DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
      ));
    }

    const weekdayKeywords = <String, int>{
      'понедельник': 1,
      'вторник': 2,
      'сред': 3,
      'четверг': 4,
      'пятниц': 5,
      'суббот': 6,
      'воскрес': 7,
    };
    for (final entry in weekdayKeywords.entries) {
      if (!query.contains(entry.key)) continue;
      var daysAhead = (entry.value - now.weekday) % 7;
      if (daysAhead < 0) daysAhead += 7;
      if (query.contains('следующ') && daysAhead == 0) daysAhead = 7;
      selectedDates.add(DateTime(
        now.year,
        now.month,
        now.day + daysAhead,
      ));
    }

    final wantsWeek = query.contains('недел') ||
        query.contains('все уроки') ||
        query.contains('всё расписание');
    if (selectedDates.isEmpty || wantsWeek) {
      final firstDayOffset = wantsWeek && query.contains('следующ') ? 7 : 0;
      for (var offset = firstDayOffset; offset < firstDayOffset + 7; offset++) {
        final date = DateTime(now.year, now.month, now.day + offset);
        if (date.weekday >= 1 && date.weekday <= 6) {
          selectedDates.add(date);
        }
      }
    }
    final orderedDates = selectedDates.toList()
      ..sort((a, b) => a.compareTo(b));
    final selectedWeekdays = orderedDates.map((date) => date.weekday).toSet();

    final className =
        (prefs.getString(_studentScopedPreferenceKey(
                  prefs,
                  'student_class_name',
                )) ??
                prefs.getString('student_class_name') ??
                '')
            .trim();
    final contextLines = <String>[
      'Текущее время по Москве: $timeLabel.',
      'Сегодня: ${dateLabel(now)}',
      'Завтра: ${dateLabel(tomorrow)}',
      'Запрошенные даты: ${orderedDates.map(dateLabel).join(', ')}.',
    ];

    if (className.isNotEmpty) {
      contextLines.add('Выбранный класс ученика: $className.');

      final groups = <String, int>{
        for (final subject in SchoolScheduleCatalog.splitSubjects(className))
          subject: prefs.getInt(
                _studentScopedPreferenceKey(
                  prefs,
                  'student_group_${className}_$subject',
                ),
              ) ??
              1,
      };
      final mathNamesByDay = <int, List<String>>{
        for (var day = 1; day <= 6; day++)
          day: [
            for (var slot = 0; slot < 6; slot++)
              prefs.getString(
                    _studentScopedPreferenceKey(
                      prefs,
                      'math_subject_${className}_${day}_$slot',
                    ),
                  ) ??
                  '',
          ],
      };
      final lessons = SchoolScheduleCatalog.buildPersonal(
        className,
        groups,
        mathNamesByDay: mathNamesByDay,
      ).where((lesson) => selectedWeekdays.contains(lesson.day)).toList()
        ..sort((a, b) {
          final dayOrder = a.day.compareTo(b.day);
          return dayOrder != 0 ? dayOrder : a.time.compareTo(b.time);
        });

      contextLines.add('Локальное расписание на запрошенные даты:');
      for (final date in orderedDates) {
        final dayLessons = lessons.where((lesson) =>
            lesson.day == date.weekday);
        contextLines.add('${dateLabel(date)}:');
        for (final lesson in dayLessons) {
          final details = <String>[
            lesson.time,
            lesson.subject,
            'группа ${lesson.group}',
            if (lesson.room.isNotEmpty) 'кабинет ${lesson.room}',
            if (lesson.teacher.isNotEmpty) 'педагог ${lesson.teacher}',
          ];
          contextLines.add('- ${details.join(' • ')}');
        }
      }
      if (lessons.isEmpty) {
        contextLines.add('Для выбранного периода занятий по этому классу не найдено.');
      }
    } else {
      contextLines.add('Класс ученика ещё не выбран; не придумывай его расписание.');
    }

    final rawSchoolUser = prefs.getString('school_user_v1');
    var schoolUserId = '';
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        if (account is Map) {
          schoolUserId = (account['id'] ?? '').toString().trim();
        }
      } catch (_) {}
    }

    final rawSupplements = prefs.getString(
      studentProfilePreferenceKey('supplements_local', userId: schoolUserId),
    );
    if (rawSupplements != null) {
      try {
        final rows = jsonDecode(rawSupplements);
        if (rows is List) {
          final lines = <String>[];
          for (final raw in rows.whereType<Map>()) {
            final item = Map<String, dynamic>.from(raw);
            final title = (item['title'] ?? '').toString().trim();
            if (title.isEmpty) continue;
            final weekday = (item['weekday'] as num?)?.toInt() ?? 0;
            if (!selectedWeekdays.contains(weekday)) continue;
            final time = [
              (item['start'] ?? '').toString().trim(),
              (item['end'] ?? '').toString().trim(),
            ].where((value) => value.isNotEmpty).join('–');
            final details = <String>[
              if (weekday >= 1 && weekday <= 6) dayNames[weekday],
              time,
              title,
              if ((item['room'] ?? '').toString().trim().isNotEmpty)
                'кабинет ${item['room']}',
              if ((item['teacher'] ?? '').toString().trim().isNotEmpty)
                'педагог ${item['teacher']}',
            ].where((value) => value.isNotEmpty);
            lines.add('- ${details.join(' • ')}');
          }
          if (lines.isNotEmpty) {
            contextLines
              ..add('Сохранённые дополнительные занятия (ДОПы) на выбранные даты:')
              ..addAll(lines);
          }
        }
      } catch (_) {
        contextLines.add('Локальные данные ДОПов не удалось прочитать.');
      }
    }

    return contextLines.join('\n');
  }

  void _selectLocationFromAi(String locationId) {
    final room = SchoolData.tryRoom(locationId);
    if (room == null) return;
    setState(() {
      selectedRoom = room.id;
      index = 1;
    });
    key.currentState?.closeDrawer();
  }

  Future<void> _openAiSchoolRoute(String destinationId) async {
    final destination = SchoolData.tryRoom(destinationId);
    if (destination == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final startFloor = (prefs.getInt('map_start_floor') ?? 1).clamp(1, 3);
    final startLocationId = prefs.getString('map_start_location');
    final route = RouteEngine.build(
      destination.id,
      startFloor: startFloor,
      startLocationId: startLocationId,
    );
    if (!mounted) return;

    // The AI page is on this Navigator. Pop it first, then show the real
    // route page using the Shell's still-mounted context.
    Navigator.of(context).pop();
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось построить маршрут по текущей схеме коридоров.'),
        ),
      );
      return;
    }
    setState(() {
      selectedRoom = destination.id;
      index = 1;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutePage(room: destination, route: route),
      ),
    );
  }

  Future<void> _openAiChat() async {
    key.currentState?.closeDrawer();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalAiChatPage(
          schoolContextLoader: _loadLocalAiSchoolContext,
          actionHandler: _handleLocalAiAction,
          onOpenMapLocation: _selectLocationFromAi,
          onOpenSchoolRoute: _openAiSchoolRoute,
        ),
      ),
    );
  }

  int? _dayNumber(Object? raw) {
    if (raw is num) {
      final value = raw.toInt();
      return value >= 1 && value <= 6 ? value : null;
    }
    final value = (raw ?? '').toString().trim().toLowerCase();
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric >= 1 && numeric <= 6 ? numeric : null;
    const aliases = <String, int>{
      'пн': 1, 'понедельник': 1,
      'вт': 2, 'вторник': 2,
      'ср': 3, 'среда': 3,
      'чт': 4, 'четверг': 4,
      'пт': 5, 'пятница': 5,
      'сб': 6, 'суббота': 6,
    };
    for (final entry in aliases.entries) {
      if (value == entry.key || value.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  String _currentSchoolUserId(SharedPreferences prefs) {
    final raw = prefs.getString('school_user_v1');
    if (raw == null) return '';
    try {
      final account = jsonDecode(raw);
      if (account is Map) return (account['id'] ?? '').toString().trim();
    } catch (_) {}
    return '';
  }

  Future<String> _handleLocalAiAction(
    String action,
    Map<String, dynamic> args,
  ) async {
    String arg(String key) => (args[key] ?? '').toString().trim();
    int? integer(String key) {
      final value = args[key];
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString());
    }

    switch (action) {
      case 'get_school_context':
        final question = arg('question');
        return _loadLocalAiSchoolContext(question.isEmpty ? 'неделя' : question);

      case 'search_school_map':
        final query = arg('query').toLowerCase();
        if (query.isEmpty) return 'Укажи номер кабинета или название места.';
        final matches = SchoolData.locations.where((room) =>
            room.id.toLowerCase().contains(query) ||
            SchoolData.title(room).toLowerCase().contains(query)).take(10).toList();
        if (matches.isEmpty) {
          return 'На встроенной карте не найдено место по запросу «$query».';
        }
        return matches.map((room) =>
            'ID: ${room.id}; ${SchoolData.title(room)}; этаж ${room.floor}.').join('\n');

      case 'plan_school_route':
        await SchoolScheduleCatalog.load();
        final destinationQuery = arg('destination').toLowerCase();
        if (destinationQuery.isEmpty) {
          return 'Укажи номер кабинета или место назначения.';
        }

        RoomInfo? resolveLocation(String value) {
          final query = value.toLowerCase().trim();
          if (query.isEmpty) return null;
          final numeric = RegExp(r'(?<!\\d)(\\d{3}(?:\\.\\d+)?)(?!\\d)')
              .firstMatch(query)
              ?.group(1);
          if (numeric != null) {
            final byNumber = SchoolData.tryRoom(numeric);
            if (byNumber != null) return byNumber;
          }
          final exact = SchoolData.locations.where((room) =>
              room.id.toLowerCase() == query ||
              SchoolData.title(room).toLowerCase() == query ||
              room.name.toLowerCase() == query).toList();
          if (exact.length == 1) return exact.single;

          final matches = SchoolData.locations.where((room) =>
              SchoolData.title(room).toLowerCase().contains(query) ||
              room.name.toLowerCase().contains(query) ||
              query.contains(SchoolData.title(room).toLowerCase())).toList();
          if (matches.length == 1) return matches.single;
          return null;
        }

        final destination = resolveLocation(destinationQuery);
        if (destination == null) {
          final suggestions = SchoolData.locations.where((room) =>
              SchoolData.title(room).toLowerCase().contains(destinationQuery) ||
              room.id.toLowerCase().contains(destinationQuery)).take(8)
              .map((room) => '${SchoolData.title(room)} (этаж ${room.floor})')
              .join(', ');
          return suggestions.isEmpty
              ? 'Не нашёл место «${arg('destination')}» в школьной карте. Проверь номер кабинета или название.'
              : 'Есть несколько/похожие места: $suggestions. Уточни точное назначение.';
        }

        final prefs = await SharedPreferences.getInstance();
        var originId = (prefs.getString('map_start_location') ?? '').trim();
        var startFloor = (prefs.getInt('map_start_floor') ?? 1).clamp(1, 3);
        final originQuery = arg('origin');
        if (originQuery.isNotEmpty &&
            !originQuery.toLowerCase().contains('главн') &&
            !originQuery.toLowerCase().contains('вход')) {
          final origin = resolveLocation(originQuery);
          if (origin == null) {
            return 'Не нашёл точку старта «$originQuery». Укажи номер кабинета или место из школьной карты.';
          }
          originId = origin.id;
          startFloor = origin.floor;
        } else if (originQuery.isNotEmpty) {
          originId = '';
          startFloor = 1;
        }
        final route = RouteEngine.build(
          destination.id,
          startFloor: startFloor,
          startLocationId: originId.isEmpty ? null : originId,
        );
        if (route == null) {
          return 'По текущей схеме не удалось построить маршрут до ${SchoolData.title(destination)}. Я не стану придумывать путь.';
        }
        final steps = RouteEngine.instructions(route);
        final originLabel = originId.isEmpty
            ? 'главный вход'
            : SchoolData.title(SchoolData.room(originId));
        final summary = StringBuffer()
          ..writeln('Маршрут построен по графу коридоров школы.')
          ..writeln('Откуда: $originLabel.')
          ..writeln('Куда: ${SchoolData.title(destination)}, этаж ${destination.floor}.')
          ..writeln('Шаги:')
          ..writeAll(steps.asMap().entries.map(
            (entry) => '${entry.key + 1}. ${entry.value.text} (${entry.value.floor}-й этаж)\\n',
          ));
        return '__OPEN_ROUTE__:${destination.id}\\n$summary';

      case 'open_school_location':
        final locationId = arg('location_id');
        final room = SchoolData.tryRoom(locationId);
        if (room == null) return 'Такой точки нет в справочнике карты. Сначала найди её через search_school_map.';
        return '__OPEN_MAP__:${room.id}';

      case 'set_math_lesson_name':
        await SchoolScheduleCatalog.load();
        final prefs = await SharedPreferences.getInstance();
        final className = (prefs.getString(_studentScopedPreferenceKey(prefs, 'student_class_name')) ??
                prefs.getString('student_class_name') ?? '')
            .trim();
        if (className.isEmpty) return 'Сначала выбери класс в разделе «Расписание».';
        final day = _dayNumber(args['day']);
        final lessonNumber = integer('lesson_number');
        if (day == null || lessonNumber == null || lessonNumber < 1) {
          return 'Не понял день или порядковый номер урока математики.';
        }
        final count = SchoolScheduleCatalog.mathLessonCount(className, day);
        if (lessonNumber > count) {
          return 'В ${{1:'Пн',2:'Вт',3:'Ср',4:'Чт',5:'Пт',6:'Сб'}[day]} у класса $className только $count математических уроков.';
        }
        final requested = arg('subject').toLowerCase();
        String normalized;
        if (requested.isEmpty || requested == 'сброс' || requested == 'обычная математика') {
          normalized = '';
        } else if (requested.contains('геометр')) {
          normalized = 'Геометрия';
        } else if (requested.contains('алгебр')) {
          normalized = 'Алгебра';
        } else if (requested.contains('вероят') || requested.contains('статист')) {
          normalized = 'Вероятность и статистика';
        } else {
          return 'Можно выбрать только алгебру, геометрию или вероятность и статистику.';
        }
        await prefs.setString(
          _studentScopedPreferenceKey(prefs, 'math_subject_${className}_${day}_${lessonNumber - 1}'),
          normalized,
        );
        return normalized.isEmpty
            ? 'Настройка математического урока сброшена.'
            : 'Сохранено: ${{1:'понедельник',2:'вторник',3:'среда',4:'четверг',5:'пятница',6:'суббота'}[day]}, урок математики №$lessonNumber — $normalized.';

      case 'set_subject_group':
        await SchoolScheduleCatalog.load();
        final prefs = await SharedPreferences.getInstance();
        final className = (prefs.getString(_studentScopedPreferenceKey(prefs, 'student_class_name')) ??
                prefs.getString('student_class_name') ?? '')
            .trim();
        if (className.isEmpty) return 'Сначала выбери класс в разделе «Расписание».';
        final subject = arg('subject');
        final group = integer('group');
        if (subject.isEmpty || group == null || group < 1) {
          return 'Укажи предмет и номер группы.';
        }
        final groups = SchoolScheduleCatalog.subjectGroups(className);
        String? actualSubject;
        for (final name in groups.keys) {
          if (name.toLowerCase() == subject.toLowerCase()) {
            actualSubject = name;
            break;
          }
        }
        if (actualSubject == null || !(groups[actualSubject] ?? <int>{}).contains(group)) {
          return 'Для предмета «$subject» в классе $className нет группы №$group. Доступные группы: ${groups[subject]?.join(', ') ?? 'не найдены'}.';
        }
        await prefs.setInt(
          _studentScopedPreferenceKey(prefs, 'student_group_${className}_$actualSubject'),
          group,
        );
        return 'Для предмета «$actualSubject» выбрана группа №$group.';

      case 'set_route_start':
        final floor = integer('floor');
        final locationId = arg('location_id');
        if (floor == null || floor < 1 || floor > 3) {
          return 'Этаж должен быть 1, 2 или 3.';
        }
        if (locationId.isNotEmpty) {
          final room = SchoolData.tryRoom(locationId);
          if (room == null || room.floor != floor) {
            return 'Точка старта не найдена на указанном этаже. Найди её через поиск карты.';
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('map_start_floor', floor);
        if (locationId.isEmpty) {
          await prefs.remove('map_start_location');
        } else {
          await prefs.setString('map_start_location', locationId);
        }
        return locationId.isEmpty
            ? 'Начальная точка маршрутов изменена на главный вход, этаж $floor.'
            : 'Начальная точка маршрутов установлена: ${SchoolData.title(SchoolData.room(locationId))}, этаж $floor.';

      case 'save_personal_note':
        final title = arg('title');
        final body = arg('body');
        if (title.isEmpty && body.isEmpty) return 'Пустую заметку сохранить нельзя.';
        if (title.length > 80 || body.length > 4000) {
          return 'Слишком длинная заметка: заголовок до 80 символов, текст до 4000.';
        }
        final prefs = await SharedPreferences.getInstance();
        final accountId = _currentSchoolUserId(prefs);
        final safeId = accountId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        final storageKey = 'pokolenie_personal_notes_v1_${safeId.isEmpty ? 'local' : safeId}';
        final raw = prefs.getString(storageKey);
        final notes = <Map<String, dynamic>>[];
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              notes.addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
            }
          } catch (_) {
            return 'Существующие заметки повреждены или имеют неизвестный формат; ничего не перезаписал.';
          }
        }
        final now = DateTime.now();
        notes.insert(0, {
          'id': now.microsecondsSinceEpoch.toString(),
          'title': title.isEmpty ? 'Заметка' : title,
          'body': body,
          'updated_at': now.toIso8601String(),
        });
        await prefs.setString(storageKey, jsonEncode(notes));
        return 'Заметка «${title.isEmpty ? 'Заметка' : title}» сохранена на этом устройстве.';

      case 'add_supplement':
        final title = arg('title');
        final day = _dayNumber(args['day']);
        final start = arg('start');
        final end = arg('end');
        final room = arg('room');
        final teacher = arg('teacher');
        final description = arg('description');
        if (title.isEmpty || day == null) return 'Для ДОПа нужны название и корректный день недели.';
        final clockPattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d
  @override
  Widget build(BuildContext context) {
    void menu() => key.currentState?.openDrawer();
    final pages = <Widget>[
      HomePage(userName: widget.userName, theme: widget.theme, onMenu: menu, onMap: () => go(1), onSchedule: () => go(2), onDop: () => go(3), onAnnouncements: _openAnnouncements, onAiChat: _openAiChat),
      MapPage(initialRoom: selectedRoom, onMenu: menu),
      SchedulePage(onMenu: menu, onNotes: _openNotes),
      SupplementsPage(onMenu: menu),
      SettingsPage(theme: widget.theme, userName: widget.userName, onThemeChanged: widget.onThemeChanged, onNameChanged: widget.onNameChanged, onMenu: menu),
    ];
    const destinations = <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Главная'),
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Карта'),
      NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Расписание'),
      NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'ДОПы'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Настройки'),
    ];
    return Scaffold(
      key: key,
      drawer: _drawer(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Row(children: [
            if (wide) ...[
              NavigationRail(
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                onDestinationSelected: go,
                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text('Главная')),
                  NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: Text('Карта')),
                  NavigationRailDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: Text('Расписание')),
                  NavigationRailDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: Text('ДОПы')),
                  NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: Text('Настройки')),
                ],
              ),
              VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
            ],
            Expanded(child: IndexedStack(index: index, children: pages)),
          ]);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(selectedIndex: index, onDestinationSelected: go, destinations: destinations)
          : null,
    );
  }

  Widget _drawer(BuildContext context){final c=Theme.of(context).colorScheme;final items=[(0,Icons.home_rounded,'Главное меню','Обзор'),(1,Icons.map_rounded,'Карта школы','Кабинеты и маршруты'),(2,Icons.calendar_month_rounded,'Расписание','Уроки и группы'),(3,Icons.auto_awesome_rounded,'ДОПы','Кружки и секции'),(4,Icons.settings_rounded,'Настройки','Профиль и кабинет'),(5,Icons.campaign_rounded,'Оповещения','Объявления школы'),(6,Icons.note_alt_rounded,'Мои заметки','Личные записи на устройстве'),(7,Icons.smart_toy_rounded,'ИИ-помощник','Локальный чат без облака')];return Drawer(width: math.min(330, MediaQuery.sizeOf(context).width * .88).toDouble(),child:SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:50,height:50,decoration:BoxDecoration(gradient:LinearGradient(colors:AppPalette.gradient(widget.theme)),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.explore_rounded,color:Colors.white)),const SizedBox(width:12),const Expanded(child:Text('Поколение',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))])),const Divider(height:1),Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[for(final x in items)Card(color:index==x.$1?c.primaryContainer:null,child:ListTile(leading:Icon(x.$2,color:index==x.$1?c.primary:null),title:Text(x.$3,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(x.$4),onTap: () { if (x.$1 == 5) { _openAnnouncements(); } else if (x.$1 == 6) { _openNotes(); } else if (x.$1 == 7) { _openAiChat(); } else { go(x.$1); } }))]))])));}
}
class HomePage extends StatelessWidget {
  final String userName;
  final AppThemeType theme;
  final VoidCallback onMenu, onMap, onSchedule, onDop, onAnnouncements, onAiChat;
  const HomePage({super.key, required this.userName, required this.theme, required this.onMenu, required this.onMap, required this.onSchedule, required this.onDop, required this.onAnnouncements, required this.onAiChat});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.gradient(theme);
    final textColor = theme == AppThemeType.darkBlue ? Colors.white : const Color(0xFF142238);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 980 ? 3 : width >= 640 ? 2 : 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Поколение'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.offline_bolt_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('Офлайн', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: EdgeInsets.fromLTRB(width < 600 ? 16 : 28, 16, width < 600 ? 16 : 28, 32),
            children: [
              Container(
                padding: EdgeInsets.all(width < 600 ? 22 : 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .18), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(color: textColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
                    child: Text('ШКОЛА «ПОКОЛЕНИЕ»', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                  ),
                  const SizedBox(height: 18),
                  Text(userName.trim().isEmpty ? 'Всё для школы\nв одном месте' : 'Привет, $userName!', style: TextStyle(color: textColor, fontSize: width < 600 ? 30 : 38, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  const SizedBox(height: 12),
                  Text('Карта здания, расписание уроков и дополнительные занятия — всё в одном месте.', style: TextStyle(color: textColor.withValues(alpha: .9), fontSize: 15, height: 1.45)),
                  const SizedBox(height: 22),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    _HeroButton('Открыть карту', Icons.explore_rounded, onMap, foreground: textColor),
                    _HeroButton('Моё расписание', Icons.calendar_month_rounded, onSchedule, foreground: textColor),
                    _HeroButton('Спросить ИИ', Icons.auto_awesome_rounded, onAiChat, foreground: textColor),
                  ]),
                ]),
              ),
              const SizedBox(height: 28),
              Row(children: [
                Expanded(child: Text('Быстрый доступ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4))),
                Text('4 раздела', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 3.0 : 1.55,
                children: [
                  _DashboardCard(icon: Icons.map_rounded, title: 'Карта школы', subtitle: 'Найди кабинет и построй маршрут', accent: const Color(0xFF3284F5), onTap: onMap),
                  _DashboardCard(icon: Icons.calendar_month_rounded, title: 'Расписание', subtitle: 'Уроки, группы и кабинеты', accent: const Color(0xFF13A88A), onTap: onSchedule),
                  _DashboardCard(icon: Icons.auto_awesome_rounded, title: 'Дополнительные занятия', subtitle: 'ДОПы, время и преподаватели', accent: const Color(0xFF9667E8), onTap: onDop),
                  _DashboardCard(icon: Icons.campaign_rounded, title: 'Объявления и оповещения', subtitle: 'Новости школы и важные сообщения', accent: const Color(0xFFE58B35), onTap: onAnnouncements),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 46, height: 46, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.offline_pin_rounded, color: Theme.of(context).colorScheme.primary, size: 25)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Работает и без интернета', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 5),
                      Text('Карта и встроенное расписание доступны офлайн. Для обновления ДОПов требуется доступ к школьному intranet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4, fontSize: 13)),
                    ])),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final Color foreground;
  const _HeroButton(this.text, this.icon, this.onTap, {required this.foreground});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(text),
    style: FilledButton.styleFrom(backgroundColor: foreground.withValues(alpha: .13), foregroundColor: foreground, side: BorderSide(color: foreground.withValues(alpha: .24))),
  );
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  const _DashboardCard({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: accent, size: 26)),
            const SizedBox(width: 14),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 5),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
            ])),
            const SizedBox(width: 6),
            Icon(Icons.arrow_outward_rounded, size: 18, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _StartChoice {
  final int floor;
  final String? id;
  const _StartChoice({required this.floor, required this.id});
}

class _StartDialog extends StatefulWidget {
  final int floor;
  final String? id;
  const _StartDialog({required this.floor, required this.id});
  @override State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late int floor = widget.floor;
  late String choice = widget.id ?? '__entrance__';
  @override Widget build(BuildContext context) {
    final rooms = SchoolData.locations.where((r) => r.floor == floor).toList();
    final values = <String>['__entrance__', ...rooms.map((r) => r.id)];
    if (!values.contains(choice)) choice = '__entrance__';
    return AlertDialog(
      title: const Text('Начало маршрута'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<int>(segments: const [ButtonSegment(value:1,label:Text('1 этаж')),ButtonSegment(value:2,label:Text('2 этаж')),ButtonSegment(value:3,label:Text('3 этаж'))], selected:{floor}, onSelectionChanged:(v){setState((){floor=v.first;choice='__entrance__';});}),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(initialValue: choice, isExpanded: true, decoration: const InputDecoration(labelText:'Точка старта'), items: [const DropdownMenuItem(value:'__entrance__',child:Text('Главный вход')), ...rooms.map((r)=>DropdownMenuItem(value:r.id,child:Text(SchoolData.isPlace(r) ? SchoolData.title(r) : '${r.id} — ${r.name}')))], onChanged:(v)=>setState(()=>choice=v??'__entrance__')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(context,_StartChoice(floor:floor,id:choice=='__entrance__'?null:choice)),child:const Text('Сохранить'))],
    );
  }
}
class MapPage extends StatefulWidget {
  final String? initialRoom; final VoidCallback onMenu;
  const MapPage({super.key,this.initialRoom,required this.onMenu});
  @override State<MapPage> createState()=>_MapPageState();
}
class _MapPageState extends State<MapPage>{
  int floor=1; String query=''; String? selected; int startFloor=1; String? startId; final search=TextEditingController();
  @override void initState(){super.initState();selected=widget.initialRoom;if(selected!=null)floor=SchoolData.room(selected!).floor;_load();}
  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoom != oldWidget.initialRoom && widget.initialRoom != null) {
      final room = SchoolData.tryRoom(widget.initialRoom!);
      if (room != null) {
        selected = room.id;
        floor = room.floor;
      }
    }
  }
  Future<void> _load()async{final p=await SharedPreferences.getInstance();startFloor=p.getInt('map_start_floor')??1;startId=p.getString('map_start_location');if(mounted)setState((){});}
  @override void dispose(){search.dispose();super.dispose();}
  List<RoomInfo> get rooms => SchoolData.locationsOnFloor(floor).where((r) => query.isEmpty || r.id.toLowerCase().contains(query.toLowerCase()) || SchoolData.title(r).toLowerCase().contains(query.toLowerCase())).toList();
  Future<void> _start() async {
    final choice = await showDialog<_StartChoice>(
      context: context,
      builder: (_) => _StartDialog(floor: startFloor, id: startId),
    );
    if (choice == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await prefs.setInt('map_start_floor', choice.floor);
    if (choice.id == null) {
      await prefs.remove('map_start_location');
    } else {
      await prefs.setString('map_start_location', choice.id!);
    }

    if (!mounted) return;
    setState(() {
      startFloor = choice.floor;
      startId = choice.id;
    });
  }
  void _open(RoomInfo room) {
    setState(() => selected = room.id);
    final route = RouteEngine.build(
      room.id,
      startFloor: startFloor,
      startLocationId: startId,
    );
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Маршрут для этой точки недоступен.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePage(room: room, route: route),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wideScreen = MediaQuery.sizeOf(context).width >= 900;
    Widget locationsPanel() => Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .8))),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: scheme.surfaceContainerHigh,
            child: ListTile(
              leading: Icon(Icons.my_location_rounded, color: scheme.primary),
              title: const Text('Откуда идём?', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(startId == null ? 'Главный вход' : SchoolData.title(SchoolData.room(startId!))),
              trailing: const Icon(Icons.tune_rounded),
              onTap: _start,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 17, 5, 9),
            child: Row(children: [
              Expanded(child: Text('Этаж $floor', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              Text('${rooms.length} мест', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.search_off_rounded, size: 34, color: scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                const Text('Ничего не найдено', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Попробуй другой номер или название.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ]),
            )
          else
            ...rooms.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Card(
                color: selected == r.id ? scheme.primaryContainer.withValues(alpha: .55) : scheme.surfaceContainer,
                child: ListTile(
                  dense: true,
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)), child: Icon(SchoolData.isPlace(r) ? Icons.place_rounded : Icons.meeting_room_rounded, color: scheme.primary)),
                  title: Text(SchoolData.title(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(SchoolData.isPlace(r) ? 'Специальное место' : 'Кабинет ${r.id}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  onTap: () => _open(r),
                ),
              ),
            )),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Карта школы'),
        actions: [
          IconButton(onPressed: _start, tooltip: 'Начало маршрута', icon: const Icon(Icons.my_location_rounded)),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenMapPage(floor: floor, selectedRoom: selected, routeRoom: null, startFloor: startFloor, startLocationId: startId))), tooltip: 'Полноэкранная карта', icon: const Icon(Icons.fullscreen_rounded)),
          IconButton(onPressed: () => setState(() { query = ''; search.clear(); }), tooltip: 'Очистить поиск', icon: const Icon(Icons.clear_all_rounded)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: TextField(controller: search, onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Кабинет, бассейн, библиотека…'))),
                const SizedBox(width: 10),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
                  selected: {floor},
                  onSelectionChanged: (v) => setState(() => floor = v.first),
                ),
              ]),
            ),
            Expanded(
              child: wideScreen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(children: [
                        Expanded(flex: 3, child: _MapImage(floor: floor, selected: selected)),
                        const SizedBox(width: 14),
                        SizedBox(width: 350, child: locationsPanel()),
                      ]),
                    )
                  : Column(children: [
                      SizedBox(height: math.min(320.0, constraints.maxHeight * .40), child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: _MapImage(floor: floor, selected: selected))),
                      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: locationsPanel())),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

}
class _MapImage extends StatelessWidget{final int floor;final String? selected;const _MapImage({required this.floor,required this.selected});@override Widget build(BuildContext context)=>Card(clipBehavior:Clip.antiAlias,child:InteractiveViewer(minScale:.7,maxScale:4,child:AspectRatio(aspectRatio:7016/4960,child:Stack(children:[Positioned.fill(child:Image.asset('assets/maps/floor$floor.webp',fit:BoxFit.contain)),if(selected!=null)Positioned.fill(child:CustomPaint(painter:_PointPainter(SchoolData.point(SchoolData.room(selected!)),Theme.of(context).colorScheme.primary)))]))));}
class _PointPainter extends CustomPainter{final Offset p;final Color color;_PointPainter(this.p,this.color);@override void paint(Canvas c,Size s){final o=Offset(p.dx*s.width,p.dy*s.height);c.drawCircle(o,9,Paint()..color=color);c.drawCircle(o,17,Paint()..color=color.withValues(alpha:.22));}@override bool shouldRepaint(covariant _PointPainter o)=>o.p!=p||o.color!=color;}
class _MathByDayDialog extends StatefulWidget {
  final String className;
  const _MathByDayDialog({required this.className});
  @override State<_MathByDayDialog> createState() => _MathByDayDialogState();
}
class _MathByDayDialogState extends State<_MathByDayDialog> {
  static const days = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];
  static const subjects = ['', 'Алгебра', 'Геометрия', 'Вероятность и статистика'];
  final selected = <String, String>{};
  @override void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        for (var d = 1; d <= 6; d++) {
          for (var slot = 0; slot < 6; slot++) {
            selected['$d|$slot'] = p.getString(_studentScopedPreferenceKey(p, 'math_subject_${widget.className}_${d}_$slot')) ?? '';
          }
        }
      });
    });
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Раздельная математика'),
    content: SizedBox(width: MediaQuery.sizeOf(context).width * .82, child: ListView(shrinkWrap: true, children: [
      const Text('Настрой названия математических уроков отдельно для каждого дня. Если уроков несколько, они идут по времени: первый, второй и далее.'),
      const SizedBox(height: 10),
      for (var d = 1; d <= 6; d++) ...[
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(days[d - 1], style: const TextStyle(fontWeight: FontWeight.w800))),
        for (var slot = 0; slot < SchoolScheduleCatalog.mathLessonCount(widget.className, d); slot++)
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Математика — урок ${slot + 1}', isDense: true),
            initialValue: subjects.contains(selected['$d|$slot'] ?? '') ? selected['$d|$slot'] : '',
            items: subjects.map((x) => DropdownMenuItem(value: x, child: Text(x.isEmpty ? 'Не переименовывать' : x))).toList(),
            onChanged: (v) => setState(() => selected['$d|$slot'] = v ?? ''),
          ),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () async {
        final p = await SharedPreferences.getInstance();
        for (var d = 1; d <= 6; d++) {
          for (var slot = 0; slot < 6; slot++) {
            await p.setString(_studentScopedPreferenceKey(p, 'math_subject_${widget.className}_${d}_$slot'), selected['$d|$slot'] ?? '');
          }
        }
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('Сохранить')),
    ],
  );
}

class SchedulePage extends StatefulWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotes;
  const SchedulePage({super.key, required this.onMenu, required this.onNotes});
  @override State<SchedulePage> createState() => _SchedulePageState();
}
class _SchedulePageState extends State<SchedulePage> {
  int day = DateTime.now().weekday > 6 ? 1 : DateTime.now().weekday;
  List<ScheduleEntry> entries = []; String classId = ''; bool loading = true;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  @override void initState() { super.initState(); _load(); _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _now = DateTime.now()); }); }
  @override void dispose() { _clockTimer?.cancel(); super.dispose(); }
  String? _breakCountdown(List<ScheduleEntry> dayEntries) => SchoolBellCountdown.describe(
    selectedDay: day,
    now: _now,
    lessons: dayEntries.map((entry) => (time: entry.time, subject: entry.subject)).toList(),
  );
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance(); await SchoolScheduleCatalog.load();
    try { await SchoolScheduleCatalog.refreshOnline(); } catch (_) {}
    classId = p.getString('student_class_name') ?? '';
    final groups = <String,int>{};
    if (classId.isNotEmpty) {
      for (final s in SchoolScheduleCatalog.splitSubjects(classId)) {
        groups[s] = p.getInt(_studentScopedPreferenceKey(p, 'student_group_${classId}_$s')) ?? 1;
      }
      final mathNames = <int, List<String>>{};
      for (var d = 1; d <= 6; d++) {
        final dayNames = <String>[];
        for (var slot = 0; slot < 6; slot++) {
          dayNames.add(p.getString(_studentScopedPreferenceKey(p, 'math_subject_${classId}_${d}_$slot')) ?? '');
        }
        mathNames[d] = dayNames;
      }
      entries = SchoolScheduleCatalog.buildPersonal(classId, groups, mathNamesByDay: mathNames);
    } else { entries = []; }
    if (mounted) setState(() => loading = false);
    try { await LocalNotificationService().scheduleUpcomingLessons(entries: entries.map((e) => (id:e.id,day:e.day,time:e.time,subject:e.subject,room:e.room)).toList()); } catch (_) {}
    if (classId.isEmpty && mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _chooseClass(required: true));
  }
  Future<void> _chooseClass({bool required = false}) async {
    final selected = await showDialog<String>(context: context, barrierDismissible: !required, builder: (_) => _StudentClassDialog(requiredChoice: required));
    if (selected == null || selected.isEmpty) return;
    final p = await SharedPreferences.getInstance(); await p.setString('student_class_name', selected); await p.setString('student_class_id', selected);
    if (!mounted) return; await showStudentGroupSelection(context, selected); await _load();
  }
  void _route(ScheduleEntry e) {
    if (e.room.isEmpty) return;
    final destination = SchoolData.tryRoom(e.room);
    if (destination == null) return;
    final sameDay = entries.where((x) => x.day == e.day).toList()..sort((a, b) => a.time.compareTo(b.time));
    final currentIndex = sameDay.indexWhere((x) => x.id == e.id);
    RoomInfo? previousRoom;
    if (currentIndex > 0) {
      for (var i = currentIndex - 1; i >= 0; i--) {
        final candidate = sameDay[i];
        if (candidate.room.isEmpty) continue;
        previousRoom = SchoolData.tryRoom(candidate.room);
        if (previousRoom != null) break;
      }
    }
    final route = RouteEngine.build(destination.id,
      startFloor: previousRoom?.floor ?? 1,
      startLocationId: previousRoom?.id,
    );
    if (route != null) Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePage(room: destination, route: route)));
  }
  @override
  Widget build(BuildContext context) {
    final list = entries.where((e) => e.day == day).toList()..sort((a, b) => a.time.compareTo(b.time));
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final splitSubjects = SchoolScheduleCatalog.splitSubjects(classId);
    final breakCountdown = _breakCountdown(list);
    const dayNames = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Расписание'),
        actions: [
          if (width >= 460)
            IconButton(
              tooltip: 'Мои заметки',
              onPressed: widget.onNotes,
              icon: const Icon(Icons.note_alt_outlined),
            ),
          IconButton(tooltip: 'Выбрать класс', onPressed: () => _chooseClass(), icon: const Icon(Icons.school_rounded)),
          if (classId.isNotEmpty) ...[
            IconButton(tooltip: 'Группы по предметам', onPressed: () async { await showStudentGroupSelection(context, classId); await _load(); }, icon: const Icon(Icons.groups_rounded)),
            IconButton(tooltip: 'Раздельная математика по дням', onPressed: () async { await showDialog<void>(context: context, builder: (_) => _MathByDayDialog(className: classId)); await _load(); }, icon: const Icon(Icons.functions_rounded)),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Padding(
            padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.calendar_month_rounded, color: scheme.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(classId.isEmpty ? 'Твоё расписание' : 'Класс $classId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                      const SizedBox(height: 4),
                      Text(
                        classId.isEmpty ? 'Выбери класс, чтобы загрузить уроки' : '${dayNames[day]} • ${list.length} ${list.length == 1 ? 'урок' : (list.length >= 2 && list.length <= 4 ? 'урока' : 'уроков')}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ])),
                    if (classId.isNotEmpty)
                      IconButton(onPressed: () async { await showStudentGroupSelection(context, classId); await _load(); }, tooltip: 'Настроить группы', icon: const Icon(Icons.tune_rounded)),
                  ]),
                ),
                const SizedBox(height: 16),
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
                if (!loading && classId.isNotEmpty && breakCountdown != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.tertiary.withValues(alpha: .25)),
                    ),
                    child: Row(children: [
                      Icon(Icons.hourglass_bottom_rounded, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(child: Text(breakCountdown, style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w800, fontSize: 13))),
                    ]),
                  ),
                ],
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : classId.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.school_outlined, size: 48, color: scheme.primary),
                                  const SizedBox(height: 12),
                                  const Text('Сначала выбери свой класс', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                                  const SizedBox(height: 6),
                                  Text('Приложение покажет предметы, группы и кабинеты именно для него.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(onPressed: () => _chooseClass(required: true), icon: const Icon(Icons.school_rounded), label: const Text('Выбрать класс')),
                                ]),
                              ),
                            )
                          : list.isEmpty
                              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.event_available_rounded, size: 44, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 10),
                                  const Text('В этот день уроков нет', style: TextStyle(fontWeight: FontWeight.w800)),
                                ]))
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  itemCount: list.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                                  itemBuilder: (context, index) {
                                    final e = list[index];
                                    final room = e.room.isEmpty ? null : SchoolData.tryRoom(e.room);
                                    final times = RegExp(r'\d{1,2}:\d{2}').allMatches(e.time).map((m) => m.group(0)!).toList();
                                    final startTime = times.isNotEmpty ? times.first : e.time;
                                    final endTime = times.length > 1 ? times[1] : '';
                                    return Card(
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.all(13),
                                        child: Row(children: [
                                          Container(
                                            width: 76,
                                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                                            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)),
                                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                                              Text(startTime, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 14)),
                                              if (endTime.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text(endTime, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                                              ],
                                            ]),
                                          ),
                                          const SizedBox(width: 13),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(e.subject, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                            const SizedBox(height: 6),
                                            Wrap(spacing: 8, runSpacing: 5, children: [
                                              if (e.room.isNotEmpty)
                                                _ScheduleTag(icon: Icons.meeting_room_outlined, label: 'Каб. ${e.room}'),
                                              if (e.teacher.isNotEmpty)
                                                _ScheduleTag(icon: Icons.person_outline_rounded, label: e.teacher),
                                              if (splitSubjects.contains(e.subject) && e.group > 0)
                                                _ScheduleTag(icon: Icons.groups_2_outlined, label: 'Группа ${e.group}'),
                                            ]),
                                          ])),
                                          IconButton(
                                            onPressed: room == null ? null : () => _route(e),
                                            tooltip: room == null ? 'Маршрут для кабинета недоступен' : 'Как пройти',
                                            icon: const Icon(Icons.directions_rounded),
                                          ),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
class _ScheduleTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ScheduleTag({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class RoutePage extends StatelessWidget {
  final RoomInfo room;
  final RouteResult route;
  const RoutePage({super.key, required this.room, required this.route});

  @override
  Widget build(BuildContext context) {
    final steps = RouteEngine.instructions(route);
    final floors = route.nodes.map((n) => n.floor).toSet().toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    final origin = route.startLocationId == null ? 'Главный вход' : SchoolData.title(SchoolData.room(route.startLocationId!));
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: ListView(
            padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.directions_rounded, color: scheme.primary, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(SchoolData.title(room), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                    const SizedBox(height: 5),
                    Text('Откуда: $origin', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text('Этаж назначения: ${room.floor} • ${floors.length} ${floors.length == 1 ? 'этаж' : 'этажа'} на маршруте', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ])),
                  Icon(Icons.flag_rounded, color: scheme.primary, size: 24),
                ]),
              ),
              const SizedBox(height: 22),
              Text('План маршрута', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final floor in floors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
                        child: Row(children: [
                          Tooltip(message: 'Этаж, по которому проходит маршрут', child: Icon(Icons.layers_rounded, color: scheme.primary)),
                          const SizedBox(width: 9),
                          Expanded(child: Text('$floor этаж', style: const TextStyle(fontWeight: FontWeight.w900))),
                          if (floor == room.floor)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text('Назначение', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11))),
                        ]),
                      ),
                      AspectRatio(
                        aspectRatio: 7016 / 4960,
                        child: Stack(children: [
                          Positioned.fill(child: Image.asset('assets/maps/floor$floor.webp', fit: BoxFit.contain)),
                          Positioned.fill(child: CustomPaint(painter: _RoutePainter(route.nodes, floor, const Color(0xFFFF2D95)))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Пошаговые инструкции', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final item in steps.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)), child: Center(child: Text('${item.key + 1}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 15)))),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.value.text, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35)),
                          const SizedBox(height: 5),
                          Text('${item.value.floor} этаж', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                        ])),
                        Icon(item.value.icon, color: scheme.primary),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<RouteNode> nodes;
  final int floor;
  final Color color;
  _RoutePainter(this.nodes, this.floor, this.color);

  @override
  void paint(Canvas c, Size s) {
    if (nodes.length < 2) return;
    final path = Path();
    var drawing = false;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.floor != floor) {
        drawing = false;
        continue;
      }
      final point = Offset(node.point.dx * s.width, node.point.dy * s.height);
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        final previous = nodes[i - 1];
        // Never bridge a floor transition: that would draw a false straight
        // line between two physically separate staircases on this floor.
        if (previous.floor == floor) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
        }
      }
    }
    // White halo keeps the route readable over every department/map color.
    c.drawPath(path, Paint()
      ..color = Colors.white.withValues(alpha: .95)
      ..strokeWidth = 11
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    c.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.nodes != nodes || old.floor != floor || old.color != color;
}
class FullscreenMapPage extends StatefulWidget {
  final int floor;
  final String? selectedRoom;
  final String? routeRoom;
  final int startFloor;
  final String? startLocationId;

  const FullscreenMapPage({
    super.key,
    required this.floor,
    required this.selectedRoom,
    required this.routeRoom,
    required this.startFloor,
    required this.startLocationId,
  });

  @override
  State<FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<FullscreenMapPage> {
  late int floor = widget.floor;
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _changeZoom(double delta, Size size) {
    final current = _zoom.value.getMaxScaleOnAxis();
    final next = (current + delta).clamp(.6, 6.0).toDouble();
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
        size.width * (1 - next) / 2,
        size.height * (1 - next) / 2,
        0,
        1,
      )
      ..scaleByDouble(next, next, next, 1);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedRoom == null ? null : SchoolData.tryRoom(widget.selectedRoom!);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$floor этаж • полноэкранная карта'),
        actions: [
          if (selected != null && selected.floor == floor)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(SchoolData.title(selected), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 этаж')),
                      ButtonSegment(value: 2, label: Text('2 этаж')),
                      ButtonSegment(value: 3, label: Text('3 этаж')),
                    ],
                    selected: {floor},
                    onSelectionChanged: (value) {
                      setState(() {
                        floor = value.first;
                        _zoom.value = Matrix4.identity();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Сбросить масштаб',
                  onPressed: () => setState(() => _zoom.value = Matrix4.identity()),
                  icon: const Icon(Icons.fit_screen_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: .6,
                      maxScale: 6,
                      boundaryMargin: const EdgeInsets.all(100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: AspectRatio(
                            aspectRatio: 7016 / 4960,
                            child: Stack(
                              children: [
                                Positioned.fill(child: Image.asset('assets/maps/floor$floor.webp', fit: BoxFit.contain)),
                                if (selected != null && selected.floor == floor)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _PointPainter(SchoolData.point(selected), scheme.primary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_in',
                          tooltip: 'Увеличить',
                          onPressed: () => _changeZoom(.35, Size(constraints.maxWidth, constraints.maxHeight)),
                          child: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_out',
                          tooltip: 'Уменьшить',
                          onPressed: () => _changeZoom(-.35, Size(constraints.maxWidth, constraints.maxHeight)),
                          child: const Icon(Icons.remove_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleEditor extends StatefulWidget {
  final ScheduleEntry? initial;
  final int defaultDay;
  const ScheduleEditor({super.key, this.initial, this.defaultDay = 1});
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late int day;
  late TextEditingController time;
  late TextEditingController subject;
  late TextEditingController room;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    day = e?.day ?? widget.defaultDay;
    time = TextEditingController(text: e?.time ?? '');
    subject = TextEditingController(text: e?.subject ?? '');
    room = TextEditingController(text: e?.room ?? '');
  }

  @override
  void dispose() {
    time.dispose();
    subject.dispose();
    room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(560.0, size.width - 32).toDouble(),
          maxHeight: math.min(620.0, size.height - 32).toDouble(),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? 'Добавить урок' : 'Изменить урок', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
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
                onChanged: (v) => setState(() => day = v ?? widget.defaultDay),
              ),
              const SizedBox(height: 10),
              TextField(controller: time, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Время', hintText: '08:30')),
              const SizedBox(height: 10),
              TextField(controller: subject, decoration: const InputDecoration(labelText: 'Предмет')),
              const SizedBox(height: 10),
              TextField(controller: room, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Кабинет', hintText: '311')),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (subject.text.trim().isEmpty) return;
                      Navigator.pop(
                        context,
                        ScheduleEntry(
                          id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                          day: day,
                          time: time.text.trim(),
                          subject: subject.text.trim(),
                          room: room.text.trim(),
                        ),
                      );
                    },
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final AppThemeType theme;
  final String userName;
  final ValueChanged<AppThemeType> onThemeChanged;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onMenu;
  const SettingsPage({super.key, required this.theme, required this.userName, required this.onThemeChanged, required this.onNameChanged, required this.onMenu});

  Future<void> _openAdmin(BuildContext context) async {
    final account = await showDialog<AdminAccount>(context: context, builder: (_) => const AdminLoginDialog());
    if (account == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPanelPage(account: account)));
  }

  Future<void> _serverAdminLogin(BuildContext context, String baseUrl) async {
    final login = TextEditingController();
    final password = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Технический вход администратора'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Только для первого запуска и восстановления доступа. Для обычной работы используй школьный SSO.'),
          const SizedBox(height: 12),
          TextField(controller: login, autofocus: true, decoration: const InputDecoration(labelText: 'Логин администратора')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль администратора')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (login.text.trim().isEmpty || password.text.isEmpty) return;
            Navigator.pop(dialogContext, {'username': login.text.trim(), 'password': password.text});
          }, child: const Text('Войти')),
        ],
      ),
    );
    login.dispose(); password.dispose();
    if (result == null) return;
    try {
      await SchoolAccountService().signInAsServerAdmin(
        baseUrl, username: result['username']!, password: result['password']!,
      );
      unawaited(desktop_polling.startDesktopNotificationPolling());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Технический вход выполнен.')));
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
      }
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), duration: const Duration(seconds: 6)),
      );
    }
  }

  Future<void> _schoolAccount(BuildContext context) async {
    final service = SchoolAccountService();
    final current = await service.currentUser();
    if (!context.mounted) return;
    if (current != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Школьная учётная запись'),
          content: Text('Вход выполнен: ${current['display_name'] ?? current['username'] ?? 'учётная запись'}\nРоль: ${current['role'] ?? 'не указана'}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Закрыть')),
            OutlinedButton(onPressed: () => Navigator.pop(dialogContext, 'signout'), child: const Text('Выйти')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'portal'),
              child: Text(current['role'] == 'student' ? 'Мои оповещения' : 'Открыть кабинет'),
            ),
          ],
        ),
      );
      if (action == 'signout') {
        await service.signOut();
        await desktop_polling.stopDesktopNotificationPolling();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы вышли из школьной учётной записи.')));
      } else if (action == 'portal' && context.mounted) {
        if (current['role'] == 'student') {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
        } else {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
        }
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('navigator_api_enabled') ?? false;
    final baseUrl = (prefs.getString('navigator_api_url') ?? '').trim();
    if (!enabled || baseUrl.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала настрой адрес API в «Кабинет школы → Сервер».')));
      return;
    }
    final loginMethod = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Вход в Поколение'),
        content: const Text('Выбери школьный вход. Технический вход нужен только администратору для первоначальной настройки или восстановления доступа.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Отмена')),
          OutlinedButton(onPressed: () => Navigator.pop(dialogContext, 'admin'), child: const Text('Технический вход')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'sso'), child: const Text('Школьный SSO')),
        ],
      ),
    );
    if (!context.mounted || loginMethod == null || loginMethod == 'cancel') return;
    if (loginMethod == 'admin') {
      await _serverAdminLogin(context, baseUrl);
      return;
    }
    try {
      final result = await service.signInWithSchoolAccount(baseUrl);
      final user = Map<String, dynamic>.from(result['user'] as Map);
      unawaited(desktop_polling.startDesktopNotificationPolling());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Вход выполнен: ${user['display_name'] ?? user['username'] ?? 'учётная запись'}.${result['push_registered'] == true ? ' Уведомления подключены.' : ' Push-уведомления пока не настроены.'}'),
          duration: const Duration(seconds: 5),
        ));
        if (user['role'] == 'student') {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
        } else {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
        }
      }
    } catch (error) {
      if (context.mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
      }
    }
  }

  Future<void> _openSchoolCabinet(BuildContext context) async {
    final service = SchoolAccountService();
    final current = await service.currentUser();
    if (!context.mounted) return;
    if (current != null) {
      if (current['role'] == 'student') {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
      } else {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
      }
      return;
    }
    await _schoolAccount(context);
  }

  Future<void> _editClass(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        final classId = (account is Map ? account['class_id'] : null)?.toString().trim() ?? '';
        if (account is Map && account['role'] == 'student' && classId.isNotEmpty) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Класс поступает из школьной учётной записи. Если он неверный, обратись к школьному администратору.')),
          );
          return;
        }
      } catch (_) {}
    }
    await SchoolScheduleCatalog.load();
    final result = await showDialog<String>(context: context, builder: (_) => const _StudentClassDialog());
    if (!context.mounted || result == null || result.isEmpty) return;
    await prefs.setString('student_class_name', result);
    await prefs.setString('student_class_id', result);
    if (!context.mounted) return;
    await showStudentGroupSelection(context, result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Профиль расписания: $result')),
      );
    }
  }

  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)), title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w900))), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
      const Text('Профиль', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.person_rounded, color: c.primary), title: const Text('Имя'), subtitle: Text(userName.isEmpty ? 'Не задано' : userName), trailing: const Icon(Icons.edit_rounded), onTap: () => _editName(context))),
      Card(child: ListTile(leading: Icon(Icons.school_rounded, color: c.primary), title: const Text('Мой класс'), subtitle: const Text('Класс используется как источник базового расписания'), trailing: const Icon(Icons.edit_rounded), onTap: () => _editClass(context))),
      Card(child: ListTile(leading: Icon(Icons.groups_rounded, color: c.primary), title: const Text('Группы по предметам'), subtitle: const Text('Например: английский — 1, математика — 2'), trailing: const Icon(Icons.tune_rounded), onTap: () async { final p = await SharedPreferences.getInstance(); final cls = p.getString('student_class_name') ?? ''; if (cls.isNotEmpty && context.mounted) await showStudentGroupSelection(context, cls); })),
      const SizedBox(height: 18), const Text('Оформление', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.palette_rounded, color: c.primary), title: const Text('Цветовая тема'), subtitle: Text(AppPalette.name(theme)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _pickTheme(context))),
      const SizedBox(height: 18), const Text('Для сотрудников', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.verified_user_rounded, color: c.primary), title: const Text('Школьная учётная запись'), subtitle: const Text('Безопасный вход через школьный SSO и регистрация уведомлений'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _schoolAccount(context))),
      Card(child: ListTile(leading: Icon(Icons.admin_panel_settings_rounded, color: c.primary), title: const Text('Кабинет школы'), subtitle: const Text('Сотрудникам — управление по роли; ученикам — школьные оповещения'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openSchoolCabinet(context))),
      Card(child: ListTile(leading: Icon(Icons.cloud_sync_rounded, color: c.primary), title: const Text('Настройки подключения'), subtitle: const Text('Адрес API, включение онлайн-режима и проверка соединения'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openAdmin(context))),
      const SizedBox(height: 18), const Text('Приложение', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: Column(children: [ListTile(leading: Icon(Icons.info_outline_rounded, color: c.primary), title: const Text('О приложении'), subtitle: const Text('Приложение школы «Поколение»'), onTap: () => showAboutDialog(context: context, applicationName: 'Поколение', applicationLegalese: 'Приложение школы «Поколение»')), const Divider(height: 1), ListTile(leading: Icon(Icons.restore_rounded, color: c.primary), title: const Text('Сбросить тему'), onTap: () => onThemeChanged(AppThemeType.turquoise))])),
    ]))));
  }

  Future<void> _editName(BuildContext context) async {
    final result = await showDialog<String>(context: context, builder: (_) => _EditValueDialog(title: 'Изменить имя', label: 'Имя', hint: 'Как к тебе обращаться?', initialValue: userName));
    if (!context.mounted || result == null || result.isEmpty) return;
    onNameChanged(result);
  }
  void _pickTheme(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [const Text('Цветовая тема', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 12), _ThemeTile(title: 'Жёлтая', description: 'Жёлтый → бежевый', colors: AppPalette.yellow, selected: theme == AppThemeType.yellow, onTap: () { onThemeChanged(AppThemeType.yellow); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Бирюзовая', description: 'Насыщенный бирюзовый → светло-зелёный', colors: AppPalette.turquoise, selected: theme == AppThemeType.turquoise, onTap: () { onThemeChanged(AppThemeType.turquoise); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Тёмно-синяя', description: 'Тёмно-синий → синий', colors: AppPalette.darkBlue, selected: theme == AppThemeType.darkBlue, onTap: () { onThemeChanged(AppThemeType.darkBlue); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Фиолетовая', description: 'Фиолетовый → сиреневый', colors: AppPalette.violet, selected: theme == AppThemeType.violet, onTap: () { onThemeChanged(AppThemeType.violet); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Коралловая', description: 'Коралловый → тёплый персиковый', colors: AppPalette.coral, selected: theme == AppThemeType.coral, onTap: () { onThemeChanged(AppThemeType.coral); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Зелёная', description: 'Изумрудный → мятный', colors: AppPalette.green, selected: theme == AppThemeType.green, onTap: () { onThemeChanged(AppThemeType.green); Navigator.pop(sheetContext); })])));
}

class _EditValueDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String initialValue;
  const _EditValueDialog({required this.title, required this.label, required this.hint, required this.initialValue});

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, autofocus: true, textInputAction: TextInputAction.done, decoration: InputDecoration(labelText: widget.label, hintText: widget.hint), onSubmitted: (_) => Navigator.pop(context, controller.text.trim())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить')),
    ],
  );
}

class _ThemeTile extends StatelessWidget { final String title; final String description; final List<Color> colors; final bool selected; final VoidCallback onTap; const _ThemeTile({required this.title, required this.description, required this.colors, required this.selected, required this.onTap}); @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 58, height: 58, decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(16))), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(description, style: const TextStyle(fontSize: 12))])), Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? colors.first : null)])))); }
);
        if ((start.isNotEmpty && !clockPattern.hasMatch(start)) ||
            (end.isNotEmpty && !clockPattern.hasMatch(end))) {
          return 'Время должно быть в формате HH:mm или оставлено пустым, если оно неизвестно.';
        }
        final prefs = await SharedPreferences.getInstance();
        final accountId = _currentSchoolUserId(prefs);
        final storageKey = studentProfilePreferenceKey('supplements_local', userId: accountId);
        final raw = prefs.getString(storageKey);
        final supplements = <Map<String, dynamic>>[];
        if (raw != null) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) supplements.addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
          } catch (_) {
            return 'Существующий список ДОПов не удалось прочитать; я ничего не перезаписал.';
          }
        }
        final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
        supplements.add({
          'id': id,
          'title': title,
          'weekday': day,
          'start': start,
          'end': end,
          'teacher': teacher,
          'room': room,
          'place': '',
          'group': '',
          'description': description,
        });
        await prefs.setString(storageKey, jsonEncode(supplements));
        if (prefs.getBool('dop_reminders_enabled') ?? false) {
          try {
            await LocalNotificationService().scheduleUpcomingSupplements(
              entries: supplements.map((item) => (
                id: item['id'].toString(),
                day: (item['weekday'] as num?)?.toInt() ?? 1,
                time: item['start'].toString(),
                title: item['title'].toString(),
                room: item['room'].toString(),
              )).toList(),
            );
          } catch (_) {}
        }
        return 'Добавлено локальное занятие «$title» на ${{1:'понедельник',2:'вторник',3:'среду',4:'четверг',5:'пятницу',6:'субботу'}[day]}. Серверная запись не создавалась.';

      case 'delete_supplement':
        final title = arg('title');
        if (title.isEmpty) return 'Укажи точное название ДОПа.';
        final prefs = await SharedPreferences.getInstance();
        final accountId = _currentSchoolUserId(prefs);
        final storageKey = studentProfilePreferenceKey('supplements_local', userId: accountId);
        final raw = prefs.getString(storageKey);
        if (raw == null) return 'Локальный список ДОПов пуст.';
        List<dynamic> decoded;
        try {
          decoded = jsonDecode(raw) as List<dynamic>;
        } catch (_) {
          return 'Список ДОПов повреждён; я ничего не менял.';
        }
        final matches = decoded.where((item) =>
          item is Map && (item['title'] ?? '').toString().trim().toLowerCase() == title.toLowerCase()).length;
        if (matches == 0) return 'ДОП «$title» не найден.';
        if (matches > 1) return 'Найдено несколько занятий с таким названием. Уточни день недели.';
        final updated = decoded.where((item) =>
          !(item is Map && (item['title'] ?? '').toString().trim().toLowerCase() == title.toLowerCase())).toList();
        await prefs.setString(storageKey, jsonEncode(updated));
        return 'Локальный ДОП «$title» удалён.';

      default:
        return 'Неизвестное действие приложения: $action.';
    }
  }
  @override
  Widget build(BuildContext context) {
    void menu() => key.currentState?.openDrawer();
    final pages = <Widget>[
      HomePage(userName: widget.userName, theme: widget.theme, onMenu: menu, onMap: () => go(1), onSchedule: () => go(2), onDop: () => go(3), onAnnouncements: _openAnnouncements),
      MapPage(initialRoom: selectedRoom, onMenu: menu),
      SchedulePage(onMenu: menu, onNotes: _openNotes),
      SupplementsPage(onMenu: menu),
      SettingsPage(theme: widget.theme, userName: widget.userName, onThemeChanged: widget.onThemeChanged, onNameChanged: widget.onNameChanged, onMenu: menu),
    ];
    const destinations = <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Главная'),
      NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Карта'),
      NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Расписание'),
      NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'ДОПы'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Настройки'),
    ];
    return Scaffold(
      key: key,
      drawer: _drawer(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Row(children: [
            if (wide) ...[
              NavigationRail(
                selectedIndex: index,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                onDestinationSelected: go,
                destinations: const [
                  NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text('Главная')),
                  NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: Text('Карта')),
                  NavigationRailDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: Text('Расписание')),
                  NavigationRailDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: Text('ДОПы')),
                  NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: Text('Настройки')),
                ],
              ),
              VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
            ],
            Expanded(child: IndexedStack(index: index, children: pages)),
          ]);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(selectedIndex: index, onDestinationSelected: go, destinations: destinations)
          : null,
    );
  }

  Widget _drawer(BuildContext context){final c=Theme.of(context).colorScheme;final items=[(0,Icons.home_rounded,'Главное меню','Обзор'),(1,Icons.map_rounded,'Карта школы','Кабинеты и маршруты'),(2,Icons.calendar_month_rounded,'Расписание','Уроки и группы'),(3,Icons.auto_awesome_rounded,'ДОПы','Кружки и секции'),(4,Icons.settings_rounded,'Настройки','Профиль и кабинет'),(5,Icons.campaign_rounded,'Оповещения','Объявления школы'),(6,Icons.note_alt_rounded,'Мои заметки','Личные записи на устройстве'),(7,Icons.smart_toy_rounded,'ИИ-помощник','Локальный чат без облака')];return Drawer(width: math.min(330, MediaQuery.sizeOf(context).width * .88).toDouble(),child:SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:50,height:50,decoration:BoxDecoration(gradient:LinearGradient(colors:AppPalette.gradient(widget.theme)),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.explore_rounded,color:Colors.white)),const SizedBox(width:12),const Expanded(child:Text('Поколение',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))])),const Divider(height:1),Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[for(final x in items)Card(color:index==x.$1?c.primaryContainer:null,child:ListTile(leading:Icon(x.$2,color:index==x.$1?c.primary:null),title:Text(x.$3,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(x.$4),onTap: () { if (x.$1 == 5) { _openAnnouncements(); } else if (x.$1 == 6) { _openNotes(); } else if (x.$1 == 7) { _openAiChat(); } else { go(x.$1); } }))]))])));}
}
class HomePage extends StatelessWidget {
  final String userName;
  final AppThemeType theme;
  final VoidCallback onMenu, onMap, onSchedule, onDop, onAnnouncements;
  const HomePage({super.key, required this.userName, required this.theme, required this.onMenu, required this.onMap, required this.onSchedule, required this.onDop, required this.onAnnouncements});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.gradient(theme);
    final textColor = theme == AppThemeType.darkBlue ? Colors.white : const Color(0xFF142238);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 980 ? 3 : width >= 640 ? 2 : 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Поколение'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.offline_bolt_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('Офлайн', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: EdgeInsets.fromLTRB(width < 600 ? 16 : 28, 16, width < 600 ? 16 : 28, 32),
            children: [
              Container(
                padding: EdgeInsets.all(width < 600 ? 22 : 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: colors.first.withValues(alpha: .18), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(color: textColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
                    child: Text('ШКОЛА «ПОКОЛЕНИЕ»', style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                  ),
                  const SizedBox(height: 18),
                  Text(userName.trim().isEmpty ? 'Всё для школы\nв одном месте' : 'Привет, $userName!', style: TextStyle(color: textColor, fontSize: width < 600 ? 30 : 38, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  const SizedBox(height: 12),
                  Text('Карта здания, расписание уроков и дополнительные занятия — всё в одном месте.', style: TextStyle(color: textColor.withValues(alpha: .9), fontSize: 15, height: 1.45)),
                  const SizedBox(height: 22),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    _HeroButton('Открыть карту', Icons.explore_rounded, onMap, foreground: textColor),
                    _HeroButton('Моё расписание', Icons.calendar_month_rounded, onSchedule, foreground: textColor),
                  ]),
                ]),
              ),
              const SizedBox(height: 28),
              Row(children: [
                Expanded(child: Text('Быстрый доступ', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4))),
                Text('4 раздела', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 3.0 : 1.55,
                children: [
                  _DashboardCard(icon: Icons.map_rounded, title: 'Карта школы', subtitle: 'Найди кабинет и построй маршрут', accent: const Color(0xFF3284F5), onTap: onMap),
                  _DashboardCard(icon: Icons.calendar_month_rounded, title: 'Расписание', subtitle: 'Уроки, группы и кабинеты', accent: const Color(0xFF13A88A), onTap: onSchedule),
                  _DashboardCard(icon: Icons.auto_awesome_rounded, title: 'Дополнительные занятия', subtitle: 'ДОПы, время и преподаватели', accent: const Color(0xFF9667E8), onTap: onDop),
                  _DashboardCard(icon: Icons.campaign_rounded, title: 'Объявления и оповещения', subtitle: 'Новости школы и важные сообщения', accent: const Color(0xFFE58B35), onTap: onAnnouncements),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 46, height: 46, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.offline_pin_rounded, color: Theme.of(context).colorScheme.primary, size: 25)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Работает и без интернета', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 5),
                      Text('Карта и встроенное расписание доступны офлайн. Для обновления ДОПов требуется доступ к школьному intranet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4, fontSize: 13)),
                    ])),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final Color foreground;
  const _HeroButton(this.text, this.icon, this.onTap, {required this.foreground});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(text),
    style: FilledButton.styleFrom(backgroundColor: foreground.withValues(alpha: .13), foregroundColor: foreground, side: BorderSide(color: foreground.withValues(alpha: .24))),
  );
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  const _DashboardCard({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: accent, size: 26)),
            const SizedBox(width: 14),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 5),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.3)),
            ])),
            const SizedBox(width: 6),
            Icon(Icons.arrow_outward_rounded, size: 18, color: colors.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _StartChoice {
  final int floor;
  final String? id;
  const _StartChoice({required this.floor, required this.id});
}

class _StartDialog extends StatefulWidget {
  final int floor;
  final String? id;
  const _StartDialog({required this.floor, required this.id});
  @override State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late int floor = widget.floor;
  late String choice = widget.id ?? '__entrance__';
  @override Widget build(BuildContext context) {
    final rooms = SchoolData.locations.where((r) => r.floor == floor).toList();
    final values = <String>['__entrance__', ...rooms.map((r) => r.id)];
    if (!values.contains(choice)) choice = '__entrance__';
    return AlertDialog(
      title: const Text('Начало маршрута'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<int>(segments: const [ButtonSegment(value:1,label:Text('1 этаж')),ButtonSegment(value:2,label:Text('2 этаж')),ButtonSegment(value:3,label:Text('3 этаж'))], selected:{floor}, onSelectionChanged:(v){setState((){floor=v.first;choice='__entrance__';});}),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(initialValue: choice, isExpanded: true, decoration: const InputDecoration(labelText:'Точка старта'), items: [const DropdownMenuItem(value:'__entrance__',child:Text('Главный вход')), ...rooms.map((r)=>DropdownMenuItem(value:r.id,child:Text(SchoolData.isPlace(r) ? SchoolData.title(r) : '${r.id} — ${r.name}')))], onChanged:(v)=>setState(()=>choice=v??'__entrance__')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(context,_StartChoice(floor:floor,id:choice=='__entrance__'?null:choice)),child:const Text('Сохранить'))],
    );
  }
}
class MapPage extends StatefulWidget {
  final String? initialRoom; final VoidCallback onMenu;
  const MapPage({super.key,this.initialRoom,required this.onMenu});
  @override State<MapPage> createState()=>_MapPageState();
}
class _MapPageState extends State<MapPage>{
  int floor=1; String query=''; String? selected; int startFloor=1; String? startId; final search=TextEditingController();
  @override void initState(){super.initState();selected=widget.initialRoom;if(selected!=null)floor=SchoolData.room(selected!).floor;_load();}
  Future<void> _load()async{final p=await SharedPreferences.getInstance();startFloor=p.getInt('map_start_floor')??1;startId=p.getString('map_start_location');if(mounted)setState((){});}
  @override void dispose(){search.dispose();super.dispose();}
  List<RoomInfo> get rooms => SchoolData.locationsOnFloor(floor).where((r) => query.isEmpty || r.id.toLowerCase().contains(query.toLowerCase()) || SchoolData.title(r).toLowerCase().contains(query.toLowerCase())).toList();
  Future<void> _start() async {
    final choice = await showDialog<_StartChoice>(
      context: context,
      builder: (_) => _StartDialog(floor: startFloor, id: startId),
    );
    if (choice == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    await prefs.setInt('map_start_floor', choice.floor);
    if (choice.id == null) {
      await prefs.remove('map_start_location');
    } else {
      await prefs.setString('map_start_location', choice.id!);
    }

    if (!mounted) return;
    setState(() {
      startFloor = choice.floor;
      startId = choice.id;
    });
  }
  void _open(RoomInfo room) {
    setState(() => selected = room.id);
    final route = RouteEngine.build(
      room.id,
      startFloor: startFloor,
      startLocationId: startId,
    );
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Маршрут для этой точки недоступен.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePage(room: room, route: route),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wideScreen = MediaQuery.sizeOf(context).width >= 900;
    Widget locationsPanel() => Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .8))),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: scheme.surfaceContainerHigh,
            child: ListTile(
              leading: Icon(Icons.my_location_rounded, color: scheme.primary),
              title: const Text('Откуда идём?', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(startId == null ? 'Главный вход' : SchoolData.title(SchoolData.room(startId!))),
              trailing: const Icon(Icons.tune_rounded),
              onTap: _start,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 17, 5, 9),
            child: Row(children: [
              Expanded(child: Text('Этаж $floor', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              Text('${rooms.length} мест', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.search_off_rounded, size: 34, color: scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                const Text('Ничего не найдено', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Попробуй другой номер или название.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ]),
            )
          else
            ...rooms.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Card(
                color: selected == r.id ? scheme.primaryContainer.withValues(alpha: .55) : scheme.surfaceContainer,
                child: ListTile(
                  dense: true,
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)), child: Icon(SchoolData.isPlace(r) ? Icons.place_rounded : Icons.meeting_room_rounded, color: scheme.primary)),
                  title: Text(SchoolData.title(r), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  subtitle: Text(SchoolData.isPlace(r) ? 'Специальное место' : 'Кабинет ${r.id}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  onTap: () => _open(r),
                ),
              ),
            )),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Карта школы'),
        actions: [
          IconButton(onPressed: _start, tooltip: 'Начало маршрута', icon: const Icon(Icons.my_location_rounded)),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenMapPage(floor: floor, selectedRoom: selected, routeRoom: null, startFloor: startFloor, startLocationId: startId))), tooltip: 'Полноэкранная карта', icon: const Icon(Icons.fullscreen_rounded)),
          IconButton(onPressed: () => setState(() { query = ''; search.clear(); }), tooltip: 'Очистить поиск', icon: const Icon(Icons.clear_all_rounded)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                Expanded(child: TextField(controller: search, onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Кабинет, бассейн, библиотека…'))),
                const SizedBox(width: 10),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
                  selected: {floor},
                  onSelectionChanged: (v) => setState(() => floor = v.first),
                ),
              ]),
            ),
            Expanded(
              child: wideScreen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(children: [
                        Expanded(flex: 3, child: _MapImage(floor: floor, selected: selected)),
                        const SizedBox(width: 14),
                        SizedBox(width: 350, child: locationsPanel()),
                      ]),
                    )
                  : Column(children: [
                      SizedBox(height: math.min(320.0, constraints.maxHeight * .40), child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: _MapImage(floor: floor, selected: selected))),
                      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: locationsPanel())),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

}
class _MapImage extends StatelessWidget{final int floor;final String? selected;const _MapImage({required this.floor,required this.selected});@override Widget build(BuildContext context)=>Card(clipBehavior:Clip.antiAlias,child:InteractiveViewer(minScale:.7,maxScale:4,child:AspectRatio(aspectRatio:7016/4960,child:Stack(children:[Positioned.fill(child:Image.asset('assets/maps/floor$floor.webp',fit:BoxFit.contain)),if(selected!=null)Positioned.fill(child:CustomPaint(painter:_PointPainter(SchoolData.point(SchoolData.room(selected!)),Theme.of(context).colorScheme.primary)))]))));}
class _PointPainter extends CustomPainter{final Offset p;final Color color;_PointPainter(this.p,this.color);@override void paint(Canvas c,Size s){final o=Offset(p.dx*s.width,p.dy*s.height);c.drawCircle(o,9,Paint()..color=color);c.drawCircle(o,17,Paint()..color=color.withValues(alpha:.22));}@override bool shouldRepaint(covariant _PointPainter o)=>o.p!=p||o.color!=color;}
class _MathByDayDialog extends StatefulWidget {
  final String className;
  const _MathByDayDialog({required this.className});
  @override State<_MathByDayDialog> createState() => _MathByDayDialogState();
}
class _MathByDayDialogState extends State<_MathByDayDialog> {
  static const days = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];
  static const subjects = ['', 'Алгебра', 'Геометрия', 'Вероятность и статистика'];
  final selected = <String, String>{};
  @override void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        for (var d = 1; d <= 6; d++) {
          for (var slot = 0; slot < 6; slot++) {
            selected['$d|$slot'] = p.getString(_studentScopedPreferenceKey(p, 'math_subject_${widget.className}_${d}_$slot')) ?? '';
          }
        }
      });
    });
  }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Раздельная математика'),
    content: SizedBox(width: MediaQuery.sizeOf(context).width * .82, child: ListView(shrinkWrap: true, children: [
      const Text('Настрой названия математических уроков отдельно для каждого дня. Если уроков несколько, они идут по времени: первый, второй и далее.'),
      const SizedBox(height: 10),
      for (var d = 1; d <= 6; d++) ...[
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(days[d - 1], style: const TextStyle(fontWeight: FontWeight.w800))),
        for (var slot = 0; slot < SchoolScheduleCatalog.mathLessonCount(widget.className, d); slot++)
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Математика — урок ${slot + 1}', isDense: true),
            initialValue: subjects.contains(selected['$d|$slot'] ?? '') ? selected['$d|$slot'] : '',
            items: subjects.map((x) => DropdownMenuItem(value: x, child: Text(x.isEmpty ? 'Не переименовывать' : x))).toList(),
            onChanged: (v) => setState(() => selected['$d|$slot'] = v ?? ''),
          ),
      ],
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () async {
        final p = await SharedPreferences.getInstance();
        for (var d = 1; d <= 6; d++) {
          for (var slot = 0; slot < 6; slot++) {
            await p.setString(_studentScopedPreferenceKey(p, 'math_subject_${widget.className}_${d}_$slot'), selected['$d|$slot'] ?? '');
          }
        }
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('Сохранить')),
    ],
  );
}

class SchedulePage extends StatefulWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotes;
  const SchedulePage({super.key, required this.onMenu, required this.onNotes});
  @override State<SchedulePage> createState() => _SchedulePageState();
}
class _SchedulePageState extends State<SchedulePage> {
  int day = DateTime.now().weekday > 6 ? 1 : DateTime.now().weekday;
  List<ScheduleEntry> entries = []; String classId = ''; bool loading = true;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  @override void initState() { super.initState(); _load(); _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _now = DateTime.now()); }); }
  @override void dispose() { _clockTimer?.cancel(); super.dispose(); }
  String? _breakCountdown(List<ScheduleEntry> dayEntries) => SchoolBellCountdown.describe(
    selectedDay: day,
    now: _now,
    lessons: dayEntries.map((entry) => (time: entry.time, subject: entry.subject)).toList(),
  );
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance(); await SchoolScheduleCatalog.load();
    try { await SchoolScheduleCatalog.refreshOnline(); } catch (_) {}
    classId = p.getString('student_class_name') ?? '';
    final groups = <String,int>{};
    if (classId.isNotEmpty) {
      for (final s in SchoolScheduleCatalog.splitSubjects(classId)) {
        groups[s] = p.getInt(_studentScopedPreferenceKey(p, 'student_group_${classId}_$s')) ?? 1;
      }
      final mathNames = <int, List<String>>{};
      for (var d = 1; d <= 6; d++) {
        final dayNames = <String>[];
        for (var slot = 0; slot < 6; slot++) {
          dayNames.add(p.getString(_studentScopedPreferenceKey(p, 'math_subject_${classId}_${d}_$slot')) ?? '');
        }
        mathNames[d] = dayNames;
      }
      entries = SchoolScheduleCatalog.buildPersonal(classId, groups, mathNamesByDay: mathNames);
    } else { entries = []; }
    if (mounted) setState(() => loading = false);
    try { await LocalNotificationService().scheduleUpcomingLessons(entries: entries.map((e) => (id:e.id,day:e.day,time:e.time,subject:e.subject,room:e.room)).toList()); } catch (_) {}
    if (classId.isEmpty && mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _chooseClass(required: true));
  }
  Future<void> _chooseClass({bool required = false}) async {
    final selected = await showDialog<String>(context: context, barrierDismissible: !required, builder: (_) => _StudentClassDialog(requiredChoice: required));
    if (selected == null || selected.isEmpty) return;
    final p = await SharedPreferences.getInstance(); await p.setString('student_class_name', selected); await p.setString('student_class_id', selected);
    if (!mounted) return; await showStudentGroupSelection(context, selected); await _load();
  }
  void _route(ScheduleEntry e) {
    if (e.room.isEmpty) return;
    final destination = SchoolData.tryRoom(e.room);
    if (destination == null) return;
    final sameDay = entries.where((x) => x.day == e.day).toList()..sort((a, b) => a.time.compareTo(b.time));
    final currentIndex = sameDay.indexWhere((x) => x.id == e.id);
    RoomInfo? previousRoom;
    if (currentIndex > 0) {
      for (var i = currentIndex - 1; i >= 0; i--) {
        final candidate = sameDay[i];
        if (candidate.room.isEmpty) continue;
        previousRoom = SchoolData.tryRoom(candidate.room);
        if (previousRoom != null) break;
      }
    }
    final route = RouteEngine.build(destination.id,
      startFloor: previousRoom?.floor ?? 1,
      startLocationId: previousRoom?.id,
    );
    if (route != null) Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePage(room: destination, route: route)));
  }
  @override
  Widget build(BuildContext context) {
    final list = entries.where((e) => e.day == day).toList()..sort((a, b) => a.time.compareTo(b.time));
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final splitSubjects = SchoolScheduleCatalog.splitSubjects(classId);
    final breakCountdown = _breakCountdown(list);
    const dayNames = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Расписание'),
        actions: [
          if (width >= 460)
            IconButton(
              tooltip: 'Мои заметки',
              onPressed: widget.onNotes,
              icon: const Icon(Icons.note_alt_outlined),
            ),
          IconButton(tooltip: 'Выбрать класс', onPressed: () => _chooseClass(), icon: const Icon(Icons.school_rounded)),
          if (classId.isNotEmpty) ...[
            IconButton(tooltip: 'Группы по предметам', onPressed: () async { await showStudentGroupSelection(context, classId); await _load(); }, icon: const Icon(Icons.groups_rounded)),
            IconButton(tooltip: 'Раздельная математика по дням', onPressed: () async { await showDialog<void>(context: context, builder: (_) => _MathByDayDialog(className: classId)); await _load(); }, icon: const Icon(Icons.functions_rounded)),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Padding(
            padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.calendar_month_rounded, color: scheme.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(classId.isEmpty ? 'Твоё расписание' : 'Класс $classId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                      const SizedBox(height: 4),
                      Text(
                        classId.isEmpty ? 'Выбери класс, чтобы загрузить уроки' : '${dayNames[day]} • ${list.length} ${list.length == 1 ? 'урок' : (list.length >= 2 && list.length <= 4 ? 'урока' : 'уроков')}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ])),
                    if (classId.isNotEmpty)
                      IconButton(onPressed: () async { await showStudentGroupSelection(context, classId); await _load(); }, tooltip: 'Настроить группы', icon: const Icon(Icons.tune_rounded)),
                  ]),
                ),
                const SizedBox(height: 16),
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
                if (!loading && classId.isNotEmpty && breakCountdown != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.tertiary.withValues(alpha: .25)),
                    ),
                    child: Row(children: [
                      Icon(Icons.hourglass_bottom_rounded, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 10),
                      Expanded(child: Text(breakCountdown, style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w800, fontSize: 13))),
                    ]),
                  ),
                ],
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : classId.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.school_outlined, size: 48, color: scheme.primary),
                                  const SizedBox(height: 12),
                                  const Text('Сначала выбери свой класс', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                                  const SizedBox(height: 6),
                                  Text('Приложение покажет предметы, группы и кабинеты именно для него.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(onPressed: () => _chooseClass(required: true), icon: const Icon(Icons.school_rounded), label: const Text('Выбрать класс')),
                                ]),
                              ),
                            )
                          : list.isEmpty
                              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.event_available_rounded, size: 44, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 10),
                                  const Text('В этот день уроков нет', style: TextStyle(fontWeight: FontWeight.w800)),
                                ]))
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  itemCount: list.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                                  itemBuilder: (context, index) {
                                    final e = list[index];
                                    final room = e.room.isEmpty ? null : SchoolData.tryRoom(e.room);
                                    final times = RegExp(r'\d{1,2}:\d{2}').allMatches(e.time).map((m) => m.group(0)!).toList();
                                    final startTime = times.isNotEmpty ? times.first : e.time;
                                    final endTime = times.length > 1 ? times[1] : '';
                                    return Card(
                                      clipBehavior: Clip.antiAlias,
                                      child: Padding(
                                        padding: const EdgeInsets.all(13),
                                        child: Row(children: [
                                          Container(
                                            width: 76,
                                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                                            decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)),
                                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                                              Text(startTime, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 14)),
                                              if (endTime.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text(endTime, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                                              ],
                                            ]),
                                          ),
                                          const SizedBox(width: 13),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(e.subject, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                            const SizedBox(height: 6),
                                            Wrap(spacing: 8, runSpacing: 5, children: [
                                              if (e.room.isNotEmpty)
                                                _ScheduleTag(icon: Icons.meeting_room_outlined, label: 'Каб. ${e.room}'),
                                              if (e.teacher.isNotEmpty)
                                                _ScheduleTag(icon: Icons.person_outline_rounded, label: e.teacher),
                                              if (splitSubjects.contains(e.subject) && e.group > 0)
                                                _ScheduleTag(icon: Icons.groups_2_outlined, label: 'Группа ${e.group}'),
                                            ]),
                                          ])),
                                          IconButton(
                                            onPressed: room == null ? null : () => _route(e),
                                            tooltip: room == null ? 'Маршрут для кабинета недоступен' : 'Как пройти',
                                            icon: const Icon(Icons.directions_rounded),
                                          ),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
class _ScheduleTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ScheduleTag({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class RoutePage extends StatelessWidget {
  final RoomInfo room;
  final RouteResult route;
  const RoutePage({super.key, required this.room, required this.route});

  @override
  Widget build(BuildContext context) {
    final steps = RouteEngine.instructions(route);
    final floors = route.nodes.map((n) => n.floor).toSet().toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    final origin = route.startLocationId == null ? 'Главный вход' : SchoolData.title(SchoolData.room(route.startLocationId!));
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(title: const Text('Маршрут')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050),
          child: ListView(
            padding: EdgeInsets.fromLTRB(width < 600 ? 12 : 24, 12, width < 600 ? 12 : 24, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerHigh]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.directions_rounded, color: scheme.primary, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(SchoolData.title(room), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                    const SizedBox(height: 5),
                    Text('Откуда: $origin', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text('Этаж назначения: ${room.floor} • ${floors.length} ${floors.length == 1 ? 'этаж' : 'этажа'} на маршруте', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ])),
                  Icon(Icons.flag_rounded, color: scheme.primary, size: 24),
                ]),
              ),
              const SizedBox(height: 22),
              Text('План маршрута', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final floor in floors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
                        child: Row(children: [
                          Tooltip(message: 'Этаж, по которому проходит маршрут', child: Icon(Icons.layers_rounded, color: scheme.primary)),
                          const SizedBox(width: 9),
                          Expanded(child: Text('$floor этаж', style: const TextStyle(fontWeight: FontWeight.w900))),
                          if (floor == room.floor)
                            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text('Назначение', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 11))),
                        ]),
                      ),
                      AspectRatio(
                        aspectRatio: 7016 / 4960,
                        child: Stack(children: [
                          Positioned.fill(child: Image.asset('assets/maps/floor$floor.webp', fit: BoxFit.contain)),
                          Positioned.fill(child: CustomPaint(painter: _RoutePainter(route.nodes, floor, const Color(0xFFFF2D95)))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Пошаговые инструкции', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              for (final item in steps.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 42, height: 42, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)), child: Center(child: Text('${item.key + 1}', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 15)))),
                        const SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item.value.text, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35)),
                          const SizedBox(height: 5),
                          Text('${item.value.floor} этаж', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                        ])),
                        Icon(item.value.icon, color: scheme.primary),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<RouteNode> nodes;
  final int floor;
  final Color color;
  _RoutePainter(this.nodes, this.floor, this.color);

  @override
  void paint(Canvas c, Size s) {
    if (nodes.length < 2) return;
    final path = Path();
    var drawing = false;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.floor != floor) {
        drawing = false;
        continue;
      }
      final point = Offset(node.point.dx * s.width, node.point.dy * s.height);
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        final previous = nodes[i - 1];
        // Never bridge a floor transition: that would draw a false straight
        // line between two physically separate staircases on this floor.
        if (previous.floor == floor) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
        }
      }
    }
    // White halo keeps the route readable over every department/map color.
    c.drawPath(path, Paint()
      ..color = Colors.white.withValues(alpha: .95)
      ..strokeWidth = 11
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    c.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.nodes != nodes || old.floor != floor || old.color != color;
}
class FullscreenMapPage extends StatefulWidget {
  final int floor;
  final String? selectedRoom;
  final String? routeRoom;
  final int startFloor;
  final String? startLocationId;

  const FullscreenMapPage({
    super.key,
    required this.floor,
    required this.selectedRoom,
    required this.routeRoom,
    required this.startFloor,
    required this.startLocationId,
  });

  @override
  State<FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<FullscreenMapPage> {
  late int floor = widget.floor;
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _changeZoom(double delta, Size size) {
    final current = _zoom.value.getMaxScaleOnAxis();
    final next = (current + delta).clamp(.6, 6.0).toDouble();
    _zoom.value = Matrix4.identity()
      ..translateByDouble(
        size.width * (1 - next) / 2,
        size.height * (1 - next) / 2,
        0,
        1,
      )
      ..scaleByDouble(next, next, next, 1);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedRoom == null ? null : SchoolData.tryRoom(widget.selectedRoom!);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('$floor этаж • полноэкранная карта'),
        actions: [
          if (selected != null && selected.floor == floor)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(SchoolData.title(selected), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 этаж')),
                      ButtonSegment(value: 2, label: Text('2 этаж')),
                      ButtonSegment(value: 3, label: Text('3 этаж')),
                    ],
                    selected: {floor},
                    onSelectionChanged: (value) {
                      setState(() {
                        floor = value.first;
                        _zoom.value = Matrix4.identity();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Сбросить масштаб',
                  onPressed: () => setState(() => _zoom.value = Matrix4.identity()),
                  icon: const Icon(Icons.fit_screen_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: .6,
                      maxScale: 6,
                      boundaryMargin: const EdgeInsets.all(100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: AspectRatio(
                            aspectRatio: 7016 / 4960,
                            child: Stack(
                              children: [
                                Positioned.fill(child: Image.asset('assets/maps/floor$floor.webp', fit: BoxFit.contain)),
                                if (selected != null && selected.floor == floor)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _PointPainter(SchoolData.point(selected), scheme.primary),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_in',
                          tooltip: 'Увеличить',
                          onPressed: () => _changeZoom(.35, Size(constraints.maxWidth, constraints.maxHeight)),
                          child: const Icon(Icons.add_rounded),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'map_zoom_out',
                          tooltip: 'Уменьшить',
                          onPressed: () => _changeZoom(-.35, Size(constraints.maxWidth, constraints.maxHeight)),
                          child: const Icon(Icons.remove_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleEditor extends StatefulWidget {
  final ScheduleEntry? initial;
  final int defaultDay;
  const ScheduleEditor({super.key, this.initial, this.defaultDay = 1});
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late int day;
  late TextEditingController time;
  late TextEditingController subject;
  late TextEditingController room;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    day = e?.day ?? widget.defaultDay;
    time = TextEditingController(text: e?.time ?? '');
    subject = TextEditingController(text: e?.subject ?? '');
    room = TextEditingController(text: e?.room ?? '');
  }

  @override
  void dispose() {
    time.dispose();
    subject.dispose();
    room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(560.0, size.width - 32).toDouble(),
          maxHeight: math.min(620.0, size.height - 32).toDouble(),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.initial == null ? 'Добавить урок' : 'Изменить урок', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
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
                onChanged: (v) => setState(() => day = v ?? widget.defaultDay),
              ),
              const SizedBox(height: 10),
              TextField(controller: time, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Время', hintText: '08:30')),
              const SizedBox(height: 10),
              TextField(controller: subject, decoration: const InputDecoration(labelText: 'Предмет')),
              const SizedBox(height: 10),
              TextField(controller: room, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Кабинет', hintText: '311')),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (subject.text.trim().isEmpty) return;
                      Navigator.pop(
                        context,
                        ScheduleEntry(
                          id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                          day: day,
                          time: time.text.trim(),
                          subject: subject.text.trim(),
                          room: room.text.trim(),
                        ),
                      );
                    },
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final AppThemeType theme;
  final String userName;
  final ValueChanged<AppThemeType> onThemeChanged;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onMenu;
  const SettingsPage({super.key, required this.theme, required this.userName, required this.onThemeChanged, required this.onNameChanged, required this.onMenu});

  Future<void> _openAdmin(BuildContext context) async {
    final account = await showDialog<AdminAccount>(context: context, builder: (_) => const AdminLoginDialog());
    if (account == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPanelPage(account: account)));
  }

  Future<void> _serverAdminLogin(BuildContext context, String baseUrl) async {
    final login = TextEditingController();
    final password = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Технический вход администратора'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Только для первого запуска и восстановления доступа. Для обычной работы используй школьный SSO.'),
          const SizedBox(height: 12),
          TextField(controller: login, autofocus: true, decoration: const InputDecoration(labelText: 'Логин администратора')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль администратора')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () {
            if (login.text.trim().isEmpty || password.text.isEmpty) return;
            Navigator.pop(dialogContext, {'username': login.text.trim(), 'password': password.text});
          }, child: const Text('Войти')),
        ],
      ),
    );
    login.dispose(); password.dispose();
    if (result == null) return;
    try {
      await SchoolAccountService().signInAsServerAdmin(
        baseUrl, username: result['username']!, password: result['password']!,
      );
      unawaited(desktop_polling.startDesktopNotificationPolling());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Технический вход выполнен.')));
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
      }
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', '')), duration: const Duration(seconds: 6)),
      );
    }
  }

  Future<void> _schoolAccount(BuildContext context) async {
    final service = SchoolAccountService();
    final current = await service.currentUser();
    if (!context.mounted) return;
    if (current != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Школьная учётная запись'),
          content: Text('Вход выполнен: ${current['display_name'] ?? current['username'] ?? 'учётная запись'}\nРоль: ${current['role'] ?? 'не указана'}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Закрыть')),
            OutlinedButton(onPressed: () => Navigator.pop(dialogContext, 'signout'), child: const Text('Выйти')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'portal'),
              child: Text(current['role'] == 'student' ? 'Мои оповещения' : 'Открыть кабинет'),
            ),
          ],
        ),
      );
      if (action == 'signout') {
        await service.signOut();
        await desktop_polling.stopDesktopNotificationPolling();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы вышли из школьной учётной записи.')));
      } else if (action == 'portal' && context.mounted) {
        if (current['role'] == 'student') {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
        } else {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
        }
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('navigator_api_enabled') ?? false;
    final baseUrl = (prefs.getString('navigator_api_url') ?? '').trim();
    if (!enabled || baseUrl.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала настрой адрес API в «Кабинет школы → Сервер».')));
      return;
    }
    final loginMethod = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Вход в Поколение'),
        content: const Text('Выбери школьный вход. Технический вход нужен только администратору для первоначальной настройки или восстановления доступа.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, 'cancel'), child: const Text('Отмена')),
          OutlinedButton(onPressed: () => Navigator.pop(dialogContext, 'admin'), child: const Text('Технический вход')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, 'sso'), child: const Text('Школьный SSO')),
        ],
      ),
    );
    if (!context.mounted || loginMethod == null || loginMethod == 'cancel') return;
    if (loginMethod == 'admin') {
      await _serverAdminLogin(context, baseUrl);
      return;
    }
    try {
      final result = await service.signInWithSchoolAccount(baseUrl);
      final user = Map<String, dynamic>.from(result['user'] as Map);
      unawaited(desktop_polling.startDesktopNotificationPolling());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Вход выполнен: ${user['display_name'] ?? user['username'] ?? 'учётная запись'}.${result['push_registered'] == true ? ' Уведомления подключены.' : ' Push-уведомления пока не настроены.'}'),
          duration: const Duration(seconds: 5),
        ));
        if (user['role'] == 'student') {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
        } else {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
        }
      }
    } catch (error) {
      if (context.mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
      }
    }
  }

  Future<void> _openSchoolCabinet(BuildContext context) async {
    final service = SchoolAccountService();
    final current = await service.currentUser();
    if (!context.mounted) return;
    if (current != null) {
      if (current['role'] == 'student') {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolAnnouncementsPage()));
      } else {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SchoolPortalPage()));
      }
      return;
    }
    await _schoolAccount(context);
  }

  Future<void> _editClass(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        final classId = (account is Map ? account['class_id'] : null)?.toString().trim() ?? '';
        if (account is Map && account['role'] == 'student' && classId.isNotEmpty) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Класс поступает из школьной учётной записи. Если он неверный, обратись к школьному администратору.')),
          );
          return;
        }
      } catch (_) {}
    }
    await SchoolScheduleCatalog.load();
    final result = await showDialog<String>(context: context, builder: (_) => const _StudentClassDialog());
    if (!context.mounted || result == null || result.isEmpty) return;
    await prefs.setString('student_class_name', result);
    await prefs.setString('student_class_id', result);
    if (!context.mounted) return;
    await showStudentGroupSelection(context, result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Профиль расписания: $result')),
      );
    }
  }

  @override Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)), title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w900))), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
      const Text('Профиль', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.person_rounded, color: c.primary), title: const Text('Имя'), subtitle: Text(userName.isEmpty ? 'Не задано' : userName), trailing: const Icon(Icons.edit_rounded), onTap: () => _editName(context))),
      Card(child: ListTile(leading: Icon(Icons.school_rounded, color: c.primary), title: const Text('Мой класс'), subtitle: const Text('Класс используется как источник базового расписания'), trailing: const Icon(Icons.edit_rounded), onTap: () => _editClass(context))),
      Card(child: ListTile(leading: Icon(Icons.groups_rounded, color: c.primary), title: const Text('Группы по предметам'), subtitle: const Text('Например: английский — 1, математика — 2'), trailing: const Icon(Icons.tune_rounded), onTap: () async { final p = await SharedPreferences.getInstance(); final cls = p.getString('student_class_name') ?? ''; if (cls.isNotEmpty && context.mounted) await showStudentGroupSelection(context, cls); })),
      const SizedBox(height: 18), const Text('Оформление', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.palette_rounded, color: c.primary), title: const Text('Цветовая тема'), subtitle: Text(AppPalette.name(theme)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _pickTheme(context))),
      const SizedBox(height: 18), const Text('Для сотрудников', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.verified_user_rounded, color: c.primary), title: const Text('Школьная учётная запись'), subtitle: const Text('Безопасный вход через школьный SSO и регистрация уведомлений'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _schoolAccount(context))),
      Card(child: ListTile(leading: Icon(Icons.admin_panel_settings_rounded, color: c.primary), title: const Text('Кабинет школы'), subtitle: const Text('Сотрудникам — управление по роли; ученикам — школьные оповещения'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openSchoolCabinet(context))),
      Card(child: ListTile(leading: Icon(Icons.cloud_sync_rounded, color: c.primary), title: const Text('Настройки подключения'), subtitle: const Text('Адрес API, включение онлайн-режима и проверка соединения'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openAdmin(context))),
      const SizedBox(height: 18), const Text('Приложение', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: Column(children: [ListTile(leading: Icon(Icons.info_outline_rounded, color: c.primary), title: const Text('О приложении'), subtitle: const Text('Приложение школы «Поколение»'), onTap: () => showAboutDialog(context: context, applicationName: 'Поколение', applicationLegalese: 'Приложение школы «Поколение»')), const Divider(height: 1), ListTile(leading: Icon(Icons.restore_rounded, color: c.primary), title: const Text('Сбросить тему'), onTap: () => onThemeChanged(AppThemeType.turquoise))])),
    ]))));
  }

  Future<void> _editName(BuildContext context) async {
    final result = await showDialog<String>(context: context, builder: (_) => _EditValueDialog(title: 'Изменить имя', label: 'Имя', hint: 'Как к тебе обращаться?', initialValue: userName));
    if (!context.mounted || result == null || result.isEmpty) return;
    onNameChanged(result);
  }
  void _pickTheme(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [const Text('Цветовая тема', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 12), _ThemeTile(title: 'Жёлтая', description: 'Жёлтый → бежевый', colors: AppPalette.yellow, selected: theme == AppThemeType.yellow, onTap: () { onThemeChanged(AppThemeType.yellow); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Бирюзовая', description: 'Насыщенный бирюзовый → светло-зелёный', colors: AppPalette.turquoise, selected: theme == AppThemeType.turquoise, onTap: () { onThemeChanged(AppThemeType.turquoise); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Тёмно-синяя', description: 'Тёмно-синий → синий', colors: AppPalette.darkBlue, selected: theme == AppThemeType.darkBlue, onTap: () { onThemeChanged(AppThemeType.darkBlue); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Фиолетовая', description: 'Фиолетовый → сиреневый', colors: AppPalette.violet, selected: theme == AppThemeType.violet, onTap: () { onThemeChanged(AppThemeType.violet); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Коралловая', description: 'Коралловый → тёплый персиковый', colors: AppPalette.coral, selected: theme == AppThemeType.coral, onTap: () { onThemeChanged(AppThemeType.coral); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Зелёная', description: 'Изумрудный → мятный', colors: AppPalette.green, selected: theme == AppThemeType.green, onTap: () { onThemeChanged(AppThemeType.green); Navigator.pop(sheetContext); })])));
}

class _EditValueDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String initialValue;
  const _EditValueDialog({required this.title, required this.label, required this.hint, required this.initialValue});

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, autofocus: true, textInputAction: TextInputAction.done, decoration: InputDecoration(labelText: widget.label, hintText: widget.hint), onSubmitted: (_) => Navigator.pop(context, controller.text.trim())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить')),
    ],
  );
}

class _ThemeTile extends StatelessWidget { final String title; final String description; final List<Color> colors; final bool selected; final VoidCallback onTap; const _ThemeTile({required this.title, required this.description, required this.colors, required this.selected, required this.onTap}); @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Container(width: 58, height: 58, decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(16))), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(description, style: const TextStyle(fontSize: 12))])), Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? colors.first : null)])))); }
