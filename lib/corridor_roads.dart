import 'package:flutter/material.dart';

/// Real corridor centre-lines supplied from the school floor plans.
/// Coordinates are normalized from the original 7016x4960 px maps.
class CorridorSegment {
  final int floor;
  final Offset a;
  final Offset b;
  final String label;
  final bool hidden;

  const CorridorSegment(this.floor, this.a, this.b, this.label, {this.hidden = false});
}

class CorridorRoads {
  static Offset p(double x, double y) => Offset(x / 7016.0, y / 4960.0);

  static const List<CorridorSegment> all = [
    // 1 floor
    CorridorSegment(1, Offset(573 / 7016, 946 / 4960), Offset(573 / 7016, 2418 / 4960), 'Длинный университетский квартал'),
    CorridorSegment(1, Offset(569 / 7016, 1466 / 4960), Offset(673 / 7016, 1466 / 4960), 'короткий подход к лестнице около 126', hidden: true),
    CorridorSegment(1, Offset(357 / 7016, 2410 / 4960), Offset(1081 / 7016, 2402 / 4960), 'Короткий университетский квартал'),
    CorridorSegment(1, Offset(2861 / 7016, 1050 / 4960), Offset(2845 / 7016, 2414 / 4960), 'Длинное фиолетовое крыло'),
    CorridorSegment(1, Offset(2845 / 7016, 2414 / 4960), Offset(2229 / 7016, 2402 / 4960), 'Короткое фиолетовое крыло'),
    CorridorSegment(1, Offset(2229 / 7016, 2402 / 4960), Offset(2173 / 7016, 2406 / 4960), 'Соединение фиолетового и центрального коридоров', hidden: true),
    CorridorSegment(1, Offset(2841 / 7016, 1470 / 4960), Offset(2941 / 7016, 1470 / 4960), 'короткий подход к лестнице около 10', hidden: true),
    CorridorSegment(1, Offset(1081 / 7016, 2399 / 4960), Offset(2229 / 7016, 2403 / 4960), 'Центральный проход'),
    CorridorSegment(1, Offset(2173 / 7016, 2406 / 4960), Offset(2177 / 7016, 3315 / 4960), 'Проход около столовой'),
    CorridorSegment(1, Offset(2177 / 7016, 3315 / 4960), Offset(3537 / 7016, 3311 / 4960), 'Длинное бирюзовое крыло'),
    CorridorSegment(1, Offset(3537 / 7016, 3311 / 4960), Offset(3537 / 7016, 4345 / 4960), 'Короткое бирюзовое крыло'),
    CorridorSegment(1, Offset(3533 / 7016, 3445 / 4960), Offset(4321 / 7016, 3441 / 4960), 'Междисциплинарный инженерный цех'),

    // 2 floor
    CorridorSegment(2, Offset(573 / 7016, 930 / 4960), Offset(573 / 7016, 2418 / 4960), 'Длинное зеленое крыло'),
    CorridorSegment(2, Offset(573 / 7016, 1383 / 4960), Offset(665 / 7016, 1387 / 4960), 'короткий подход к лестнице около 224', hidden: true),
    CorridorSegment(2, Offset(357 / 7016, 2410 / 4960), Offset(1081 / 7016, 2402 / 4960), 'Короткое зеленое крыло'),
    CorridorSegment(2, Offset(2861 / 7016, 975 / 4960), Offset(2845 / 7016, 2414 / 4960), 'Длинное фиолетовое крыло'),
    CorridorSegment(2, Offset(2845 / 7016, 2414 / 4960), Offset(2229 / 7016, 2402 / 4960), 'Короткое фиолетовое крыло'),
    CorridorSegment(2, Offset(2833 / 7016, 1367 / 4960), Offset(2929 / 7016, 1367 / 4960), 'короткий подход к лестнице около 208', hidden: true),
    CorridorSegment(2, Offset(1081 / 7016, 2391 / 4960), Offset(1253 / 7016, 2391 / 4960), 'маленький отрезок из зеленого крыла', hidden: true),
    CorridorSegment(2, Offset(1257 / 7016, 2380 / 4960), Offset(1257 / 7016, 2604 / 4960), 'перпендикулярный к актовому залу', hidden: true),
    CorridorSegment(2, Offset(1257 / 7016, 2604 / 4960), Offset(2161 / 7016, 2592 / 4960), 'Длинное синее крыло'),
    CorridorSegment(2, Offset(2229 / 7016, 2392 / 4960), Offset(2093 / 7016, 2396 / 4960), 'отрезок из фиолетового', hidden: true),
    CorridorSegment(2, Offset(2093 / 7016, 2396 / 4960), Offset(2101 / 7016, 2600 / 4960), 'перпендикулярный к актовому залу', hidden: true),
    CorridorSegment(2, Offset(2101 / 7016, 2600 / 4960), Offset(2165 / 7016, 2579 / 4960), 'Соединение синего и фиолетового коридоров', hidden: true),
    CorridorSegment(2, Offset(2165 / 7016, 2579 / 4960), Offset(2157 / 7016, 3467 / 4960), 'Короткое синее крыло'),
    CorridorSegment(2, Offset(2157 / 7016, 3467 / 4960), Offset(2173 / 7016, 3319 / 4960), 'Переход из синего в бирюзовое крыло', hidden: true),
    CorridorSegment(2, Offset(2173 / 7016, 3319 / 4960), Offset(2701 / 7016, 3311 / 4960), 'Короткое бирюзовое крыло'),
    CorridorSegment(2, Offset(2701 / 7016, 3311 / 4960), Offset(2713 / 7016, 3431 / 4960), 'Переход в длинное бирюзовое крыло', hidden: true),
    CorridorSegment(2, Offset(2713 / 7016, 3431 / 4960), Offset(3557 / 7016, 3431 / 4960), 'Длинное бирюзовое крыло'),
    // Удалён ложный проход вдоль спортзала: от кабинета 215 маршрут идёт только через коридор к кампусу.
    CorridorSegment(2, Offset(3213 / 7016, 3463 / 4960), Offset(3073 / 7016, 4099 / 4960), 'Среднее бирюзовое крыло'),
    // Join the campus-side branch to the main turquoise corridor; the endpoints
    // are 32 source-map pixels apart, outside the graph's 25 px snap tolerance.
    CorridorSegment(2, Offset(3213 / 7016, 3463 / 4960), Offset(3557 / 7016, 3431 / 4960), 'Соединение основного коридора с кампусным проходом', hidden: true),
    CorridorSegment(2, Offset(3073 / 7016, 4099 / 4960), Offset(3177 / 7016, 3939 / 4960), 'Соединение бирюзовых коридоров', hidden: true),
    CorridorSegment(2, Offset(3177 / 7016, 3939 / 4960), Offset(3537 / 7016, 4079 / 4960), 'Коридор к спальному корпусу'),
    CorridorSegment(2, Offset(3537 / 7016, 4079 / 4960), Offset(3500 / 7016, 4297 / 4960), 'Подход к кабинету 215', hidden: true),
    CorridorSegment(2, Offset(1771 / 7016, 3406 / 4960), Offset(2055 / 7016, 3494 / 4960), 'Коридор у кабинета 218', hidden: true),
    CorridorSegment(2, Offset(2055 / 7016, 3494 / 4960), Offset(2285 / 7016, 3600 / 4960), 'Коридор у кабинетов 217–216', hidden: true),
    CorridorSegment(2, Offset(2285 / 7016, 3600 / 4960), Offset(2165 / 7016, 3467 / 4960), 'Выход из локального коридора', hidden: true),

    // 3 floor
    CorridorSegment(3, Offset(585 / 7016, 921 / 4960), Offset(585 / 7016, 2429 / 4960), 'Длинный зелёный коридор'),
    CorridorSegment(3, Offset(325 / 7016, 2429 / 4960), Offset(1069 / 7016, 2429 / 4960), 'Короткий зелёный коридор'),
    CorridorSegment(3, Offset(2877 / 7016, 909 / 4960), Offset(2877 / 7016, 2417 / 4960), 'Длинный фиолетовый коридор'),
    CorridorSegment(3, Offset(2965 / 7016, 2417 / 4960), Offset(2229 / 7016, 2417 / 4960), 'Короткий фиолетовый коридор'),
    CorridorSegment(3, Offset(2845 / 7016, 2414 / 4960), Offset(2229 / 7016, 2402 / 4960), 'Короткое фиолетовое крыло'),
    CorridorSegment(3, Offset(2833 / 7016, 1367 / 4960), Offset(2929 / 7016, 1367 / 4960), 'фиолетовый', hidden: true),
    CorridorSegment(3, Offset(1081 / 7016, 2391 / 4960), Offset(1253 / 7016, 2391 / 4960), 'маленький голубой проход', hidden: true),
    CorridorSegment(3, Offset(1257 / 7016, 2380 / 4960), Offset(1257 / 7016, 2704 / 4960), 'перпендикулярный проход', hidden: true),
    CorridorSegment(3, Offset(1257 / 7016, 2704 / 4960), Offset(2161 / 7016, 2713 / 4960), 'Длинное синее крыло'),
    CorridorSegment(3, Offset(2229 / 7016, 2392 / 4960), Offset(2093 / 7016, 2430 / 4960), 'отрезок из фиолетового', hidden: true),
    CorridorSegment(3, Offset(2093 / 7016, 2430 / 4960), Offset(2165 / 7016, 2697 / 4960), 'перпендикулярный проход', hidden: true),
    CorridorSegment(3, Offset(2285 / 7016, 3540 / 4960), Offset(2157 / 7016, 3467 / 4960), 'Соединение локального коридора с синим крылом', hidden: true),
    CorridorSegment(3, Offset(2165 / 7016, 2697 / 4960), Offset(2157 / 7016, 3467 / 4960), 'Короткое синее крыло'),
    CorridorSegment(3, Offset(2157 / 7016, 3467 / 4960), Offset(2173 / 7016, 3319 / 4960), 'Переход из синего в бирюзовое крыло', hidden: true),
    CorridorSegment(3, Offset(2173 / 7016, 3319 / 4960), Offset(2701 / 7016, 3311 / 4960), 'Короткое бирюзовое крыло'),
    CorridorSegment(3, Offset(2701 / 7016, 3311 / 4960), Offset(2713 / 7016, 3517 / 4960), 'Переход в длинное бирюзовое крыло', hidden: true),
    CorridorSegment(3, Offset(2713 / 7016, 3517 / 4960), Offset(3557 / 7016, 3517 / 4960), 'Длинное бирюзовое крыло'),
    CorridorSegment(3, Offset(3557 / 7016, 3517 / 4960), Offset(2813 / 7016, 3517 / 4960), 'Подход к Информационно-библиотечному центру'),
    CorridorSegment(3, Offset(1881 / 7016, 3292 / 4960), Offset(1913 / 7016, 3448 / 4960), 'Коридор у кабинета 318', hidden: true),
    CorridorSegment(3, Offset(1913 / 7016, 3448 / 4960), Offset(2285 / 7016, 3540 / 4960), 'Коридор у кабинетов 317–316', hidden: true),
    CorridorSegment(3, Offset(2125 / 7016, 3540 / 4960), Offset(2285 / 7016, 3388 / 4960), 'Коридор у кабинетов 316–315', hidden: true),
    CorridorSegment(3, Offset(2285 / 7016, 3388 / 4960), Offset(2157 / 7016, 3467 / 4960), 'Выход в короткое синее крыло', hidden: true),
  ];
}
