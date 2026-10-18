import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/bell_countdown.dart';

void main() {
  group('SchoolBellCountdown', () {
    final mondayLessons = <({String time, String subject})>[
      (time: '08:00 - 08:40', subject: 'Алгебра'),
      (time: '08:50 - 09:30', subject: 'Информатика'),
      (time: '09:40 - 10:20', subject: 'Физика'),
    ];

    test('counts down to the break while a lesson is in progress', () {
      final text = SchoolBellCountdown.describe(
        selectedDay: 1,
        now: DateTime(2026, 10, 19, 8, 20),
        lessons: mondayLessons,
      );
      expect(text, contains('До перемены: 20 мин 00 сек'));
      expect(text, contains('Алгебра'));
      expect(text, contains('08:40'));
    });

    test('during a break counts down to the next lesson', () {
      final text = SchoolBellCountdown.describe(
        selectedDay: 1,
        now: DateTime(2026, 10, 19, 8, 42),
        lessons: mondayLessons,
      );
      expect(text, contains('До урока: 8 мин 00 сек'));
      expect(text, contains('Информатика'));
      expect(text, contains('08:50'));
    });

    test('reports that lessons are over and ignores other weekdays', () {
      expect(
        SchoolBellCountdown.describe(
          selectedDay: 1,
          now: DateTime(2026, 10, 19, 11),
          lessons: mondayLessons,
        ),
        'Уроки на сегодня закончились',
      );
      expect(
        SchoolBellCountdown.describe(
          selectedDay: 1,
          now: DateTime(2026, 10, 20, 8, 20),
          lessons: mondayLessons,
        ),
        isNull,
      );
    });
  });
}
