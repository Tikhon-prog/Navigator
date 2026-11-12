import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:navigator/dop_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DOP student profile isolation', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('signed-in account reads only its own profile fields', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_user_v1', jsonEncode({'id': 'student-a'}));

      await prefs.setString('student_last_name', 'LocalSurname');
      await prefs.setString('student_first_name', 'LocalName');
      await prefs.setString('student_class_number', '9');
      await prefs.setString('student_class_letter', 'А');

      await prefs.setString('student_last_name_student-a', 'AccountSurname');
      await prefs.setString('student_first_name_student-a', 'AccountName');
      await prefs.setString('student_class_number_student-a', '10');
      await prefs.setString('student_class_letter_student-a', 'Б');
      await prefs.setString(
        'student_profile_student-a',
        DopStudent.grade10Profiles.first,
      );

      final student = await const NavigatorStudentProvider().load();
      expect(student, isNotNull);
      expect(student!.lastName, 'AccountSurname');
      expect(student.firstName, 'AccountName');
      expect(student.className, '10Б');
      expect(student.profile, DopStudent.grade10Profiles.first);
    });

    test('malformed non-empty school session never falls back to local profile', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('school_user_v1', '{broken-json');
      await prefs.setString('student_last_name', 'PreviousUser');
      await prefs.setString('student_first_name', 'PreviousName');
      await prefs.setString('student_class_number', '8');
      await prefs.setString('student_class_letter', 'В');

      expect(await const NavigatorStudentProvider().load(), isNull);
    });

    test('anonymous offline profile still reads legacy local fields', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('student_last_name', 'LocalSurname');
      await prefs.setString('student_first_name', 'LocalName');
      await prefs.setString('student_class_number', '8');
      await prefs.setString('student_class_letter', 'В');

      final student = await const NavigatorStudentProvider().load();
      expect(student, isNotNull);
      expect(student!.className, '8В');
      expect(student.lastName, 'LocalSurname');
    });
  });

  group('DOP parser redirect policy', () {
    test('allows only the exact intranet HTTPS origin', () {
      expect(
        DopParser.isTrustedUri(Uri.parse('https://intranet.pokolenie.school/current_application.php')),
        isTrue,
      );
      expect(
        DopParser.isTrustedUri(Uri.parse('http://intranet.pokolenie.school/current_application.php')),
        isFalse,
      );
      expect(
        DopParser.isTrustedUri(Uri.parse('https://sub.intranet.pokolenie.school/current_application.php')),
        isFalse,
      );
      expect(
        DopParser.isTrustedUri(Uri.parse('https://intranet.pokolenie.school.attacker.example/')),
        isFalse,
      );
      expect(
        DopParser.isTrustedUri(Uri.parse('https://user:password@intranet.pokolenie.school/')),
        isFalse,
      );
    });
  });
}
