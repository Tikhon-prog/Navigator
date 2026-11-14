part of '../main.dart';

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
      fontFamily: 'Inter',
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
        titleTextStyle: TextStyle(fontFamily: 'Inter', color: colors.onSurface, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.35),
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
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _PokoleniePageTransitionsBuilder(),
          TargetPlatform.iOS: _PokoleniePageTransitionsBuilder(),
          TargetPlatform.linux: _PokoleniePageTransitionsBuilder(),
          TargetPlatform.macOS: _PokoleniePageTransitionsBuilder(),
          TargetPlatform.windows: _PokoleniePageTransitionsBuilder(),
          TargetPlatform.fuchsia: _PokoleniePageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: TextStyle(fontFamily: 'Inter', color: colors.onSurface, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      chipTheme: ChipThemeData(
        side: border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
  bool _mentorMenuAllowed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshMentorMenuAccess());
  }

  Future<void> _refreshMentorMenuAccess() async {
    final allowed = await MentorMenteesPage.canAccessForCurrentUser();
    if (mounted && allowed != _mentorMenuAllowed) {
      setState(() => _mentorMenuAllowed = allowed);
    }
  }

  Future<void> _openMentorMentees() async {
    key.currentState?.closeDrawer();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MentorMenteesPage()),
    );
  }

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
      final storedWholeClassGroup = SchoolScheduleCatalog.usesWholeClassSubgroup(className)
          ? prefs.getInt(
              _studentScopedPreferenceKey(prefs, 'student_class_group_8В'),
            )
          : null;
      final wholeClassGroup =
          storedWholeClassGroup == 1 || storedWholeClassGroup == 2
              ? storedWholeClassGroup
              : null;

      if (SchoolScheduleCatalog.usesWholeClassSubgroup(className) &&
          wholeClassGroup == null) {
        contextLines.add(
          'Подгруппа 8В ещё не выбрана. Попроси ученика выбрать 8В/1 или 8В/2 в разделе «Расписание»; не показывай расписание обеих подгрупп одновременно.',
        );
      } else {
        final lessons = SchoolScheduleCatalog.buildPersonal(
          className,
          groups,
          mathNamesByDay: mathNamesByDay,
          wholeClassGroup: wholeClassGroup,
        ).where((lesson) => selectedWeekdays.contains(lesson.day)).toList()
          ..sort((a, b) {
            final dayOrder = a.day.compareTo(b.day);
            return dayOrder != 0
                ? dayOrder
                : compareLessonTimes(a.time, b.time);
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
              if (lesson.group > 0) 'группа ${lesson.group}',
              if (lesson.room.isNotEmpty) 'кабинет ${lesson.room}',
              if (lesson.teacher.isNotEmpty) 'педагог ${lesson.teacher}',
            ];
            contextLines.add('- ${details.join(' • ')}');
          }
        }
        if (lessons.isEmpty) {
          contextLines.add('Для выбранного периода занятий по этому классу не найдено.');
        }
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

  Future<void> _openAiSchoolRoute(String destinationId, String? originId) async {
    final destination = SchoolData.tryRoom(destinationId);
    if (destination == null || !mounted) return;
    final startRoom = originId == null || originId.isEmpty
        ? null
        : SchoolData.tryRoom(originId);
    if (originId != null && originId.isNotEmpty && startRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Точка старта маршрута больше не найдена.')),
      );
      return;
    }
    final route = RouteEngine.build(
      destination.id,
      startFloor: startRoom?.floor ?? 1,
      startLocationId: startRoom?.id,
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
          const placeAliases = <String, String>{
            'библиотек': 'place_library',
            'столов': 'place_canteen',
            'бассейн': 'place_pool',
            'спортзал': 'place_sport',
            'тренажер': 'place_gym',
            'тренажёр': 'place_gym',
            'хореограф': 'place_choreo',
            'актов': 'place_auditorium',
            'террас': 'place_terrace',
            'дрон': 'place_drone',
            'инженер': 'place_engineering',
          };
          for (final alias in placeAliases.entries) {
            if (query.contains(alias.key)) {
              final aliased = SchoolData.tryRoom(alias.value);
              if (aliased != null) return aliased;
            }
          }
          final numeric = RegExp(r'(?<!\d)(\d{3}(?:\.\d+)?)(?!\d)')
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
        var startFloor = (prefs.getInt('map_start_floor') ?? 1).clamp(1, 3).toInt();
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
            : (SchoolData.tryRoom(originId) == null ? originId : SchoolData.title(SchoolData.tryRoom(originId)!));
        final summary = StringBuffer()
          ..writeln('Маршрут построен по графу коридоров школы.')
          ..writeln('Откуда: $originLabel.')
          ..writeln('Куда: ${SchoolData.title(destination)}, этаж ${destination.floor}.')
          ..writeln('Шаги:')
          ..writeAll(steps.asMap().entries.map(
            (entry) => '${entry.key + 1}. ${entry.value.text} (${entry.value.floor}-й этаж)\n',
          ));
        return '__OPEN_ROUTE__:${destination.id}|${originId}\n$summary';

      case 'open_school_location':
        final locationId = arg('location_id');
        final room = SchoolData.tryRoom(locationId);
        if (room == null) return 'Такой точки нет в справочнике карты. Сначала найди её через search_school_map.';
        return '__OPEN_MAP__:${room.id}';

      case 'set_favorite_location':
        final locationId = arg('location_id');
        final room = SchoolData.tryRoom(locationId);
        if (room == null) return 'Не нашёл это помещение. Сначала найди его через поиск по карте.';
        final rawFavorite = arg('favorite').toLowerCase();
        final shouldFavorite = const {'true', 'yes', 'да', 'добавить', 'избранное'}.contains(rawFavorite);
        final shouldRemove = const {'false', 'no', 'нет', 'убрать', 'удалить'}.contains(rawFavorite);
        if (!shouldFavorite && !shouldRemove) {
          return 'Не понял действие. Напиши «добавить» или «убрать».';
        }
        final prefs = await SharedPreferences.getInstance();
        final favoriteIds = (prefs.getStringList('pokolenie_favorite_locations_v1') ?? const <String>[]).toSet();
        if (shouldFavorite) {
          favoriteIds.add(room.id);
        } else {
          favoriteIds.remove(room.id);
        }
        await prefs.setStringList('pokolenie_favorite_locations_v1', favoriteIds.toList()..sort());
        notifySchoolLocalDataChanged();
        return shouldFavorite
            ? '${SchoolData.title(room)} добавлено в избранное.'
            : '${SchoolData.title(room)} убрано из избранного.';

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
        notifySchoolLocalDataChanged();
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
        if (SchoolScheduleCatalog.usesWholeClassSubgroup(className)) {
          return 'В 8В выбирается общая подгруппа целиком. Открой раздел «Расписание» и выбери 8В/1 или 8В/2.';
        }
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
          return 'Для предмета «$subject» в классе $className нет группы №$group. Доступные группы: ${groups[actualSubject ?? subject]?.join(', ') ?? 'не найдены'}.';
        }
        await prefs.setInt(
          _studentScopedPreferenceKey(prefs, 'student_group_${className}_$actualSubject'),
          group,
        );
        notifySchoolLocalDataChanged();
        return 'Для предмета «$actualSubject» выбрана группа №$group.';

      case 'set_route_start':
        final floor = integer('floor');
        final locationId = arg('location_id');
        if (floor == null || floor < 1 || floor > 3) {
          return 'Этаж должен быть 1, 2 или 3.';
        }
        if (locationId.isEmpty && floor != 1) {
          return 'Главный вход находится на 1-м этаже. Чтобы начать со 2-го или 3-го, укажи конкретный кабинет или место.';
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
        notifySchoolLocalDataChanged();
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
        notifySchoolLocalDataChanged();
        return 'Заметка «${title.isEmpty ? 'Заметка' : title}» сохранена на этом устройстве.';

      default:
        return 'Неизвестное действие приложения: $action.';
    }
  }

  @override
  Widget build(BuildContext context) {
    void menu() {
      unawaited(_refreshMentorMenuAccess());
      key.currentState?.openDrawer();
    }
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
            Expanded(child: _AnimatedIndexedStack(index: index, children: pages)),
          ]);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
          ? NavigationBar(animationDuration: const Duration(milliseconds: 320), selectedIndex: index, onDestinationSelected: go, destinations: destinations)
          : null,
    );
  }

  Widget _drawer(BuildContext context){final c=Theme.of(context).colorScheme;final items=[(0,Icons.home_rounded,'Главное меню','Обзор'),(1,Icons.map_rounded,'Карта школы','Кабинеты и маршруты'),(2,Icons.calendar_month_rounded,'Расписание','Уроки и группы'),(3,Icons.auto_awesome_rounded,'ДОПы','Кружки и секции'),(4,Icons.settings_rounded,'Настройки','Профиль и кабинет'),(5,Icons.campaign_rounded,'Оповещения','Объявления школы'),(6,Icons.note_alt_rounded,'Мои заметки','Личные записи на устройстве'),(7,Icons.smart_toy_rounded,'ИИ-помощник','Локальный чат без облака'),if(_mentorMenuAllowed)(9,Icons.groups_rounded,'Мои подопечные','Локальный список наставника')];return Drawer(width: math.min(330, MediaQuery.sizeOf(context).width * .88).toDouble(),child:SafeArea(child:Column(children:[Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:50,height:50,decoration:BoxDecoration(gradient:LinearGradient(colors:AppPalette.gradient(widget.theme)),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.explore_rounded,color:Colors.white)),const SizedBox(width:12),const Expanded(child:Text('Поколение',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close_rounded))])),const Divider(height:1),Expanded(child:ListView(padding:const EdgeInsets.all(12),children:[for(final x in items)Card(color:index==x.$1?c.primaryContainer:null,child:ListTile(leading:Icon(x.$2,color:index==x.$1?c.primary:null),title:Text(x.$3,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(x.$4),onTap: () { if (x.$1 == 5) { _openAnnouncements(); } else if (x.$1 == 6) { _openNotes(); } else if (x.$1 == 7) { _openAiChat(); } else if (x.$1 == 9) { _openMentorMentees(); } else { go(x.$1); } }))]))])));}
}
class _PokoleniePageTransitionsBuilder extends PageTransitionsBuilder {
  const _PokoleniePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    Route<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.035, 0),
      end: Offset.zero,
    ).animate(curved);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

/// Keeps tab state alive while cross-fading and gently sliding between screens.
class _AnimatedIndexedStack extends StatelessWidget {
  const _AnimatedIndexedStack({
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != index,
              child: ExcludeSemantics(
                excluding: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  child: AnimatedSlide(
                    offset: i == index || reduceMotion ? Offset.zero : const Offset(.018, 0),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: TickerMode(
                      enabled: i == index,
                      child: children[i],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
