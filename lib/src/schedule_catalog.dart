part of '../main.dart';

class SchoolScheduleCatalog {
  static const int _bundledScheduleRevision = 4;
  static const String _cacheKey = 'school_schedule_cache_v1';
  static const String _cacheRevisionKey = 'school_schedule_cache_revision_v1';
  static Map<String, dynamic>? _data;

  static Future<void> load() async {
    if (_data != null) return;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    final cachedRevision = prefs.getInt(_cacheRevisionKey) ?? 0;

    // Keep server-provided schedules for other classes, but never let an old
    // cache shadow a newer bundled override such as the 8В second-quarter data.
    if (cached != null && cachedRevision >= _bundledScheduleRevision) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map && decoded['classes'] is Map) {
          _data = Map<String, dynamic>.from(decoded);
          return;
        }
      } catch (error) { debugPrint('schedule_catalog: ${error.runtimeType}'); }
    }

    final raw = await rootBundle.loadString(
      'assets/data/school_schedule_2026-10-05.json',
    );
    final bundled = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final classes = Map<String, dynamic>.from(
      bundled['classes'] as Map? ?? const {},
    );
    final classOrder = <String, dynamic>{
      for (final entry in (bundled['class_order'] as Map? ?? const {}).entries)
        entry.key.toString(): List<String>.from(entry.value as List),
    };

    if (cached != null) {
      try {
        final cachedData = Map<String, dynamic>.from(jsonDecode(cached) as Map);
        final cachedClasses = cachedData['classes'] as Map? ?? const {};
        for (final entry in cachedClasses.entries) {
          final cachedName = entry.key.toString();
          final isBundledOverride = classes.entries.any((bundledEntry) {
            final value = bundledEntry.value;
            return _normalizeClassName(bundledEntry.key.toString()) ==
                    _normalizeClassName(cachedName) &&
                value is Map &&
                value['local_override'] == true;
          });
          if (!isBundledOverride) classes[cachedName] = entry.value;
        }

        final cachedOrder = cachedData['class_order'] as Map? ?? const {};
        for (final entry in cachedOrder.entries) {
          final grade = entry.key.toString();
          final names = List<String>.from(
            classOrder[grade] as List? ?? const <String>[],
          );
          for (final name in (entry.value as List).whereType<String>()) {
            if (classes.containsKey(name) && !names.contains(name)) {
              names.add(name);
            }
          }
          classOrder[grade] = names;
        }
      } catch (_) {
        // A malformed legacy cache is ignored in favor of the bundled data.
      }
    }

    _data = {
      ...bundled,
      'classes': classes,
      'class_order': classOrder,
    };
    await prefs.setString(_cacheKey, jsonEncode(_data));
    await prefs.setInt(_cacheRevisionKey, _bundledScheduleRevision);
  }

  static Map<String, dynamic> _normalizedScheduleRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = entry.key.trim().toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '_')
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
    } catch (error) { debugPrint('schedule_catalog: ${error.runtimeType}'); }
    final variantsByClass = <String, List<Map<String, dynamic>>>{};
    for (final raw in rawRows) {
      if (raw is! Map) continue;
      final row = _normalizedScheduleRow(Map<String, dynamic>.from(raw));
      final classRef = _rowText(row, ['class_id', 'class', 'класс_id']);
      final classLabel = _rowText(row, ['class_name', 'class_label', 'class_display_name', 'класс']);
      final className = classLabel.isNotEmpty ? classLabel : (classNames[classRef] ?? classRef);
      final subject = _rowText(row, ['subject', 'subject_name', 'discipline', 'discipline_name', 'lesson', 'предмет', 'дисциплина']);
      final day = _rowDay(_rowText(row, ['day', 'weekday', 'day_of_week', 'день', 'день_недели']));
      final rawTime = _rowText(row, ['time', 'lesson_time', 'time_slot', 'start_time', 'lesson_start', 'время', 'время_урока', 'время_начала', 'время_начала_урока']);
      final time = normalizeLessonTime(rawTime);
      if (className.isEmpty || subject.isEmpty || day == null || time == null) continue;
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
      final hasBundledOverride = classes.entries.any((existing) {
        final value = existing.value;
        return _normalizeClassName(existing.key.toString()) ==
                _normalizeClassName(entry.key) &&
            value is Map &&
            value['local_override'] == true;
      });
      if (hasBundledOverride) continue;

      classes[entry.key] = {'variants': entry.value};
      final grade = RegExp(r'^\d+').firstMatch(entry.key)?.group(0) ?? 'Другие';
      final list = List<String>.from(classOrder[grade] as List? ?? const <String>[]);
      if (!list.contains(entry.key)) list.add(entry.key);
      list.sort();
      classOrder[grade] = list;
    }
    _data = {...baseData, 'classes': classes, 'class_order': classOrder};
    await prefs.setString(_cacheKey, jsonEncode(_data));
    await prefs.setInt(_cacheRevisionKey, _bundledScheduleRevision);
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

  static Map<String, dynamic>? classDetails(String className) {
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
    return classData is Map ? Map<String, dynamic>.from(classData) : null;
  }

  static String periodForClass(String className) =>
      (classDetails(className)?['period'] ?? '').toString().trim();

  static List<Map<String, dynamic>> variants(String className) {
    final raw = classDetails(className)?['variants'];
    return raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }
  static String? clockRangeForLessonRange(
    String className, int day, int firstLesson, int lastLesson,
  ) {
    if (className.trim().isEmpty || day < 1 || day > 6 ||
        firstLesson < 1 || lastLesson < firstLesson) return null;
    final slots = variants(className)
        .where((row) => (int.tryParse('${row['day']}') ?? 0) == day)
        .where((row) => baseSubject('${row['subject'] ?? ''}').toLowerCase() != 'обед')
        .map((row) => '${row['time'] ?? ''}'.trim())
        .where((value) => normalizeLessonTimeRange(value) != null)
        .toSet()
        .toList()
      ..sort(compareLessonTimes);
    if (lastLesson > slots.length) return null;
    final start = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(slots[firstLesson - 1]);
    final end = RegExp(r'[-–—]\s*(\d{1,2}:\d{2})').firstMatch(slots[lastLesson - 1]);
    if (start == null || end == null) return null;
    return '${start.group(1)}–${end.group(1)}';
  }

  static String baseSubject(String value) {
    var subject = value.trim();
    subject = subject.replaceFirst(RegExp(r'\s+[А-ЯЁ][А-Яа-яЁё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.(?:,\s*[А-ЯЁ][А-Яа-яЁё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.)?,?$'), '');
    return subject.trim().replaceFirst(RegExp(r',$'), '').trim();
  }
  static RegExp get _teacherSuffix => RegExp(
        r'\s+([А-ЯЁ][А-Яа-яЁё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.(?:,\s*[А-ЯЁ][А-Яа-яЁё-]+\s+[А-ЯЁ]\.[А-ЯЁ]\.)?)\s*$',
      );
  static String teacherFromSubject(String value) =>
      _teacherSuffix.firstMatch(value.trim())?.group(1)?.trim() ?? '';

  static const String _choiceSeparator = ' / ';

  /// День|время → предмет → группы (только реальные подгруппы, group > 0).
  static Map<String, Map<String, Set<int>>> _slotIndex(String className) {
    final slots = <String, Map<String, Set<int>>>{};
    for (final e in variants(className)) {
      final subject = baseSubject('${e['subject'] ?? ''}');
      if (subject.isEmpty) continue;
      final group = int.tryParse('${e['group']}') ?? 1;
      if (group <= 0) continue;
      final day = int.tryParse('${e['day']}') ?? 1;
      final slot = '$day|${canonicalLessonTimeKey('${e['time'] ?? ''}')}';
      ((slots[slot] ??= <String, Set<int>>{})[subject] ??= <int>{}).add(group);
    }
    return slots;
  }

  /// Ключ выбора группы для временного слота. Если в слоте одновременно идут
  /// разные подгруппы одного предмета — ключ это название предмета. Если
  /// параллельно идут разные предметы (например, «Великие достижения» и
  /// «Введение в ИИ») — названия через « / ». Слот без подгрупп даёт null.
  static String? _choiceKey(Map<String, Set<int>> slot) {
    final groups = <int>{for (final value in slot.values) ...value};
    if (groups.length < 2) return null;
    return (slot.keys.toList()..sort()).join(_choiceSeparator);
  }

  /// Варианты групп для каждого выбора, где в одном и том же временном слоте
  /// реально присутствуют разные группы. Группа выбирается отдельно для
  /// каждого предмета (или набора параллельных предметов).
  static Map<String, Set<int>> subjectGroups(String className) {
    final result = <String, Set<int>>{};
    for (final slot in _slotIndex(className).values) {
      final key = _choiceKey(slot);
      if (key == null) continue;
      (result[key] ??= <int>{}).addAll({for (final value in slot.values) ...value});
    }
    return result;
  }

  static Set<String> splitSubjects(String className) =>
      subjectGroups(className).keys.toSet();

  /// Подпись для выбора группы: номер подгруппы и преподаватель. Для набора
  /// параллельных предметов вместо преподавателя показывается «предмет (педагог)».
  static String subgroupLabel(String className, String subject, int group) {
    final members = subject.split(_choiceSeparator).map((e) => e.trim()).toSet();
    final parallel = members.length > 1;
    final parts = <String>{};
    for (final row in variants(className)) {
      final rowSubject = baseSubject('${row['subject'] ?? ''}');
      if (!members.contains(rowSubject)) continue;
      if ((int.tryParse('${row['group']}') ?? 1) != group) continue;
      final stored = '${row['teacher'] ?? ''}'.trim();
      final teacher = stored.isNotEmpty
          ? stored
          : teacherFromSubject('${row['subject'] ?? ''}');
      if (parallel) {
        parts.add(teacher.isEmpty ? rowSubject : '$rowSubject ($teacher)');
      } else if (teacher.isNotEmpty) {
        parts.add(teacher);
      }
    }
    final sorted = parts.toList()..sort();
    return sorted.isEmpty
        ? 'Подгруппа $group'
        : 'Подгруппа $group • ${sorted.join(' / ')}';
  }

  /// Заголовок выбора в диалоге групп.
  static String choiceTitle(String key) =>
      key.contains(_choiceSeparator) ? 'Параллельно: $key' : key;

  static bool isMathSubject(String subject) {
    final value = subject.toLowerCase();
    // «Практикум по алгебре/геометрии/математике» и «Наглядная геометрия» —
    // самостоятельные предметы, а не уроки основной математики.
    if (value.contains('практикум') || value.contains('наглядн')) return false;
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
    final slotIndex = _slotIndex(className);
    final choiceBySlot = <String, String?>{
      for (final entry in slotIndex.entries) entry.key: _choiceKey(entry.value),
    };

    for (final row in all) {
      final rowSubject = baseSubject('${row['subject'] ?? ''}');
      if (rowSubject.isEmpty || !isMathSubject(rowSubject)) continue;
      final rowDay = int.tryParse('${row['day']}') ?? 1;
      final rowTime = canonicalLessonTimeKey('${row['time'] ?? ''}');
      final slots = mathSlots.putIfAbsent(rowDay, () => <String>[]);
      if (!slots.contains(rowTime)) slots.add(rowTime);
    }
    for (final slots in mathSlots.values) {
      slots.sort(compareLessonTimes);
    }

    for (final e in all) {
      final rawSubject = '${e['subject'] ?? ''}'.trim();
      final subject = baseSubject(rawSubject);
      if (subject.isEmpty) continue;
      final group = int.tryParse('${e['group']}') ?? 1;
      final day = int.tryParse('${e['day']}') ?? 1;
      final time = '${e['time'] ?? ''}'.trim();
      var displayGroup = 0;

      if (group > 0) {
        final slotId = '$day|${canonicalLessonTimeKey(time)}';
        final choice = choiceBySlot[slotId];
        final slotMap = slotIndex[slotId];
        // Одинокий урок с пометкой группы (без параллельной подгруппы) идёт
        // всему классу. Если же в слоте есть выбор — берём выбранную группу,
        // а если такой группы в слоте нет, то первую из имеющихся.
        if (choice != null && slotMap != null) {
          final slotGroups = <int>{for (final value in slotMap.values) ...value};
          final wanted = selected[choice] ?? 1;
          final effective = slotGroups.contains(wanted)
              ? wanted
              : (slotGroups.toList()..sort()).first;
          if (group != effective) continue;
          displayGroup = group;
        }
      }

      var displaySubject = subject;
      if (isMathSubject(subject)) {
        final slots = mathSlots[day] ?? const <String>[];
        final ordinal = slots.indexOf(canonicalLessonTimeKey(time));
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
        teacher: teacher, group: displayGroup,
      ));
    }
    result.sort((a, b) => a.day != b.day
        ? a.day.compareTo(b.day)
        : compareLessonTimes(a.time, b.time));
    return result;
  }
}
