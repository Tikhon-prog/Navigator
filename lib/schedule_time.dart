/// Shared parsing and ordering helpers for timetable time strings.
///
/// Accepts both zero-padded and non-padded hours, and full ranges such as
/// "08:30 - 09:10". Invalid values sort after valid lesson times.
int? lessonStartMinute(String value) {
  final match = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(value);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// Compares lesson ranges by their actual start time rather than lexically.
///
/// For equal start times, the original value is used as a stable tie-breaker.
int compareLessonTimes(String left, String right) {
  final leftMinute = lessonStartMinute(left);
  final rightMinute = lessonStartMinute(right);
  if (leftMinute == null) {
    return rightMinute == null ? left.compareTo(right) : 1;
  }
  if (rightMinute == null) return -1;
  final byMinute = leftMinute.compareTo(rightMinute);
  return byMinute != 0 ? byMinute : left.compareTo(right);
}

/// Normalizes a full time range or a single start time.
///
/// Single start times are accepted because some online schedule APIs provide
/// only the lesson start. Complete ranges are preferred for bell countdowns.
String? normalizeLessonTime(String value) {
  final range = normalizeLessonTimeRange(value);
  if (range != null) return range;

  final match = RegExp(r'^\\s*(\\d{1,2}):(\\d{2})\\s*
  final match = RegExp(
    r'^\s*(\d{1,2}):(\d{2})\s*[-–—]\s*(\d{1,2}):(\d{2})\s*$',
  ).firstMatch(value);
  if (match == null) return null;

  final startHour = int.tryParse(match.group(1) ?? '');
  final startMinute = int.tryParse(match.group(2) ?? '');
  final endHour = int.tryParse(match.group(3) ?? '');
  final endMinute = int.tryParse(match.group(4) ?? '');
  if (startHour == null || startMinute == null ||
      endHour == null || endMinute == null ||
      startHour > 23 || endHour > 23 ||
      startMinute > 59 || endMinute > 59) {
    return null;
  }
  final start = startHour * 60 + startMinute;
  final end = endHour * 60 + endMinute;
  if (end <= start) return null;

  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(startHour)}:${two(startMinute)} - '
      '${two(endHour)}:${two(endMinute)}';
}
).firstMatch(value);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// A stable slot key so "9:00 - 9:40" and "09:00 - 09:40" are equivalent.
String canonicalLessonTimeKey(String value) =>
    normalizeLessonTime(value) ?? value.trim();

/// Normalizes common lesson-range formats to HH:mm - HH:mm.
///
/// Returns null when the input is not a valid complete range.
String? normalizeLessonTimeRange(String value) {
  final match = RegExp(
    r'^\s*(\d{1,2}):(\d{2})\s*[-–—]\s*(\d{1,2}):(\d{2})\s*$',
  ).firstMatch(value);
  if (match == null) return null;

  final startHour = int.tryParse(match.group(1) ?? '');
  final startMinute = int.tryParse(match.group(2) ?? '');
  final endHour = int.tryParse(match.group(3) ?? '');
  final endMinute = int.tryParse(match.group(4) ?? '');
  if (startHour == null || startMinute == null ||
      endHour == null || endMinute == null ||
      startHour > 23 || endHour > 23 ||
      startMinute > 59 || endMinute > 59) {
    return null;
  }
  final start = startHour * 60 + startMinute;
  final end = endHour * 60 + endMinute;
  if (end <= start) return null;

  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(startHour)}:${two(startMinute)} - '
      '${two(endHour)}:${two(endMinute)}';
}
