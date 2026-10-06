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
  static const darkBlue = [Color(0xFF102A66), Color(0xFF6A42D8)];

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
    _data = Map<String, dynamic>.from(jsonDecode(await rootBundle.loadString('assets/data/school_schedule_2026-10-05.json')) as Map);
  }
  static List<String> grades() => List<String>.from((_data?['class_order'] as Map? ?? {}).keys);
  static List<String> classesForGrade(String grade) => List<String>.from(((_data?['class_order'] as Map?)?[grade] as List?) ?? const []);
  static List<Map<String, dynamic>> variants(String className) {
    final raw = ((_data?['classes'] as Map?)?[className] as Map?)?['variants'];
    return raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
  }
  static Map<String, Set<int>> subjectGroups(String className) {
    final result = <String, Set<int>>{};
    for (final e in variants(className)) {
      final subject = '${e['subject'] ?? ''}'.trim();
      if (subject.isEmpty) continue;
      (result[subject] ??= <int>{}).add(int.tryParse('${e['group']}') ?? 1);
    }
    return result;
  }

  static Set<String> splitSubjects(String className) => subjectGroups(className).entries.where((e) => e.value.length > 1).map((e) => e.key).toSet();
  static List<ScheduleEntry> buildPersonal(String className, Map<String, int> selected) {
    final all = variants(className), result = <ScheduleEntry>[]; final seen = <String>{};
    for (final e in all) {
      final subject = '${e['subject'] ?? ''}'.trim(); final group = int.tryParse('${e['group']}') ?? 1; final wanted = selected[subject] ?? 1;
      final slotGroups = all.where((x) => '${x['day']}' == '${e['day']}' && '${x['time']}' == '${e['time']}' && '${x['subject'] ?? ''}'.trim() == subject).map((x) => int.tryParse('${x['group']}') ?? 1).toSet();
      if (slotGroups.length > 1 && group != wanted) continue;
      final key = '${e['day']}|${e['time']}|$subject|${e['room']}|${e['teacher']}'; if (!seen.add(key)) continue;
      result.add(ScheduleEntry(id: '${className}_${e['day']}_${e['time']}_${subject.hashCode}_$group', day: int.tryParse('${e['day']}') ?? 1, time: '${e['time'] ?? ''}', subject: subject, room: '${e['room'] ?? ''}', teacher: '${e['teacher'] ?? ''}', group: group));
    }
    result.sort((a,b) => a.day != b.day ? a.day.compareTo(b.day) : a.time.compareTo(b.time)); return result;
  }
}

class _StudentClassDialog extends StatefulWidget { const _StudentClassDialog(); @override State<_StudentClassDialog> createState() => _StudentClassDialogState(); }
class _StudentClassDialogState extends State<_StudentClassDialog> {
  String? grade;
  @override Widget build(BuildContext context) { final grades=SchoolScheduleCatalog.grades(); final classes=grade==null ? const <String>[] : SchoolScheduleCatalog.classesForGrade(grade!); return AlertDialog(title: const Text('Какой у вас класс?'), content: SizedBox(width:420, child: Column(mainAxisSize:MainAxisSize.min, children:[DropdownButtonFormField<String>(decoration:const InputDecoration(labelText:'Параллель'), initialValue:grade, items:grades.map((g)=>DropdownMenuItem(value:g,child:Text(g))).toList(), onChanged:(v)=>setState(()=>grade=v)), if(classes.isNotEmpty) ...[const SizedBox(height:12), Wrap(spacing:8,runSpacing:8,children:classes.map((c)=>ActionChip(label:Text(c),onPressed:()=>Navigator.pop(context,c))).toList())]]))); }
}
Future<void> showStudentGroupSelection(BuildContext context,String className,{bool onlyIfNeeded=false}) async {
  await SchoolScheduleCatalog.load(); final subjects=SchoolScheduleCatalog.splitSubjects(className).toList()..sort(); if(subjects.isEmpty && onlyIfNeeded)return; final prefs=await SharedPreferences.getInstance(); final values=<String,int>{for(final s in subjects)s:prefs.getInt('student_group_${className}_$s')??1};
  if(!context.mounted)return; await showDialog<void>(context:context,builder:(_)=>_StudentGroupsDialog(className:className,subjects:subjects,values:values));
}
class _StudentGroupsDialog extends StatefulWidget {
  final String className;
  final List<String> subjects;
  final Map<String, int> values;
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
      return ListTile(
        title: Text(s),
        subtitle: const Text('Выбор действует только для этого предмета'),
        trailing: SegmentedButton<int>(
          segments: groups.map((g) => ButtonSegment(value: g, label: Text('Группа $g'))).toList(),
          selected: {values[s] ?? groups.first},
          onSelectionChanged: (v) => setState(() => values[s] = v.first),
        ),
      );
    }).toList())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(onPressed: () async {
        final p = await SharedPreferences.getInstance();
        for (final e in values.entries) await p.setInt('student_group_${widget.className}_${e.key}', e.value);
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('Сохранить')),
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
  @override
  State<NavigatorApp> createState() => _NavigatorAppState();
}

class _NavigatorAppState extends State<NavigatorApp> {
  AppThemeType theme = AppThemeType.turquoise;
  String userName = '';
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await SchoolScheduleCatalog.load();
    classId = prefs.getString('student_class_name') ?? '';
    if (classId.isEmpty && mounted) {
      classId = await showDialog<String>(context: context, barrierDismissible: false, builder: (_) => const _StudentClassDialog()) ?? '';
      if (classId.isNotEmpty) { await prefs.setString('student_class_name', classId); await prefs.setString('student_class_id', classId); }
    }
    if (classId.isNotEmpty) {
      final groups = <String,int>{};
      for (final subject in SchoolScheduleCatalog.splitSubjects(classId)) groups[subject] = prefs.getInt('student_group_${classId}_$subject') ?? 1;
      entries = SchoolScheduleCatalog.buildPersonal(classId, groups);
    }
    if (mounted) setState(() => loading = false);
    await _scheduleNextReminder();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedule_$classId', jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  Future<void> _scheduleNextReminder() async {
    try {
      await LocalNotificationService().scheduleUpcomingLessons(
        entries: entries
            .map((e) => (
                  id: e.id,
                  day: e.day,
                  time: e.time,
                  subject: e.subject,
                  room: e.room,
                ))
            .toList(),
      );
    } catch (_) {
      // Уведомления не должны ломать экран расписания.
    }
  }

  List<ScheduleEntry> get today {
    final list = entries.where((e) => e.day == day).toList();
    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(leading: IconButton(onPressed: widget.onMenu, tooltip: 'Меню', icon: const Icon(Icons.menu_rounded)), title: Text('Расписание • $classId', style: const TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(tooltip: 'Группы по предметам', onPressed: () async { await showStudentGroupSelection(context, classId); await _load(); }, icon: const Icon(Icons.groups_rounded)), IconButton(tooltip: 'Синхронизировать', onPressed: _syncOnline, icon: const Icon(Icons.cloud_sync_rounded)), IconButton(tooltip: 'Добавить урок', onPressed: _add, icon: const Icon(Icons.add_rounded))]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                      child: SegmentedButton<int>(
                        segments: const [ButtonSegment(value: 1, label: Text('Пн')), ButtonSegment(value: 2, label: Text('Вт')), ButtonSegment(value: 3, label: Text('Ср')), ButtonSegment(value: 4, label: Text('Чт')), ButtonSegment(value: 5, label: Text('Пт')), ButtonSegment(value: 6, label: Text('Сб'))],
                        selected: {day},
                        onSelectionChanged: (v) => setState(() => day = v.first),
                      ),
                    ),
                    Expanded(child: today.isEmpty ? _empty() : ListView.builder(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), itemCount: today.length, itemBuilder: (context, i) => _entryCard(today[i], wide))),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _empty() => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.event_note_rounded, size: 60, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12), const Text('На этот день пока ничего нет', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text('Класс: $classId • базовое расписание можно менять в этом профиле.')])));

  Widget _entryCard(ScheduleEntry e, bool wide) {
    RoomInfo? room;
    for (final candidate in SchoolData.rooms) {
      if (candidate.id == e.room) {
        room = candidate;
        break;
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(child: Text(e.time.isEmpty ? '•' : e.time.split(':').first)),
        title: Text(e.subject.isEmpty ? 'Без названия' : e.subject, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(room == null ? (e.room.isEmpty ? 'Кабинет не указан' : 'Кабинет ${e.room}') : 'Кабинет ${room.id} • ${room.floor} этаж • ${room.name}'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _edit(e);
            if (value == 'delete') _delete(e);
            if (value == 'route' && room != null) {
              final route = RouteEngine.build(room.id);
              if (route != null) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => RoutePage(room: room!, route: route)));
              }
            }
          },
          itemBuilder: (context) => [
            if (room != null) const PopupMenuItem(value: 'route', child: Text('Как пройти')),
            const PopupMenuItem(value: 'edit', child: Text('Изменить')),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ),
    );
  }

  Future<void> _syncOnline() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('navigator_api_url') ?? '';
    if (baseUrl.isEmpty) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала укажи URL API в админ-панели.'))); return; }
    final service = OnlineDataService(NavigatorApiConfig(baseUrl: baseUrl));
    final data = await service.get('health');
    if (data == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сервер недоступен. Локальное базовое расписание сохранено.'))); return; }
    final payload = await service.get('schedule?class_id=${Uri.encodeComponent(classId)}');
    if (payload == null) return;
    final rows = payload['rows'];
    if (rows is List) {
      final converted = <ScheduleEntry>[];
      for (final raw in rows) {
        if (raw is! Map<String, dynamic>) continue;
        final row = raw['row'];
        if (row is! List || row.length < 9) continue;
        converted.add(ScheduleEntry(
          id: '${row[0]}',
          day: int.tryParse('${row[2]}') ?? 1,
          time: '${row[4]}',
          subject: '${row[6]}',
          room: '${row[8]}',
        ));
      }
      if (converted.isNotEmpty) { setState(() => entries = converted); await _save(); }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Базовое расписание класса синхронизировано.')));
  }

  Future<void> _add() async {
    final result = await showDialog<ScheduleEntry>(context: context, builder: (context) => ScheduleEditor(defaultDay: day));
    if (result != null) {
      setState(() => entries.add(result));
      await _save();
      await _scheduleNextReminder();
    }
  }

  Future<void> _edit(ScheduleEntry old) async {
    final result = await showDialog<ScheduleEntry>(context: context, builder: (context) => ScheduleEditor(initial: old));
    if (result != null) {
      final i = entries.indexWhere((e) => e.id == old.id);
      if (i >= 0) {
        setState(() => entries[i] = result);
        await _save();
        await _scheduleNextReminder();
      }
    }
  }

  Future<void> _delete(ScheduleEntry entry) async {
    setState(() => entries.removeWhere((e) => e.id == entry.id));
    await _save();
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
