import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/dop_parser.dart';

void main() {
  final origin = Uri.parse('https://intranet.pokolenie.school/');

  group('School intranet redirect policy', () {
    test('allows HTTPS redirects on the exact same host and port', () {
      expect(
        allowsSchoolIntranetRedirect(
          origin,
          Uri.parse('https://intranet.pokolenie.school/current_application.php'),
        ),
        isTrue,
      );
      expect(
        allowsSchoolIntranetRedirect(origin, Uri.parse('/login.php?continue=1')),
        isTrue,
      );
    });

    test('rejects downgrade, alternate host, suffix lookalike and port', () {
      for (final target in [
        Uri.parse('http://intranet.pokolenie.school/login.php'),
        Uri.parse('https://attacker.example/login.php'),
        Uri.parse('https://intranet.pokolenie.school.attacker.example/login.php'),
        Uri.parse('https://intranet.pokolenie.school:444/login.php'),
      ]) {
        expect(
          allowsSchoolIntranetRedirect(origin, target),
          isFalse,
          reason: target.toString(),
        );
      }
    });

    test('rejects credential-bearing URLs even when the host matches', () {
      expect(
        allowsSchoolIntranetRedirect(
          origin,
          Uri.parse('https://user:pass@intranet.pokolenie.school/login.php'),
        ),
        isFalse,
      );
    });
  });
}
