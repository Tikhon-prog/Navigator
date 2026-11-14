part of '../main.dart';

class RoomInfo {
  final String id;
  final int floor;
  final String name;
  final Offset point;
  final String corridor;

  const RoomInfo(this.id, this.floor, this.name, this.point, this.corridor);
}

/// Functional groups for the school map. Categories are derived from the
/// verified room catalog; they do not alter room IDs or route graph anchors.
enum SchoolLocationCategory {
  classrooms('Учебные', Icons.school_rounded),
  laboratories('Лаборатории и IT', Icons.science_rounded),
  workshops('Мастерские и творчество', Icons.palette_rounded),
  sports('Спорт и здоровье', Icons.sports_basketball_rounded),
  administration('Администрация', Icons.badge_rounded),
  common('Общие пространства', Icons.meeting_room_rounded);

  const SchoolLocationCategory(this.label, this.icon);
  final String label;
  final IconData icon;
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
