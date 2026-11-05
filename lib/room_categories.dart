/// Human-friendly room grouping based only on names in the school catalogue.
class RoomCategories {
  static const all = 'Все помещения';
  static const labels = <String>[
    all,
    'Учительские',
    'Администрация',
    'Математика',
    'Наука и лаборатории',
    'Информатика и технологии',
    'Гуманитарные',
    'Творческие',
    'Мастерские',
    'Спорт',
    'Медицина и поддержка',
    'Общие пространства',
    'Учебные кабинеты',
  ];

  static String classify(String id, String name) {
    final value = name.toLowerCase().replaceAll('ё', 'е');
    if (value.contains('учительск')) return 'Учительские';
    if (value.contains('приемн') ||
        value.contains('директор') ||
        value.contains('административ')) {
      return 'Администрация';
    }
    if (value.contains('математик') || value.contains('алгебр') || value.contains('геометр')) {
      return 'Математика';
    }
    if (value.contains('информат') ||
        value.contains('искусствен') ||
        value.contains('робототех') ||
        value.contains('беспилот') ||
        value.contains('космическ') ||
        value.contains('киберспорт') ||
        value.contains('дрон')) {
      return 'Информатика и технологии';
    }
    if (value.contains('физик') ||
        value.contains('хими') ||
        value.contains('биолог') ||
        value.contains('лаборатор') ||
        value.contains('генетик') ||
        value.contains('биотех') ||
        value.contains('агротех') ||
        value.contains('земледел') ||
        value.contains('наук')) {
      return 'Наука и лаборатории';
    }
    if (value.contains('истори') ||
        value.contains('обществозн') ||
        value.contains('русск') ||
        value.contains('литератур') ||
        value.contains('иностран') ||
        value.contains('географ')) {
      return 'Гуманитарные';
    }
    if (value.contains('художеств') ||
        value.contains('театр') ||
        value.contains('дизайн') ||
        value.contains('телестуди') ||
        value.contains('хореограф')) {
      return 'Творческие';
    }
    if (value.contains('мастерск') ||
        value.contains('кулинар') ||
        value.contains('инженер') ||
        value.contains('издательск') ||
        value.contains('столяр') ||
        value.contains('слесар') ||
        value.contains('инструмент')) {
      return 'Мастерские';
    }
    if (value.contains('тренер') ||
        value.contains('спортив') ||
        value.contains('бассейн') ||
        (value.contains('зал') &&
            (value.contains('спорт') || value.contains('тренаж')))) {
      return 'Спорт';
    }
    if (value.contains('медицин') ||
        value.contains('медпункт') ||
        value.contains('психолог')) {
      return 'Медицина и поддержка';
    }
    if (value.contains('столов') ||
        value.contains('пищеблок') ||
        value.contains('библиотек') ||
        value.contains('лектори') ||
        value.contains('актов') ||
        value.contains('сцен') ||
        value.contains('гример') ||
        value.contains('террас') ||
        value.contains('музей') ||
        value.contains('центр детских инициатив') ||
        id.startsWith('place_')) {
      return 'Общие пространства';
    }
    return 'Учебные кабинеты';
  }
}
