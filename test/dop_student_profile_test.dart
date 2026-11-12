import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/dop_parser.dart';

class _FixedStudentProvider extends NavigatorStudentProvider {
  final DopStudent student;

  const _FixedStudentProvider(this.student);

  @override
  Future<DopStudent?> load() async => student;
}

void main() {
  group('DOP student study profile', () {
    test('10th grade requires a profile value accepted by the intranet', () {
      final student = DopStudent(
        lastName: 'Иванов',
        firstName: 'Иван',
        classNumber: '10',
        classLetter: 'А',
      );

      expect(DopStudent.grade10Profiles, [
        'инженерно-математический',
        'медико-биологический',
        'агротехнологический',
        'информационно-технологический',
        'социально-гуманитарный',
      ]);
      expect(
        DopStudent.grade10ProfileLabel('информационно-технологический'),
        'Информационно-технологический',
      );
      expect(student.requiresProfile, isTrue);
      expect(student.hasValidProfile, isFalse);

      final selected = DopStudent(
        lastName: 'Иванов',
        firstName: 'Иван',
        classNumber: '10',
        classLetter: 'А',
        profile: DopStudent.grade10Profiles.first,
      );
      expect(selected.hasValidProfile, isTrue);
    });

    test('accepts a non-empty profile returned by a newer intranet catalog', () {
      final student = DopStudent(
        lastName: 'Иванов',
        firstName: 'Иван',
        classNumber: '10',
        classLetter: 'А',
        profile: 'Технологический (новое направление школы)',
      );

      expect(student.requiresProfile, isTrue);
      expect(student.hasValidProfile, isTrue);
    });

    test('grades below 10 do not require a study profile', () {
      final student = DopStudent(
        lastName: 'Иванов',
        firstName: 'Иван',
        classNumber: '8',
        classLetter: 'В',
      );

      expect(student.requiresProfile, isFalse);
      expect(student.hasValidProfile, isTrue);
    });

    test('DOP parser stops before network access when grade 10 has no profile', () async {
      final student = DopStudent(
        lastName: 'Иванов',
        firstName: 'Иван',
        classNumber: '10',
        classLetter: 'А',
      );
      final parser = DopParser(
        studentProvider: _FixedStudentProvider(student),
      );

      await expectLater(
        parser.parse(),
        throwsA(isA<DopParserException>()),
      );
    });
  });
}
