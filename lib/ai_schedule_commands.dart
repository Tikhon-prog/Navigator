/// Deterministic validation for natural-language math timetable edits.
///
/// The language model may help understand a message, but schedule changes are
/// never applied from model output alone. Every slot is validated against the
/// real number of mathematics lessons and confirmed by the user.
class AiMathSlot {
  final int day;
  final int slot;

  const AiMathSlot(this.day, this.slot);

  @override
  bool operator ==(Object other) =>
      other is AiMathSlot && other.day == day && other.slot == slot;

  @override
  int get hashCode => Object.hash(day, slot);
}

class AiMathScheduleDraft {
  final Map<int, List<String?>> assignments;
  final List<AiMathSlot> missingSlots;
  final List<String> errors;

  AiMathScheduleDraft({
    required this.assignments,
    required this.missingSlots,
    this.errors = const [],
  });

  bool get isComplete => missingSlots.isEmpty && errors.isEmpty;

  String? fillNext(String text) {
    if (missingSlots.isEmpty) return null;
    final subject = AiMathScheduleParser.subjectFromText(text);
    if (subject == null) return null;
    final slot = missingSlots.removeAt(0);
    final daySlots = assignments[slot.day];
    if (daySlots == null || slot.slot >= daySlots.length) return null;
    daySlots[slot.slot] = subject;
    return subject;
  }

  Map<int, List<String>> get completedAssignments => {
        for (final entry in assignments.entries)
          if (entry.value.every((value) => value != null))
            entry.key: entry.value.cast<String>(),
      };

  String preview() {
    const dayNames = {
      1: 'понедельник',
      2: 'вторник',
      3: 'среду',
      4: 'четверг',
      5: 'пятницу',
      6: 'субботу',
    };
    return assignments.entries
        .map((entry) {
          final subjects = entry.value
              .asMap()
              .entries
              .map((slot) =>
                  '${slot.key + 1}-й: ${slot.value ?? 'не выбрано'}')
              .join(', ');
          return 'Во ${dayNames[entry.key] ?? 'день ${entry.key}'}: $subjects';
        })
        .join('\n');
  }
}

class AiMathScheduleParser {
  static const _dayNumbers = <String, int>{
    'понедельник': 1,
    'понедельника': 1,
    'пн': 1,
    'вторник': 2,
    'вторника': 2,
    'вт': 2,
    'среда': 3,
    'среду': 3,
    'среды': 3,
    'ср': 3,
    'четверг': 4,
    'четверга': 4,
    'чт': 4,
    'пятница': 5,
    'пятницу': 5,
    'пятницы': 5,
    'пт': 5,
    'суббота': 6,
    'субботу': 6,
    'субботы': 6,
    'сб': 6,
  };

  static final RegExp _dayPattern = RegExp(
    r'(?<![А-Яа-яЁё])(понедельника?|пн|вторника?|вт|сред[ауые]?|ср|четверга?|чт|пятниц[ауые]?|пт|суббот[ауые]?|сб)(?![А-Яа-яЁё])',
    caseSensitive: false,
  );

  static final List<({RegExp pattern, String name})> _subjects = [
    (
      pattern: RegExp(
        r'(?<![А-Яа-яЁё])геом(?:етрия|етрию|етрии|етр|а)?(?![А-Яа-яЁё])',
        caseSensitive: false,
      ),
      name: 'Геометрия',
    ),
    (
      pattern: RegExp(
        r'(?<![А-Яа-яЁё])алгебр(?:а|у|ы|е|ой)?(?![А-Яа-яЁё])',
        caseSensitive: false,
      ),
      name: 'Алгебра',
    ),
    (
      pattern: RegExp(
        r'(?<![А-Яа-яЁё])(?:ви\s*с|вероятност[а-яё]*|статистик[а-яё]*)(?![А-Яа-яЁё])',
        caseSensitive: false,
      ),
      name: 'Вероятность и статистика',
    ),
  ];

  static int? dayNumber(String raw) {
    final normalized = raw.toLowerCase().replaceAll('ё', 'е').trim();
    return _dayNumbers[normalized];
  }

  static String? subjectFromText(String text) {
    final matches = <({int start, String name})>[];
    for (final subject in _subjects) {
      for (final match in subject.pattern.allMatches(text)) {
        matches.add((start: match.start, name: subject.name));
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches.first.name;
  }

  static List<String> _subjectsIn(String text) {
    final matches = <({int start, String name})>[];
    for (final subject in _subjects) {
      for (final match in subject.pattern.allMatches(text)) {
        matches.add((start: match.start, name: subject.name));
      }
    }
    matches.sort((a, b) => a.start.compareTo(b.start));
    final result = <String>[];
    for (final match in matches) {
      if (result.isEmpty || result.last != match.name) result.add(match.name);
    }
    return result;
  }

  /// Returns null when the text does not contain a day-based timetable command.
  static AiMathScheduleDraft? parse(
    String text, {
    required Map<int, int> mathSlotsByDay,
  }) {
    final dayMatches = _dayPattern.allMatches(text).toList();
    if (dayMatches.isEmpty) return null;

    final assignments = <int, List<String?>>{};
    final missing = <AiMathSlot>[];
    final errors = <String>[];

    for (var i = 0; i < dayMatches.length; i++) {
      final match = dayMatches[i];
      final day = dayNumber(match.group(0) ?? '');
      if (day == null) continue;
      final end = i + 1 < dayMatches.length
          ? dayMatches[i + 1].start
          : text.length;
      final segment = text.substring(match.end, end);
      final subjects = _subjectsIn(segment);
      final count = mathSlotsByDay[day] ?? 0;

      if (count == 0) {
        errors.add('В ${_dayLabel(day)} по загруженному расписанию нет уроков математики.');
        continue;
      }
      if (subjects.isEmpty) {
        errors.add('Не понял, какой математический предмет поставить на ${_dayLabel(day)}.');
        continue;
      }
      if (subjects.length > count) {
        errors.add(
          'На ${_dayLabel(day)} найдено ${subjects.length} предмета, но математических уроков только $count.',
        );
        continue;
      }

      // One named subject means every mathematics slot on that day.
      final values = subjects.length == 1
          ? List<String?>.filled(count, subjects.single)
          : <String?>[
              ...subjects,
              ...List<String?>.filled(count - subjects.length, null),
            ];
      assignments[day] = values;
      for (var slot = 0; slot < values.length; slot++) {
        if (values[slot] == null) missing.add(AiMathSlot(day, slot));
      }
    }

    if (assignments.isEmpty && errors.isEmpty) return null;
    return AiMathScheduleDraft(
      assignments: assignments,
      missingSlots: missing,
      errors: errors,
    );
  }

  static String _dayLabel(int day) => switch (day) {
        1 => 'понедельник',
        2 => 'вторник',
        3 => 'среду',
        4 => 'четверг',
        5 => 'пятницу',
        6 => 'субботу',
        _ => 'день $day',
      };
}
