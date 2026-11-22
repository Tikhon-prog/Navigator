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
      // В 10Б делятся только параллельные занятия «НВП / Первая помощь».
      expect(
        SchoolScheduleCatalog.splitSubjects('10Б'),
        {'Начальная военная подготовка / Первая помощь, основы ухода за больными'},
      );
    });

    test('subgroup choices expose the matching teacher for split subjects across classes', () {
      expect(
        SchoolScheduleCatalog.subgroupLabel('8А', 'Информатика', 1),
        contains('Тимошенко'),
      );
      expect(
        SchoolScheduleCatalog.subgroupLabel('8А', 'Информатика', 2),
        contains('Золотухина'),
      );
      expect(
        SchoolScheduleCatalog.subgroupLabel('5А', 'Математика', 1),
        startsWith('Подгруппа 1'),
      );
      expect(
        SchoolScheduleCatalog.subgroupLabel('5А', 'Математика', 2),
        startsWith('Подгруппа 2'),
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
    test('8В: группа выбирается отдельно по каждому предмету', () {
      const parallel =
          'Введение в искусственный интеллект / Великие достижения соотечественников';
      expect(
        SchoolScheduleCatalog.splitSubjects('8В'),
        containsAll(['Информатика', 'Математика', 'Иностранный язык', 'Технология', parallel]),
      );

      final groupOne = SchoolScheduleCatalog.buildPersonal('8В', const {});
      final groupTwo = SchoolScheduleCatalog.buildPersonal(
        '8В',
        const {parallel: 2, 'Информатика': 2},
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

      // Общий урок виден всем.
      for (final entries in [groupOne, groupTwo]) {
        expect(
          hasLesson(entries,
              day: 1, time: '08:00 - 08:40', subject: 'Разговоры о важном', room: '125'),
          isTrue,
        );
      }

      // Параллельные разные предметы: каждому ученику — по его выбору.
      expect(
        hasLesson(groupOne,
            day: 3, time: '16:30 - 17:10', subject: 'Великие достижения', room: '323'),
        isTrue,
      );
      expect(
        hasLesson(groupOne,
            day: 3, time: '16:30 - 17:10', subject: 'Введение в искусственный интеллект'),
        isFalse,
      );
      expect(
        hasLesson(groupTwo,
            day: 3,
            time: '16:30 - 17:10',
            subject: 'Введение в искусственный интеллект',
            room: '130'),
        isTrue,
      );
      expect(
        hasLesson(groupTwo, day: 3, time: '16:30 - 17:10', subject: 'Великие достижения'),
        isFalse,
      );

      // Одинокий урок после обеда идёт всему классу и не помечен группой.
      for (final entries in [groupOne, groupTwo]) {
        final algorithmization = entries.singleWhere((entry) =>
            entry.day == 4 &&
            entry.time == '14:40 - 15:20' &&
            entry.subject.contains('Алгоритмизация и программирование'));
        expect(algorithmization.room, '130');
        expect(algorithmization.group, 0);
      }

      // Информатика делится на подгруппы с разными кабинетами.
      expect(
        hasLesson(groupOne,
            day: 4, time: '10:20 - 11:00', subject: 'Информатика', room: '312'),
        isTrue,
      );
      expect(
        hasLesson(groupTwo,
            day: 4, time: '10:20 - 11:00', subject: 'Информатика', room: '311'),
        isTrue,
      );
    });

    test('двойная фамилия учителя не мешает определить предмет и преподавателя', () {
      expect(
        SchoolScheduleCatalog.baseSubject('Технология Захарова-Медицкая Н.И.'),
        'Технология',
      );
      expect(
        SchoolScheduleCatalog.teacherFromSubject('Технология Захарова-Медицкая Н.И.'),
        'Захарова-Медицкая Н.И.',
      );
    });

    test('практикумы и наглядная геометрия не считаются основной математикой', () {
      expect(SchoolScheduleCatalog.isMathSubject('Математика'), isTrue);
      expect(SchoolScheduleCatalog.isMathSubject('Практикум по алгебре'), isFalse);
      expect(SchoolScheduleCatalog.isMathSubject('Практикум по геометрии'), isFalse);
      expect(SchoolScheduleCatalog.isMathSubject('Наглядная геометрия'), isFalse);
    });

  });
}
