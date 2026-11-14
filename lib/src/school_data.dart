part of '../main.dart';

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

  static SchoolLocationCategory category(RoomInfo room) {
    final name = room.name.toLowerCase();
    final id = room.id.toLowerCase();

    if (name.contains('административ') ||
        name.contains('директор') ||
        name.contains('учительская') ||
        name.contains('приёмная') ||
        name.contains('приемная')) {
      return SchoolLocationCategory.administration;
    }

    if (name.contains('бассейн') ||
        name.contains('спортив') ||
        name.contains('тренажёр') ||
        name.contains('тренажер') ||
        name.contains('тренерская') ||
        name.contains('медицинский пункт') ||
        name.contains('психологической разгрузки')) {
      return SchoolLocationCategory.sports;
    }

    if (name.contains('лаборатор') ||
        name.contains('робототех') ||
        name.contains('беспилот') ||
        name.contains('искусственного интеллекта') ||
        name.contains('киберспорт') ||
        name.contains('инженерный цех') ||
        name.contains('дрон-рейсинг') ||
        name.contains('космических технологий') ||
        name.contains('медицинской физики') ||
        name.contains('генетики') ||
        name.contains('агротехнолог') ||
        name.contains('биотехнолог') ||
        name.contains('точного земледелия')) {
      return SchoolLocationCategory.laboratories;
    }

    if (name.contains('мастерская') ||
        name.contains('студия') ||
        name.contains('сцена') ||
        name.contains('гример') ||
        name.contains('гримёр') ||
        name.contains('телестудия') ||
        name.contains('издательский') ||
        name.contains('музей') ||
        name.contains('кулинария') ||
        name.contains('столярная') ||
        name.contains('слесарная') ||
        name.contains('инструментальная') ||
        name.contains('центр детских инициатив') ||
        name.contains('хореограф') ||
        name.contains('актовый зал')) {
      return SchoolLocationCategory.workshops;
    }

    if (name.contains('столовая') ||
        name.contains('пищеблок') ||
        name.contains('библиотек') ||
        name.contains('библиотеч') ||
        name.contains('терраса') ||
        name.contains('лекторий')) {
      return SchoolLocationCategory.common;
    }

    if (id.startsWith('place_')) return SchoolLocationCategory.common;
    return SchoolLocationCategory.classrooms;
  }

  static String title(RoomInfo r) => isPlace(r) ? r.name : 'Кабинет ${r.id}';
  static String typeLabel(RoomInfo r) =>
      isPlace(r) ? category(r).label : 'Кабинет';
  static Offset point(RoomInfo r) => DoorPoints.of(r.id, r.point);
}
