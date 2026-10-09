import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SchoolScheduleCatalog', () {
    setUpAll(() async {
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
  });
}
