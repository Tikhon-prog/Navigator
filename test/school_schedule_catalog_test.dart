import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SchoolScheduleCatalog', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await SchoolScheduleCatalog.load();
    });

    test('contains all 33 classes from the embedded school schedule', () {
      final classes = SchoolScheduleCatalog.grades()
          .expand(SchoolScheduleCatalog.classesForGrade)
          .toSet();
      expect(classes, hasLength(33));
      expect(classes, containsAll(['5А', '5З', '6Е', '7Е', '8Г', '10Ж']));
    });

    test('detects only actual parallel groups for the selected class', () {
      expect(
        SchoolScheduleCatalog.splitSubjects('8А'),
        containsAll(['Иностранный язык', 'Информатика']),
      );
      expect(
        SchoolScheduleCatalog.splitSubjects('10Б'),
        isEmpty,
      );
    });

    test('personal schedule applies a group choice per subject and extracts teacher', () {
      final groupOne = SchoolScheduleCatalog.buildPersonal(
        '8А',
        {'Иностранный язык': 1, 'Информатика': 1},
      );
      final groupTwo = SchoolScheduleCatalog.buildPersonal(
        '8А',
        {'Иностранный язык': 2, 'Информатика': 2},
      );

      expect(groupOne, isNotEmpty);
      expect(groupTwo, isNotEmpty);
      expect(groupOne.any((e) => e.teacher.isNotEmpty), isTrue);

      bool hasParallelDuplicate(List<ScheduleEntry> entries) {
        final seen = <String>{};
        for (final e in entries) {
          final key = '${e.day}|${e.time}|${SchoolScheduleCatalog.baseSubject(e.subject)}';
          if (!seen.add(key)) return true;
        }
        return false;
      }

      expect(hasParallelDuplicate(groupOne), isFalse);
      expect(hasParallelDuplicate(groupTwo), isFalse);
    });
    test('8В chooses one whole-class subgroup and keeps merged lessons for both', () {
      final groupOne = SchoolScheduleCatalog.buildPersonal(
        '8В',
        const {},
        wholeClassGroup: 1,
      );
      final groupTwo = SchoolScheduleCatalog.buildPersonal(
        '8В',
        const {},
        wholeClassGroup: 2,
      );

      bool hasLesson(
        List<ScheduleEntry> entries, {
        required int day,
        required String time,
        required String subject,
        String? room,
      }) =>
          entries.any((entry) =>
              entry.day == day &&
              entry.time == time &&
              entry.subject.contains(subject) &&
              (room == null || entry.room == room));

      // A merged cell must appear for both students.
      for (final entries in [groupOne, groupTwo]) {
        expect(
          hasLesson(
            entries,
            day: 1,
            time: '08:00 - 08:40',
            subject: 'Разговоры о важном',
            room: '125',
          ),
          isTrue,
        );
      }

      // The same lesson slot contains different subjects for the two subgroups.
      expect(
        hasLesson(
          groupOne,
          day: 3,
          time: '16:30 - 17:10',
          subject: 'Великие достижения',
          room: '323',
        ),
        isTrue,
      );
      expect(
        hasLesson(
          groupOne,
          day: 3,
          time: '16:30 - 17:10',
          subject: 'Введение в искусственный интеллект',
        ),
        isFalse,
      );
      expect(
        hasLesson(
          groupTwo,
          day: 3,
          time: '16:30 - 17:10',
          subject: 'Введение в искусственный интеллект',
          room: '130',
        ),
        isTrue,
      );
      expect(
        hasLesson(
          groupTwo,
          day: 3,
          time: '16:30 - 17:10',
          subject: 'Великие достижения',
        ),
        isFalse,
      );

      // A lesson present only in the 8В/2 column stays hidden from 8В/1.
      expect(
        hasLesson(
          groupOne,
          day: 4,
          time: '14:40 - 15:20',
          subject: 'Алгоритмизация и программирование',
        ),
        isFalse,
      );
      expect(
        hasLesson(
          groupTwo,
          day: 4,
          time: '14:40 - 15:20',
          subject: 'Алгоритмизация и программирование',
          room: '130',
        ),
        isTrue,
      );

      expect(
        hasLesson(
          groupOne,
          day: 4,
          time: '10:20 - 11:00',
          subject: 'Информатика',
          room: '312',
        ),
        isTrue,
      );
      expect(
        hasLesson(
          groupTwo,
          day: 4,
          time: '10:20 - 11:00',
          subject: 'Информатика',
          room: '311',
        ),
        isTrue,
      );
    });

  });
}
