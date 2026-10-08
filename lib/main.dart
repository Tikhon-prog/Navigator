import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_panel.dart';
import 'door_points.dart';
import 'corridor_roads.dart';
import 'local_notification_service.dart';
import 'online_data_service.dart';
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
  static Map<String, Set<int>> subjectGroups(String className) {
    final result = <String, Set<int>>{};
    for (final e in variants(className)) {
      final subject = baseSubject('${e['subject'] ?? ''}');
      if (subject.isEmpty) continue;
      (result[subject] ??= <int>{}).add(int.tryParse('${e['group']}') ?? 1);
    }
    return result;
  }
  static Set<String> splitSubjects(String className) => subjectGroups(className).entries.where((e) => e.value.length > 1).map((e) => e.key).toSet();
  static List<ScheduleEntry> buildPersonal(String className, Map<String, int> selected) {
    final all = variants(className);
    final result = <ScheduleEntry>[];
    final seen = <String>{};
    for (final e in all) {
      final subject = baseSubject('${e['subject'] ?? ''}');
      if (subject.isEmpty) continue;
      final group = int.tryParse('${e['group']}') ?? 1;
      final wanted = selected[subject] ?? 1;
      final slotGroups = all.where((x) => '${x['day']}' == '${e['day']}' && '${x['time']}' == '${e['time']}' && baseSubject('${x['subject'] ?? ''}') == subject).map((x) => int.tryParse('${x['group']}') ?? 1).toSet();
      if (slotGroups.length > 1 && group != wanted) continue;
      final day = int.tryParse('${e['day']}') ?? 1;
      final time = '${e['time'] ?? ''}'.trim();
      final room = '${e['room'] ?? ''}'.trim();
      final key = '$day|$time|$subject|$room';
      if (!seen.add(key)) continue;
      result.add(ScheduleEntry(id: '${className}_${day}_${time}_${subject}_${group}'.replaceAll(RegExp(r'[^A-Za-zА-Яа-яЁё0-9_-]'), '_'), day: day, time: time, subject: subject, room: room, group: group));
    }
    result.sort((a,b) => a.day != b.day ? a.day.compareTo(b.day) : a.time.compareTo(b.time));
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
    final requestedAnchors = <String>{destination.id, if (startLocationId != null) startLocationId!};
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
  ThemeData _theme(AppThemeType type){final dark=type==AppThemeType.darkBlue;final colors=AppPalette.gradient(type);final cs=ColorScheme.fromSeed(seedColor:colors.first,brightness:dark?Brightness.dark:Brightness.light).copyWith(primary:dark?const Color(0xFF6F91FF):colors.first,secondary:dark?const Color(0xFF9EAEFF):colors.last,surface:dark?const Color(0xFF07101F):null,surfaceContainer:dark?const Color(0xFF0E1B2F):null,surfaceContainerHigh:dark?const Color(0xFF14243D):null,surfaceContainerHighest:dark?const Color(0xFF1A2C49):null,onSurface:dark?const Color(0xFFF3F6FF):null,onSurfaceVariant:dark?const Color(0xFFB8C5DE):null,outlineVariant:dark?const Color(0xFF263751):null);return ThemeData(useMaterial3:true,brightness:dark?Brightness.dark:Brightness.light,colorScheme:cs,scaffoldBackgroundColor:cs.surface,appBarTheme:AppBarTheme(backgroundColor:cs.surface,foregroundColor:cs.onSurface,elevation:0,surfaceTintColor:Colors.transparent),cardTheme:CardThemeData(color:dark?cs.surfaceContainer:null,elevation:dark?1:0,margin:EdgeInsets.zero,surfaceTintColor:Colors.transparent,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20))),inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:cs.surfaceContainerHighest,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16),borderSide:BorderSide.none)),filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(backgroundColor:cs.primary,foregroundColor:cs.onPrimary,minimumSize:const Size(48,48),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)))));}
}
class AppShell extends StatefulWidget{
  final String userName;final AppThemeType theme;final ValueChanged<AppThemeType> onThemeChanged;final ValueChanged<String> onNameChanged;
  const AppShell({super.key,required this.userName,required this.theme,required this.onThemeChanged,required this.onNameChanged});
  @override State<AppShell> createState()=>_AppShellState();
}
class _AppShellState extends State<AppShell>{
  int index=0;String? selectedRoom;final key=GlobalKey<ScaffoldState>();
  void go(int i){setState(()=>index=i);key.currentState?.closeDrawer();}
  @override Widget build(BuildContext context){final menu=()=>key.currentState?.openDrawer();return Scaffold(key:key,drawer:_drawer(context),body:IndexedStack(index:index,children:[HomePage(userName:widget.userName,theme:widget.theme,onMenu:menu,onMap:()=>go(1),onSchedule:()=>go(2),onDop:()=>go(3)),MapPage(initialRoom:selectedRoom,onMenu:menu),SchedulePage(onMenu:menu),SupplementsPage(onMenu:menu),SettingsPage(theme:widget.theme,userName:widget.userName,onThemeChanged:widget.onThemeChanged,onNameChanged:widget.onNameChanged,onMenu:menu)]));}
  Widget _drawer(BuildContext context){final c=Theme.of(context).colorScheme;final items=[(0,Icons.home_rounded,'Главное меню','Обзор'),(1,Icons.map_rounded,'Карта школы','Кабинеты и маршруты'),(2,Icons.calendar_month_rounded,'Расписание','Уроки и группы'),(3,Icons.auto_awesome_rounded,'ДОПы','Кружки и секции'),(4,Icons.settings_rounded,'Настройки','Профиль и админ')];return Drawer(width:330,child:SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:50,height:50,decoration:BoxDecoration(gradient:LinearGradient(colors:AppPalette.gradient(widget.theme)),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.explore_rounded,color:Colors.white)),const SizedBox(width:12),const Expanded(child:Text('Navigator',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))])),const Divider(height:1),Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[for(final x in items)Card(color:index==x.$1?c.primaryContainer:null,child:ListTile(leading:Icon(x.$2,color:index==x.$1?c.primary:null),title:Text(x.$3,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(x.$4),onTap:()=>go(x.$1)))]))])));}
}
class HomePage extends StatelessWidget {
  final String userName;
  final AppThemeType theme;
  final VoidCallback onMenu, onMap, onSchedule, onDop;
  const HomePage({super.key,required this.userName,required this.theme,required this.onMenu,required this.onMap,required this.onSchedule,required this.onDop});
  @override
  Widget build(BuildContext context) {
    final colors=AppPalette.gradient(theme);
    return Scaffold(
      appBar: AppBar(leading:IconButton(onPressed:onMenu,icon:const Icon(Icons.menu_rounded)),title:const Text('Navigator',style:TextStyle(fontWeight:FontWeight.w900))),
      body: Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:1050),
        child:ListView(padding:const EdgeInsets.all(18),children:[
          Container(
            padding:const EdgeInsets.all(24),
            decoration:BoxDecoration(gradient:LinearGradient(colors:colors),borderRadius:BorderRadius.circular(28)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(userName.isEmpty?'Главное меню':'Привет, '+userName+'!',style:const TextStyle(color:Colors.white,fontSize:27,fontWeight:FontWeight.w900)),
              const SizedBox(height:8),
              const Text('Карта школы, расписание и ДОПы — в одном приложении.',style:TextStyle(color:Colors.white)),
              const SizedBox(height:18),
              Wrap(spacing:10,runSpacing:10,children:[
                _HeroButton('Карта школы',Icons.map_rounded,onMap),
                _HeroButton('Расписание',Icons.calendar_month_rounded,onSchedule),
                _HeroButton('ДОПы',Icons.auto_awesome_rounded,onDop),
              ]),
            ]),
          ),
          const SizedBox(height:16),
          Card(child:ListTile(
            leading:Icon(Icons.offline_bolt_rounded,color:Theme.of(context).colorScheme.primary),
            title:const Text('Офлайн-first',style:TextStyle(fontWeight:FontWeight.w900)),
            subtitle:const Text('Карта и базовые данные остаются доступными без интернета.'),
          )),
        ]),
      )),
    );
  }
}
class _HeroButton extends StatelessWidget{final String text;final IconData icon;final VoidCallback onTap;const _HeroButton(this.text,this.icon,this.onTap);@override Widget build(BuildContext context)=>FilledButton.icon(onPressed:onTap,icon:Icon(icon),label:Text(text),style:FilledButton.styleFrom(backgroundColor:Colors.white24,foregroundColor:Colors.white));}
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
    final rooms = SchoolData.rooms.where((r) => r.floor == floor).toList();
    final values = <String>['__entrance__', ...rooms.map((r) => r.id)];
    if (!values.contains(choice)) choice = '__entrance__';
    return AlertDialog(
      title: const Text('Начало маршрута'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<int>(segments: const [ButtonSegment(value:1,label:Text('1 этаж')),ButtonSegment(value:2,label:Text('2 этаж')),ButtonSegment(value:3,label:Text('3 этаж'))], selected:{floor}, onSelectionChanged:(v){setState((){floor=v.first;choice='__entrance__';});}),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(initialValue: choice, isExpanded: true, decoration: const InputDecoration(labelText:'Точка старта'), items: [const DropdownMenuItem(value:'__entrance__',child:Text('Главный вход')), ...rooms.map((r)=>DropdownMenuItem(value:r.id,child:Text('${r.id} — ${SchoolData.title(r)}')))], onChanged:(v)=>setState(()=>choice=v??'__entrance__')),
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
  List<RoomInfo> get rooms=>SchoolData.rooms.where((r)=>r.floor==floor&&(query.isEmpty||r.id.toLowerCase().contains(query.toLowerCase())||SchoolData.title(r).toLowerCase().contains(query.toLowerCase()))).toList();
  Future<void> _start()async{final r=await showDialog<_StartChoice>(context:context,builder:(_)=>_StartDialog(floor:startFloor,id:startId));if(r==null)return;final p=await SharedPreferences.getInstance();await p.setInt('map_start_floor',r.floor);if(r.id==null)await p.remove('map_start_location');else await p.setString('map_start_location',r.id!);if(mounted)setState((){startFloor=r.floor;startId=r.id;});}
  void _open(RoomInfo r){setState(()=>selected=r.id);final route=RouteEngine.build(r.id,startFloor:startFloor,startLocationId:startId);if(route==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Маршрут для этой точки недоступен.')));return;}Navigator.push(context,MaterialPageRoute(builder:(_)=>RoutePage(room:r,route:route)));}
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(leading:IconButton(onPressed:widget.onMenu,icon:const Icon(Icons.menu_rounded)),title:const Text('Карта школы',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:_start,tooltip:'Начало маршрута',icon:const Icon(Icons.my_location_rounded)),IconButton(onPressed:()=>setState((){query='';search.clear();}),tooltip:'Очистить поиск',icon:const Icon(Icons.clear_all_rounded))]),
      body:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,6),child:Row(children:[
          Expanded(child:TextField(controller:search,onChanged:(v)=>setState(()=>query=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search_rounded),hintText:'Номер или название кабинета'))),
          const SizedBox(width:10),
          SegmentedButton<int>(segments:const [ButtonSegment(value:1,label:Text('1')),ButtonSegment(value:2,label:Text('2')),ButtonSegment(value:3,label:Text('3'))],selected:{floor},onSelectionChanged:(v)=>setState(()=>floor=v.first)),
        ])),
        Expanded(child:Row(children:[
          Expanded(flex:3,child:Padding(padding:const EdgeInsets.fromLTRB(16,6,8,16),child:_MapImage(floor:floor,selected:selected))),
          SizedBox(width:340,child:ListView(padding:const EdgeInsets.fromLTRB(8,6,16,16),children:[
            Card(child:ListTile(leading:const Icon(Icons.login_rounded),title:const Text('Точка старта',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(startId==null?'Главный вход':SchoolData.title(SchoolData.room(startId!))),onTap:_start)),
            const SizedBox(height:6),
            Text('Кабинеты и места • '+floor.toString()+' этаж',style:const TextStyle(fontWeight:FontWeight.w900)),
            const SizedBox(height:6),
            ...rooms.map((r)=>Card(margin:const EdgeInsets.only(bottom:6),child:ListTile(leading:Icon(SchoolData.isPlace(r)?Icons.place_rounded:Icons.meeting_room_rounded),title:Text(SchoolData.title(r),maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('каб. '+r.id),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>_open(r)))),
          ])),
        ])),
      ]),
    );
  }
}
class _MapImage extends StatelessWidget{final int floor;final String? selected;const _MapImage({required this.floor,required this.selected});@override Widget build(BuildContext context)=>Card(clipBehavior:Clip.antiAlias,child:InteractiveViewer(minScale:.7,maxScale:4,child:AspectRatio(aspectRatio:7016/4960,child:Stack(children:[Positioned.fill(child:Image.asset('assets/maps/floor${floor}.webp',fit:BoxFit.contain)),if(selected!=null)Positioned.fill(child:CustomPaint(painter:_PointPainter(SchoolData.room(selected!).point,Theme.of(context).colorScheme.primary)))]))));}
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
  @override Widget build(BuildContext context) {
    final list = entries.where((e) => e.day == day).toList()..sort((a,b)=>a.time.compareTo(b.time));
    return Scaffold(appBar: AppBar(leading: IconButton(onPressed: widget.onMenu,tooltip:'Меню',icon:const Icon(Icons.menu_rounded)), title: Text(classId.isEmpty?'Расписание':'Расписание • $classId',style:const TextStyle(fontWeight:FontWeight.w900)), actions:[IconButton(tooltip:'Выбрать класс',onPressed:()=>_chooseClass(),icon:const Icon(Icons.school_rounded)), if(classId.isNotEmpty) IconButton(tooltip:'Группы',onPressed:() async {await showStudentGroupSelection(context,classId);await _load();},icon:const Icon(Icons.groups_rounded))]),
      body: loading ? const Center(child:CircularProgressIndicator()) : Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1100),child:Column(children:[
        if(classId.isEmpty) Padding(padding:const EdgeInsets.fromLTRB(18,18,18,8),child:Card(child:ListTile(title:const Text('Выбери класс',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:const Text('После выбора расписание и группы сохранятся на устройстве.'),trailing:FilledButton(onPressed:()=>_chooseClass(required:true),child:const Text('Выбрать'))))),
        SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.fromLTRB(18,10,18,8),child:SegmentedButton<int>(segments:const [ButtonSegment(value:1,label:Text('Пн')),ButtonSegment(value:2,label:Text('Вт')),ButtonSegment(value:3,label:Text('Ср')),ButtonSegment(value:4,label:Text('Чт')),ButtonSegment(value:5,label:Text('Пт')),ButtonSegment(value:6,label:Text('Сб'))],selected:{day},onSelectionChanged:(v)=>setState(()=>day=v.first))),
        Expanded(child:list.isEmpty?Center(child:Text(classId.isEmpty?'Выбери класс, чтобы увидеть расписание':'На этот день уроков нет')):ListView.builder(padding:const EdgeInsets.fromLTRB(18,8,18,30),itemCount:list.length,itemBuilder:(_,i){final e=list[i];final room=e.room.isEmpty?null:SchoolData.tryRoom(e.room);return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:CircleAvatar(child:Text(e.time.split(':').first)),title:Text(e.subject,style:const TextStyle(fontWeight:FontWeight.w900)),subtitle:Text(e.room.isEmpty?e.time:'${e.time} • каб. ${e.room}'),trailing:IconButton(onPressed:room==null?null:()=>_route(e),tooltip:'Как пройти',icon:const Icon(Icons.route_rounded))));})),
      ]))),
    );
  }
}
class RoutePage extends StatelessWidget {
  final RoomInfo room; final RouteResult route;
  const RoutePage({super.key,required this.room,required this.route});
  @override Widget build(BuildContext context){
    final steps=RouteEngine.instructions(route);
    return Scaffold(
      appBar:AppBar(title:Text('Маршрут → '+SchoolData.title(room),style:const TextStyle(fontWeight:FontWeight.w900))),
      body:ListView(
        padding:const EdgeInsets.all(16),
        children:[
          Card(clipBehavior:Clip.antiAlias,child:AspectRatio(
            aspectRatio:7016/4960,
            child:Stack(children:[
              Positioned.fill(child:Image.asset('assets/maps/floor'+room.floor.toString()+'.webp',fit:BoxFit.contain)),
              Positioned.fill(child:CustomPaint(painter:_RoutePainter(route.nodes.where((n)=>n.floor==room.floor).toList(),Theme.of(context).colorScheme.primary))),
            ]),
          )),
          const SizedBox(height:12),
          Card(child:ListTile(leading:const Icon(Icons.route_rounded),title:const Text('Маршрут построен',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:Text('Этаж старта: '+route.startFloor.toString()+' • этаж назначения: '+room.floor.toString()))),
          for(final e in steps.asMap().entries)Card(child:ListTile(leading:CircleAvatar(child:Text((e.key+1).toString())),title:Text(e.value.text),subtitle:Text(e.value.floor.toString()+' этаж'))),
        ],
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
class FullscreenMapPage extends StatelessWidget {
  final int floor; final String? selectedRoom; final String? routeRoom; final int startFloor; final String? startLocationId;
  const FullscreenMapPage({super.key,required this.floor,required this.selectedRoom,required this.routeRoom,required this.startFloor,required this.startLocationId});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(floor.toString()+' этаж')),body:InteractiveViewer(minScale:.5,maxScale:6,child:Center(child:AspectRatio(aspectRatio:7016/4960,child:Image.asset('assets/maps/floor'+floor.toString()+'.webp',fit:BoxFit.contain)))));
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
