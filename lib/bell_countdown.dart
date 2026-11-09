/// Derives a live lesson/break countdown from the selected day's lesson intervals.
class SchoolBellCountdown {
  static final RegExp _rangePattern = RegExp(
    r'(\d{1,2}):(\d{2})\s*[-–—]\s*(\d{1,2}):(\d{2})',
  );

  static String? describe({
    required int selectedDay,
    required DateTime now,
    required List<({String time, String subject})> lessons,
  }) {
    if (selectedDay < 1 || selectedDay > 6 || selectedDay != now.weekday) {
      return null;
    }

    final parsed = <({DateTime start, DateTime end, String subject})>[];
    for (final lesson in lessons) {
      final match = _rangePattern.firstMatch(lesson.time);
      if (match == null) continue;
      final startHour = int.parse(match.group(1)!);
      final startMinute = int.parse(match.group(2)!);
      final endHour = int.parse(match.group(3)!);
      final endMinute = int.parse(match.group(4)!);
      if (startHour > 23 || endHour > 23 || startMinute > 59 || endMinute > 59) {
        continue;
      }
      final start = DateTime(now.year, now.month, now.day, startHour, startMinute);
      final end = DateTime(now.year, now.month, now.day, endHour, endMinute);
      if (!end.isAfter(start)) continue;
      parsed.add((
        start: start,
        end: end,
        subject: lesson.subject.trim().isEmpty ? 'Урок' : lesson.subject.trim(),
      ));
    }

    if (parsed.isEmpty) return null;
    parsed.sort((a, b) => a.start.compareTo(b.start));

    var completedLesson = false;
    for (final lesson in parsed) {
      if (now.isBefore(lesson.start)) {
        final label = completedLesson ? 'До урока' : 'До первого урока';
        return '$label: ${_remaining(lesson.start.difference(now))} • '
            '${lesson.subject} в ${_clock(lesson.start)}';
      }
      if (now.isBefore(lesson.end)) {
        return 'До перемены: ${_remaining(lesson.end.difference(now))} • '
            '${lesson.subject} закончится в ${_clock(lesson.end)}';
      }
      completedLesson = true;
    }

    return 'Уроки на сегодня закончились';
  }

  static String _remaining(Duration remaining) {
    final totalSeconds = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) return '$hours ч $minutes мин';
    if (minutes == 0) return '$seconds сек';
    return '$minutes мин ${seconds.toString().padLeft(2, '0')} сек';
  }

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
