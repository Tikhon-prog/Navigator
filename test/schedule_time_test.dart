import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/schedule_time.dart';

void main() {
  test('compares non-padded lesson hours numerically', () {
    final values = ['10:00 - 10:40', '9:00 - 9:40', '08:30 - 09:10']
      ..sort(compareLessonTimes);
    expect(values, [
      '08:30 - 09:10',
      '9:00 - 9:40',
      '10:00 - 10:40',
    ]);
  });

  test('accepts common separators and normalizes a complete range', () {
    expect(normalizeLessonTimeRange('9:05–9:45'), '09:05 - 09:45');
    expect(normalizeLessonTimeRange('09:05 — 09:45'), '09:05 - 09:45');
    expect(normalizeLessonTimeRange('09:05 - 09:45'), '09:05 - 09:45');
  });

  test('normalizes single online start times and canonical slot keys', () {
    expect(normalizeLessonTime('9:05'), '09:05');
    expect(normalizeLessonTime('09:05'), '09:05');
    expect(normalizeLessonTime('9:05 - 9:45'), '09:05 - 09:45');
    expect(canonicalLessonTimeKey('9:05 - 9:45'), '09:05 - 09:45');
    expect(normalizeLessonTime('25:05'), isNull);
    expect(normalizeLessonTime('урок 3'), isNull);
  });

  test('rejects invalid and overnight lesson ranges', () {
    expect(normalizeLessonTimeRange('25:00 - 25:40'), isNull);
    expect(normalizeLessonTimeRange('09:70 - 10:10'), isNull);
    expect(normalizeLessonTimeRange('10:00 - 09:00'), isNull);
    expect(normalizeLessonTimeRange('урок 3'), isNull);
  });

  test('invalid values sort after valid timetable entries', () {
    expect(compareLessonTimes('09:00 - 09:40', 'урок 3'), lessThan(0));
  });
}
