import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_panel.dart';
import 'door_points.dart';
import 'corridor_roads.dart';
import 'local_notification_service.dart';
import 'security_service.dart';
import 'supplements_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try { await LocalNotificationService().initialize(); } catch (_) {}
  runApp(const NavigatorApp());
}

enum AppThemeType { yellow, turquoise, darkBlue }

class AppPalette {
  static const yellow = [Color(0xFFFFC94D), Color(0xFFEADCC7)];
  static const turquoise = [Color(0xFF00BFAE), Color(0xFF79E2A0)];
  static const darkBlue = [Color(0xFF0B1633), Color(0xFF173A78), Color(0xFF3657B8)];

  static List<Color> gradient(AppThemeType type) => switch (type) {
    AppThemeType.yellow => yellow,
    AppThemeType.turquoise => turquoise,
    AppThemeType.darkBlue => darkBlue,
  };

  static String name(AppThemeType type) => switch (type) {
    AppThemeType.yellow => 'Жёлтая',
    AppThemeType.turquoise => 'Бирюзовая',
    AppThemeType.darkBlue => 'Тёмно-синяя',
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
    RoomInfo('place_bio_lab', 1, 'Лаборатория бактериальных экспериментов', Offset(.115, .455), 'f1_left'),
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
    final raw = await rootBundle.loadString('assets/data/school_schedule_2026-10-05.json');
    _data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
  static List<String> grades() => List<String>.from((_data?['class_order'] as Map? ?? {}).keys);
  static List<String> classesForGrade(String grade) => List<String>.from(((_data?['class_order'] as Map?)?[grade] as List?) ?? const []);
  static List<Map<String, dynamic>> variants(String className) {
    final raw = ((_data?['classes'] as Map?)?[className] as Map?)?['variants'];
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

  static List<ScheduleEntry> buildPersonal(
    String className,
    Map<String, int> selected,
  ) {
    final all = variants(className);
    final result = <ScheduleEntry>[];
    final seen = <String>{};
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
      final room = '${e['room'] ?? ''}'.trim();
      final storedTeacher = '${e['teacher'] ?? ''}'.trim();
      final teacher = storedTeacher.isNotEmpty
          ? storedTeacher
          : teacherFromSubject(rawSubject);
      final key = '$day|$time|$subject|$room|$teacher';
      if (!seen.add(key)) continue;
      result.add(ScheduleEntry(
        id: '${className}_${day}_${time}_${subject}_${group}'.replaceAll(
          RegExp(r'[^A-Za-zА-Яа-яЁё0-9_-]'), '_'),
        day: day, time: time, subject: subject, room: room,
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
Future<void> showStudentGroupSelection(BuildContext context, String className) async {
  await SchoolScheduleCatalog.load();
  final subjects = SchoolScheduleCatalog.splitSubjects(className).toList()..sort();
  if (subjects.isEmpty || !context.mounted) return;
  final prefs = await SharedPreferences.getInstance();
  final values = <String, int>{for (final s in subjects) s: prefs.getInt('student_group_${className}_$s') ?? 1};
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
    content: SizedBox(width: 560, child: ListView(shrinkWrap: true, children: widget.subjects.map((s) {
      final groups = (available[s] ?? <int>{1}).toList()..sort();
      return ListTile(title: Text(s), subtitle: const Text('Выбор сохраняется отдельно для предмета.'), trailing: SegmentedButton<int>(segments: groups.map((g) => ButtonSegment(value: g, label: Text('Группа $g'))).toList(), selected: {values[s] ?? groups.first}, onSelectionChanged: (v) => setState(() => values[s] = v.first)));
    }).toList())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () async { final p = await SharedPreferences.getInstance(); for (final e in values.entries) await p.setInt('student_group_${widget.className}_${e.key}', e.value); if (context.mounted) Navigator.pop(context); }, child: const Text('Сохранить')),
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
  static const double _snapPx = 25.0;

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
    final v = b - a;
    final len2 = v.dx * v.dx + v.dy * v.dy;
    if (len2 <= 1e-12) return a;
    final t = ((p.dx - a.dx) * v.dx + (p.dy - a.dy) * v.dy) / len2;
    final clamped = t.clamp(0.0, 1.0);
    return Offset(a.dx + v.dx * clamped, a.dy + v.dy * clamped);
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
    final destination = SchoolData.room(destinationId);
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
    for (final entry in _anchors.entries) {
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
      if (bestSegment < 0) continue;
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
        connect(a.id, b.id, (a.point - b.point).distance);
      }
    }

    // Connect every anchor to its own perpendicular projection on the road.
    for (final entry in anchorNode.entries) {
      final anchorId = entry.value;
      final roadId = anchorRoadNode[entry.key];
      if (roadId == null || anchorId == roadId) continue;
      final anchorPoint = nodes[anchorId]!.point;
      final roadPoint = nodes[roadId]!.point;
      connect(anchorId, roadId, (anchorPoint - roadPoint).distance);
    }

    // Vertical stair links. The closed turquoise stair is deliberately omitted from 2↔3.
    for (final chain in _verticalStairs()) {
      for (var i = 0; i + 1 < chain.length; i++) {
        final aId = anchorNode[chain[i]];
        final bId = anchorNode[chain[i + 1]];
        if (aId == null || bId == null) continue;
        final a = nodes[aId]!;
        final b = nodes[bId]!;
        connect(a.id, b.id, .28);
      }
    }

    // Main entrance is the source when no room is selected.
    final startRoom = startLocationId == null ? null : SchoolData.room(startLocationId);
    final effectiveStartFloor = startRoom?.floor ?? startFloor;
    final sourceAnchor = startRoom == null ? 'entry' : startRoom.id;
    final source = anchorNode[sourceAnchor];
    final target = anchorNode[destination.id];
    if (source == null || target == null) return null;

    if (startLocationId == destinationId) {
      final p = DoorPoints.of(destination.id, destination.point);
      return RouteResult([RouteNode('same_start', destination.floor, p, 'Точка назначения')], destination, 0, destination.floor, startLocationId);
    }

    final distance = <String, double>{source: 0};
    final previous = <String, String?>{source: null};
    final open = <_QueueItem>[_QueueItem(source, 0, 0)];

    double heuristic(String id) {
      final a = nodes[id];
      final b = nodes[target];
      if (a == null || b == null) return 0;
      return (a.point - b.point).distance + (a.floor - b.floor).abs() * .25;
    }

    while (open.isNotEmpty) {
      open.sort((a, b) => a.priority.compareTo(b.priority));
      final current = open.removeAt(0);
      final best = distance[current.id];
      if (best == null || current.g > best + 1e-9) continue;
      if (current.id == target) break;
      for (final edge in graph[current.id] ?? const <RouteEdge>[]) {
        final nextG = best + edge.cost;
        if (nextG < (distance[edge.b] ?? double.infinity)) {
          distance[edge.b] = nextG;
          previous[edge.b] = current.id;
          open.add(_QueueItem(edge.b, nextG, nextG + heuristic(edge.b)));
        }
      }
    }
    if (!distance.containsKey(target)) return null;

    final ids = <String>[];
    String? cursor = target;
    while (cursor != null) {
      ids.add(cursor);
      cursor = previous[cursor];
    }
    final path = ids.reversed.map((id) => nodes[id]!).toList();

    // Replace technical anchor nodes with readable door/start labels.
    if (startRoom != null) {
      path.insert(0, RouteNode('start_room_${startRoom.id}', startRoom.floor, DoorPoints.of(startRoom.id, startRoom.point), SchoolData.title(startRoom)));
    }
    if (startRoom == null) {
      path.insert(0, RouteNode('start_entry', effectiveStartFloor, DoorPoints.all['place_entrance']!, 'Главный вход'));
    }
    path.add(RouteNode('destination_door_${destination.id}', destination.floor, DoorPoints.of(destination.id, destination.point), SchoolData.title(destination)));

    return RouteResult(path, destination, distance[target]!, effectiveStartFloor, startLocationId);
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
    final path = result.nodes;
    if (path.isEmpty) return const [];
    final steps = <RouteStep>[];
    if (result.startLocationId == null) {
      steps.add(RouteStep(result.startFloor, 'Начните от главного входа и двигайтесь по коридору.', Icons.directions_walk_rounded));
    } else {
      steps.add(RouteStep(result.startFloor, 'Выйдите из ${SchoolData.title(SchoolData.room(result.startLocationId!))} через дверь в коридор.', Icons.exit_to_app_rounded));
    }
    for (var i = 1; i < path.length; i++) {
      final prev = path[i - 1];
      final cur = path[i];
      if (cur.floor != prev.floor) {
        steps.add(RouteStep(cur.floor, cur.floor > prev.floor
            ? 'Поднимитесь по лестнице на ${cur.floor} этаж.'
            : 'Спуститесь по лестнице на ${cur.floor} этаж.', Icons.stairs_rounded));
        continue;
      }
      if (cur.id.startsWith('destination_door_')) {
        steps.add(RouteStep(cur.floor, 'Подойдите к ${SchoolData.title(result.destination)} — вы на месте.', Icons.flag_rounded));
        continue;
      }
      if (i + 1 < path.length) {
        final next = path[i + 1];
        final v1 = cur.point - prev.point;
        final v2 = next.point - cur.point;
        if (v1.distance > .01 && v2.distance > .01) {
          final cross = v1.dx * v2.dy - v1.dy * v2.dx;
          final dot = v1.dx * v2.dx + v1.dy * v2.dy;
          if (dot < 0.0 || cross.abs() > .015) {
            final turn = cross > 0 ? 'Поверните направо' : 'Поверните налево';
            steps.add(RouteStep(cur.floor, '$turn и продолжайте по коридору.', cross > 0 ? Icons.turn_right_rounded : Icons.turn_left_rounded));
          }
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

class NavigatorApp extends StatefulWidget {
  const NavigatorApp({super.key});
  @override State<NavigatorApp> createState()=>_NavigatorAppState();
}
class _NavigatorAppState extends State<NavigatorApp>{
  AppThemeType theme=AppThemeType.turquoise; String userName=''; bool ready=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{final p=await SharedPreferences.getInstance();await SchoolScheduleCatalog.load();userName=p.getString('user_name')??'';final t=p.getString('theme');theme=AppThemeType.values.firstWhere((x)=>x.name==t,orElse:()=>AppThemeType.turquoise);if(mounted)setState(()=>ready=true);}
  Future<void> setName(String v)async{v=v.trim();if(v.isEmpty)return;final p=await SharedPreferences.getInstance();await p.setString('user_name',v);if(mounted)setState(()=>userName=v);}
  Future<void> setTheme(AppThemeType v)async{final p=await SharedPreferences.getInstance();await p.setString('theme',v.name);if(mounted)setState(()=>theme=v);}
  @override Widget build(BuildContext context){if(!ready)return MaterialApp(debugShowCheckedModeBanner:false,home:Scaffold(body:Center(child:CircularProgressIndicator(color:AppPalette.gradient(theme).first))));return MaterialApp(debugShowCheckedModeBanner:false,title:'Navigator — школа «Поколение»',theme:_theme(theme),home:AppShell(userName:userName,theme:theme,onThemeChanged:setTheme,onNameChanged:setName));}
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
  @override
  Widget build(BuildContext context) {
    final menu = () => key.currentState?.openDrawer();
    final pages = <Widget>[
      HomePage(userName: widget.userName, theme: widget.theme, onMenu: menu, onMap: () => go(1), onSchedule: () => go(2), onDop: () => go(3)),
      MapPage(initialRoom: selectedRoom, onMenu: menu),
      SchedulePage(onMenu: menu),
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

  Widget _drawer(BuildContext context){final c=Theme.of(context).colorScheme;final items=[(0,Icons.home_rounded,'Главное меню','Обзор'),(1,Icons.map_rounded,'Карта школы','Кабинеты и маршруты'),(2,Icons.calendar_month_rounded,'Расписание','Уроки и группы'),(3,Icons.auto_awesome_rounded,'ДОПы','Кружки и секции'),(4,Icons.settings_rounded,'Настройки','Профиль и админ')];return Drawer(width:330,child:SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:50,height:50,decoration:BoxDecoration(gradient:LinearGradient(colors:AppPalette.gradient(widget.theme)),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.explore_rounded,color:Colors.white)),const SizedBox(width:12),const Expanded(child:Text('Navigator',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))])),const Divider(height:1),Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[for(final x in items)Card(color:index==x.$1?c.primaryContainer:null,child:ListTile(leading:Icon(x.$2,color:index==x.$1?c.primary:null),title:Text(x.$3,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(x.$4),onTap:()=>go(x.$1)))]))])));}
}
class HomePage extends StatelessWidget {
  final String userName;
  final AppThemeType theme;
  final VoidCallback onMenu, onMap, onSchedule, onDop;
  const HomePage({super.key, required this.userName, required this.theme, required this.onMenu, required this.onMap, required this.onSchedule, required this.onDop});

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.gradient(theme);
    final textColor = theme == AppThemeType.darkBlue ? Colors.white : const Color(0xFF142238);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 980 ? 3 : width >= 640 ? 2 : 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Navigator'),
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
                  Text(userName.trim().isEmpty ? 'Твой школьный\nнавигатор' : 'Привет, $userName!', style: TextStyle(color: textColor, fontSize: width < 600 ? 30 : 38, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -1)),
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
                Text('3 раздела', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
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
  Future<void> _start()async{final r=await showDialog<_StartChoice>(context:context,builder:(_)=>_StartDialog(floor:startFloor,id:startId));if(r==null)return;final p=await SharedPreferences.getInstance();await p.setInt('map_start_floor',r.floor);if(r.id==null)await p.remove('map_start_location');else await p.setString('map_start_location',r.id!);if(mounted)setState((){startFloor=r.floor;startId=r.id;});}
  void _open(RoomInfo r){setState(()=>selected=r.id);final route=RouteEngine.build(r.id,startFloor:startFloor,startLocationId:startId);if(route==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Маршрут для этой точки недоступен.')));return;}Navigator.push(context,MaterialPageRoute(builder:(_)=>RoutePage(room:r,route:route)));}
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
class _MapImage extends StatelessWidget{final int floor;final String? selected;const _MapImage({required this.floor,required this.selected});@override Widget build(BuildContext context)=>Card(clipBehavior:Clip.antiAlias,child:InteractiveViewer(minScale:.7,maxScale:4,child:AspectRatio(aspectRatio:7016/4960,child:Stack(children:[Positioned.fill(child:Image.asset('assets/maps/floor${floor}.webp',fit:BoxFit.contain)),if(selected!=null)Positioned.fill(child:CustomPaint(painter:_PointPainter(SchoolData.point(SchoolData.room(selected!)),Theme.of(context).colorScheme.primary)))]))));}
class _PointPainter extends CustomPainter{final Offset p;final Color color;_PointPainter(this.p,this.color);@override void paint(Canvas c,Size s){final o=Offset(p.dx*s.width,p.dy*s.height);c.drawCircle(o,9,Paint()..color=color);c.drawCircle(o,17,Paint()..color=color.withValues(alpha:.22));}@override bool shouldRepaint(covariant _PointPainter o)=>o.p!=p||o.color!=color;}
class SchedulePage extends StatefulWidget {
  final VoidCallback onMenu;
  const SchedulePage({super.key, required this.onMenu});
  @override State<SchedulePage> createState() => _SchedulePageState();
}
class _SchedulePageState extends State<SchedulePage> {
  int day = math.min(DateTime.now().weekday, 6);
  List<ScheduleEntry> entries = []; String classId = ''; bool loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance(); await SchoolScheduleCatalog.load();
    classId = p.getString('student_class_name') ?? '';
    final groups = <String,int>{};
    if (classId.isNotEmpty) { for (final s in SchoolScheduleCatalog.splitSubjects(classId)) groups[s] = p.getInt('student_group_${classId}_$s') ?? 1; entries = SchoolScheduleCatalog.buildPersonal(classId, groups); } else { entries = []; }
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
  void _route(ScheduleEntry e) { if (e.room.isEmpty) return; final r = SchoolData.tryRoom(e.room); if (r == null) return; final route = RouteEngine.build(r.id); if (route != null) Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePage(room:r,route:route))); }
  @override
  Widget build(BuildContext context) {
    final list = entries.where((e) => e.day == day).toList()..sort((a, b) => a.time.compareTo(b.time));
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final splitSubjects = SchoolScheduleCatalog.splitSubjects(classId);
    const dayNames = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота'];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)),
        title: const Text('Расписание'),
        actions: [
          IconButton(tooltip: 'Выбрать класс', onPressed: () => _chooseClass(), icon: const Icon(Icons.school_rounded)),
          if (classId.isNotEmpty)
            IconButton(tooltip: 'Группы по предметам', onPressed: () async { await showStudentGroupSelection(context, classId); await _load(); }, icon: const Icon(Icons.groups_rounded)),
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
                                  separatorBuilder: (_, __) => const SizedBox(height: 9),
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
                          Icon(Icons.layers_rounded, color: scheme.primary),
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
                          Positioned.fill(child: CustomPaint(painter: _RoutePainter(route.nodes.where((n) => n.floor == floor).toList(), scheme.primary))),
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
  final List<RouteNode> nodes; final Color color;
  _RoutePainter(this.nodes,this.color);
  @override void paint(Canvas c,Size s){
    if(nodes.length<2)return;
    final p=Paint()..color=color..strokeWidth=6..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final path=Path();
    for(var i=0;i<nodes.length;i++){final o=Offset(nodes[i].point.dx*s.width,nodes[i].point.dy*s.height);if(i==0)path.moveTo(o.dx,o.dy);else path.lineTo(o.dx,o.dy);}
    c.drawPath(path,p);
  }
  @override bool shouldRepaint(covariant _RoutePainter old)=>old.nodes!=nodes||old.color!=color;
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
      ..translate(size.width * (1 - next) / 2, size.height * (1 - next) / 2)
      ..scale(next);
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

  Future<void> _editClass(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance(); await SchoolScheduleCatalog.load();
    final result = await showDialog<String>(context: context, builder: (_) => const _StudentClassDialog());
    if (!context.mounted || result == null || result.isEmpty) return;
    await prefs.setString('student_class_name', result); await prefs.setString('student_class_id', result); await showStudentGroupSelection(context, result);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Профиль расписания: $result')));
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
      const SizedBox(height: 18), const Text('Администрирование', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: ListTile(leading: Icon(Icons.admin_panel_settings_rounded, color: c.primary), title: const Text('Вход для администраторов'), subtitle: const Text('Управление администраторами, расписанием, ДОПами и синхронизацией'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openAdmin(context))),
      const SizedBox(height: 18), const Text('Приложение', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Card(child: Column(children: [ListTile(leading: Icon(Icons.info_outline_rounded, color: c.primary), title: const Text('О приложении'), subtitle: const Text('Navigator 1.0.0'), onTap: () => showAboutDialog(context: context, applicationName: 'Navigator', applicationVersion: '1.0.0', applicationLegalese: 'Навигатор школы «Поколение»')), const Divider(height: 1), ListTile(leading: Icon(Icons.restore_rounded, color: c.primary), title: const Text('Сбросить тему'), onTap: () => onThemeChanged(AppThemeType.turquoise))])),
    ]))));
  }

  Future<void> _editName(BuildContext context) async {
    final result = await showDialog<String>(context: context, builder: (_) => _EditValueDialog(title: 'Изменить имя', label: 'Имя', hint: 'Как к тебе обращаться?', initialValue: userName));
    if (!context.mounted || result == null || result.isEmpty) return;
    onNameChanged(result);
  }
  void _pickTheme(BuildContext context) => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [const Text('Цветовая тема', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 12), _ThemeTile(title: 'Жёлтая', description: 'Жёлтый → бежевый', colors: AppPalette.yellow, selected: theme == AppThemeType.yellow, onTap: () { onThemeChanged(AppThemeType.yellow); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Бирюзовая', description: 'Насыщенный бирюзовый → светло-зелёный', colors: AppPalette.turquoise, selected: theme == AppThemeType.turquoise, onTap: () { onThemeChanged(AppThemeType.turquoise); Navigator.pop(sheetContext); }), _ThemeTile(title: 'Тёмно-синяя', description: 'Тёмно-синий → фиолетовый', colors: AppPalette.darkBlue, selected: theme == AppThemeType.darkBlue, onTap: () { onThemeChanged(AppThemeType.darkBlue); Navigator.pop(sheetContext); })])));
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
