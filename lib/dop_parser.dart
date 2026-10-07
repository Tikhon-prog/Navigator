import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class DopStudent {
  final String lastName;
  final String firstName;
  final String classNumber;
  final String classLetter;
  final String profile;
  final String residenceType;

  const DopStudent({
    required this.lastName,
    required this.firstName,
    required this.classNumber,
    required this.classLetter,
    this.profile = '',
    this.residenceType = 'day',
  });

  String get className => classNumber + classLetter;
}

class NavigatorStudentProvider {
  const NavigatorStudentProvider();

  Future<DopStudent?> load() async {
    final p = await SharedPreferences.getInstance();

    String first(List<String> keys) {
      for (final key in keys) {
        final value = p.getString(key)?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return '';
    }

    final classId = first([
      'student_class_id',
      'student_class_name',
      'class_id',
      'class_name',
    ]);

    final split =
        RegExp(r'^\\s*(\\d{1,2})\\s*([А-ЯЁA-Z])\\s*$',
                caseSensitive: false)
            .firstMatch(classId);

    final storedNumber = first([
      'student_class_number',
      'class_number',
      'class_grade',
    ]);
    final storedLetter = first([
      'student_class_letter',
      'class_letter',
    ]);

    final classNumber =
        storedNumber.isNotEmpty ? storedNumber : (split?.group(1) ?? '');
    final classLetter = storedLetter.isNotEmpty
        ? storedLetter
        : (split?.group(2) ?? '').toUpperCase();

    final lastName = first([
      'student_last_name',
      'last_name',
      'profile_last_name',
      'surname',
    ]);
    final firstName = first([
      'student_first_name',
      'first_name',
      'profile_first_name',
      'name',
    ]);

    if (lastName.isEmpty ||
        firstName.isEmpty ||
        classNumber.isEmpty ||
        classLetter.isEmpty) {
      return null;
    }

    final profile = first([
      'student_profile',
      'profile',
      'student_profile_name',
    ]);
    final residenceRaw = first([
      'residence_type',
      'student_residence_type',
    ]);

    return DopStudent(
      lastName: lastName,
      firstName: firstName,
      classNumber: classNumber,
      classLetter: classLetter,
      profile: profile,
      residenceType: residenceRaw.isEmpty ? 'day' : residenceRaw,
    );
  }
}

class DopScheduleItem {
  final int day;
  final int start;
  final int end;
  final String room;

  const DopScheduleItem({
    required this.day,
    required this.start,
    required this.end,
    required this.room,
  });

  Map<String, dynamic> toJson() => {
        'day': day,
        'start': start,
        'end': end,
        'room': room,
      };
}

class DopSubgroup {
  final int programId;
  final int subgroupId;
  final String name;
  final int hours;
  final int limitHours;
  final String teacher;
  final List<DopScheduleItem> schedule;
  final String? supplies;

  const DopSubgroup({
    required this.programId,
    required this.subgroupId,
    required this.name,
    required this.hours,
    required this.limitHours,
    required this.teacher,
    required this.schedule,
    required this.supplies,
  });

  Map<String, dynamic> toJson() => {
        'program_id': programId,
        'subgroup_id': subgroupId,
        'name': name,
        'hours': hours,
        'limit_hours': limitHours,
        'teacher': teacher,
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'supplies': supplies,
      };
}

class DopApplication {
  final DopStudent student;
  final DateTime updatedAt;
  final List<DopSubgroup> disciplines;

  const DopApplication({
    required this.student,
    required this.updatedAt,
    required this.disciplines,
  });

  Map<String, dynamic> toJson() => {
        'updated_at': updatedAt.toIso8601String(),
        'student': {
          'last_name': student.lastName,
          'first_name': student.firstName,
          'class_number': student.classNumber,
          'class_letter': student.classLetter,
          'class': student.className,
          'profile': student.profile,
          'residence_type': student.residenceType,
        },
        'disciplines': disciplines.map((e) => e.toJson()).toList(),
      };

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

class DopParserException implements Exception {
  final String message;
  const DopParserException(this.message);

  @override
  String toString() => 'DopParserException: ' + message;
}

class DopParseResult {
  final DopApplication application;
  final int availablePrograms;

  const DopParseResult({
    required this.application,
    required this.availablePrograms,
  });
}

class DopParser {
  static final Uri baseUri =
      Uri.parse('https://intranet.pokolenie.school/');

  final NavigatorStudentProvider studentProvider;

  const DopParser({
    this.studentProvider = const NavigatorStudentProvider(),
  });

  Future<DopParseResult> parse() async {
    final student = await studentProvider.load();

    if (student == null) {
      throw const DopParserException(
        'Не найдены ФИО и класс в Navigator storage.',
      );
    }

    final session = _DopSession();

    try {
      final first = await session.get(baseUri);
      final csrf = _inputValue(first.body, 'csrf_token');

      if (csrf.isEmpty) {
        throw const DopParserException(
          'Не найден csrf_token на стартовой странице intranet.',
        );
      }

      final catalogResponse = await session.post(first.uri, {
        'csrf_token': csrf,
        'last_name': student.lastName,
        'first_name': student.firstName,
        'class_number': student.classNumber,
        'class_letter': student.classLetter,
        'profile': student.profile,
        'residence_type': student.residenceType,
      });

      final programs = _parseCatalog(catalogResponse.body);
      final currentUri =
          catalogResponse.uri.resolve('current_application.php');
      final currentResponse = await session.get(currentUri);
      final activeRefs =
          _parseCurrentApplication(currentResponse.body);

      final disciplines = <DopSubgroup>[];

      for (final program in programs) {
        for (final subgroup in program.subgroups) {
          final key = subgroup.programId.toString() +
              ':' +
              subgroup.subgroupId.toString();

          if (activeRefs.contains(key)) {
            disciplines.add(subgroup);
          }
        }
      }

      return DopParseResult(
        application: DopApplication(
          student: student,
          updatedAt: DateTime.now(),
          disciplines: disciplines,
        ),
        availablePrograms: programs.length,
      );
    } finally {
      session.close();
    }
  }

  List<DopProgram> _parseCatalog(String html) {
    final result = <DopProgram>[];

    final cards = RegExp(
      r'<article\\b[^>]*\\bdata-program-card\\s*=\\s*["' +
          "'" +
          r'](\\d+)["' +
          "'" +
          r'][^>]*>([\\s\\S]*?)</article>',
      caseSensitive: false,
    ).allMatches(html);

    for (final card in cards) {
      final programId =
          int.tryParse(card.group(1) ?? '');
      if (programId == null) continue;

      final body = card.group(2) ?? '';
      final name = _textTag(body, 'h2');
      if (name.isEmpty) continue;

      final direction =
          _textClass(body, 'direction-badge');
      final hours =
          _number(_textClass(body, 'hours-badge'));
      final classes =
          _textClass(body, 'program-class-badge');
      final startDate =
          _nullable(_textClass(body, 'start-date-badge'));

      final subgroups = <DopSubgroup>[];
      final sgMatches = RegExp(
        r'<section\\b[^>]*\\bdata-subgroup-card\\b[^>]*>([\\s\\S]*?)</section>',
        caseSensitive: false,
      ).allMatches(body);

      for (final sgMatch in sgMatches) {
        final sg = sgMatch.group(1) ?? '';

        final input = RegExp(
          r'<input\\b[^>]*\\bclass\\s*=\\s*["' +
              "'" +
              r'][^"' +
              "'" +
              r']*\\bdiscipline-checkbox\\b[^"' +
              "'" +
              r']*["' +
              "'" +
              r'][^>]*>',
          caseSensitive: false,
        ).firstMatch(sg)?.group(0);

        if (input == null) continue;

        final subgroupId =
            int.tryParse(_attr(input, 'data-subgroup-id'));
        if (subgroupId == null) continue;

        final inputProgramId =
            int.tryParse(_attr(input, 'data-program-id')) ??
                programId;
        final dataName =
            _attr(input, 'data-name');
        final subgroupHours =
            int.tryParse(_attr(input, 'data-hours')) ?? hours;
        final limitHours =
            int.tryParse(_attr(input, 'data-limit-hours')) ??
                subgroupHours;

        var schedule = <DopScheduleItem>[];
        final rawSchedule =
            _decode(_attr(input, 'data-schedule'));

        try {
          final decoded = jsonDecode(rawSchedule);

          if (decoded is List) {
            schedule = decoded
                .whereType<Map>()
                .map((raw) {
              final m =
                  Map<String, dynamic>.from(raw);

              return DopScheduleItem(
                day: _toInt(m['day']),
                start: _toInt(m['start']),
                end: _toInt(m['end']),
                room: (m['room'] ?? '').toString().trim(),
              );
            }).toList();
          }
        } catch (_) {}

        final teacher = _textClass(
          sg,
          'program-subgroup-teacher',
          tag: 'b',
        );
        final supplies = _nullable(
          _textClass(sg, 'supplies-inline-text'),
        );

        subgroups.add(
          DopSubgroup(
            programId: inputProgramId,
            subgroupId: subgroupId,
            name: dataName.isNotEmpty ? dataName : name,
            hours: subgroupHours,
            limitHours: limitHours,
            teacher: teacher,
            schedule: schedule,
            supplies: supplies,
          ),
        );
      }

      result.add(
        DopProgram(
          programId: programId,
          name: name,
          direction: direction,
          hours: hours,
          classes: classes,
          startDate: startDate,
          subgroups: subgroups,
        ),
      );
    }

    return result;
  }

  Set<String> _parseCurrentApplication(String html) {
    final result = <String>{};

    for (final m in RegExp(
      r'<input\\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html)) {
      final tag = m.group(0)!;
      final program =
          int.tryParse(_attr(tag, 'data-program-id'));
      final subgroup =
          int.tryParse(_attr(tag, 'data-subgroup-id'));
      final value = _attr(tag, 'value');

      if (program != null && subgroup != null) {
        result.add(
          program.toString() + ':' + subgroup.toString(),
        );
      }

      final pair =
          RegExp(r'^(\\d+):(\\d+)$').firstMatch(value);

      final lower = tag.toLowerCase();

      if (pair != null &&
          (lower.contains('checked') ||
              lower.contains('selected') ||
              lower.contains('choice') ||
              lower.contains('discipline'))) {
        result.add(
          pair.group(1)! + ':' + pair.group(2)!,
        );
      }
    }

    for (final m in RegExp(
      r'\\bchoice-(\\d+)-(\\d+)\\b',
      caseSensitive: false,
    ).allMatches(html)) {
      result.add(
        m.group(1)! + ':' + m.group(2)!,
      );
    }

    return result;
  }

  String _attr(String tag, String name) {
    final pattern = RegExp(
      r'(?:\\s|^)' +
          RegExp.escape(name) +
          r'\\s*=\\s*["' +
          "'" +
          r']([^"' +
          "'" +
          r']*)["' +
          "'" +
          r']',
      caseSensitive: false,
    );

    return _decode(
      pattern.firstMatch(tag)?.group(1) ?? '',
    ).trim();
  }

  String _textTag(String html, String tag) {
    return _clean(RegExp(
      '<' +
          tag +
          r'\\b[^>]*>([\\s\\S]*?)</' +
          tag +
          '>',
      caseSensitive: false,
    ).firstMatch(html)?.group(1) ?? '');
  }

  String _textClass(
    String html,
    String className, {
    String? tag,
  }) {
    final tagName = tag ?? r'\\w+';

    return _clean(RegExp(
      '<' +
          tagName +
          r'\\b[^>]*class\\s*=\\s*["' +
          "'" +
          r'][^"' +
          "'" +
          r']*\\b' +
          RegExp.escape(className) +
          r'\\b[^"' +
          "'" +
          r']*["' +
          "'" +
          r'][^>]*>([\\s\\S]*?)</' +
          tagName +
          r'>',
      caseSensitive: false,
    ).firstMatch(html)?.group(1) ?? '');
  }

  String _clean(String value) {
    var v = _decode(value);
    v = v.replaceAll(RegExp(r'<[^>]+>'), ' ');
    v = v.replaceAll(RegExp(r'\\s+'), ' ');
    return v.trim();
  }

  String _decode(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  int _number(String value) =>
      int.tryParse(
        RegExp(r'\\d+').firstMatch(value)?.group(0) ?? '',
      ) ??
      0;

  int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class DopProgram {
  final int programId;
  final String name;
  final String direction;
  final int hours;
  final String classes;
  final String? startDate;
  final List<DopSubgroup> subgroups;

  const DopProgram({
    required this.programId,
    required this.name,
    required this.direction,
    required this.hours,
    required this.classes,
    required this.startDate,
    required this.subgroups,
  });
}

class _DopSession {
  final HttpClient _client = HttpClient();
  final Map<String, String> _cookies = {};

  Future<_DopResponse> get(Uri uri) =>
      _request('GET', uri);

  Future<_DopResponse> post(
    Uri uri,
    Map<String, String> data,
  ) =>
      _request('POST', uri, data: data);

  Future<_DopResponse> _request(
    String method,
    Uri uri, {
    Map<String, String> data = const {},
  }) async {
    var currentUri = uri;
    var currentMethod = method;
    var currentData = data;

    for (var i = 0; i < 6; i++) {
      final request =
          await _client.openUrl(currentMethod, currentUri);

      request.followRedirects = false;

      for (final c in _cookies.entries) {
        request.cookies.add(
          Cookie(c.key, c.value),
        );
      }

      if (currentMethod == 'POST') {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );

        request.write(
          currentData.entries
              .map(
                (e) =>
                    Uri.encodeQueryComponent(e.key) +
                    '=' +
                    Uri.encodeQueryComponent(e.value),
              )
              .join('&'),
        );
      }

      final response = await request.close();

      for (final cookie in response.cookies) {
        if (cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now())) {
          _cookies.remove(cookie.name);
        } else {
          _cookies[cookie.name] = cookie.value;
        }
      }

      final body =
          await utf8.decoder.bind(response).join();

      if (response.isRedirect) {
        final location =
            response.headers.value('location');

        if (location == null || location.isEmpty) {
          return _DopResponse(
            response.statusCode,
            body,
            currentUri,
          );
        }

        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303) {
          currentMethod = 'GET';
          currentData = const {};
        }

        currentUri =
            currentUri.resolve(location);
        continue;
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 400) {
        throw DopParserException(
          'HTTP ' +
              response.statusCode.toString() +
              ' при обращении к ' +
              currentUri.toString(),
        );
      }

      return _DopResponse(
        response.statusCode,
        body,
        currentUri,
      );
    }

    throw const DopParserException(
      'Слишком много перенаправлений intranet.',
    );
  }

  void close() => _client.close(force: true);
}

class _DopResponse {
  final int statusCode;
  final String body;
  final Uri uri;

  const _DopResponse(
    this.statusCode,
    this.body,
    this.uri,
  );
}

String _inputValue(String html, String name) {
  final tag = RegExp(
    r'<input\\b[^>]*\\bname\\s*=\\s*["' +
        "'" +
        RegExp.escape(name) +
        r'["' +
        "'" +
        r'][^>]*>',
    caseSensitive: false,
  ).firstMatch(html)?.group(0);

  if (tag == null) return '';

  return RegExp(
    r'\\bvalue\\s*=\\s*["' +
        "'" +
        r']([^"' +
        "'" +
        r']*)["' +
        "'" +
        r']',
    caseSensitive: false,
  ).firstMatch(tag)?.group(1) ?? '';
}
