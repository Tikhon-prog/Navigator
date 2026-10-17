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

/// Keeps personally entered profile/supplement data isolated between school
/// accounts on shared devices. Unauthenticated/offline-only use retains the
/// original legacy preference keys for backward compatibility.
String studentProfilePreferenceKey(String key, {String? userId}) {
  final id = (userId ?? '').trim();
  return id.isEmpty ? key : '${key}_${id}';
}

/// Временный источник данных ученика.
///
/// Позже здесь можно сопоставить эти поля с официальным профилем «Поколение»,
/// не меняя остальной парсер.
class NavigatorStudentProvider {
  const NavigatorStudentProvider();

  Future<DopStudent?> load() async {
    final prefs = await SharedPreferences.getInstance();
    String? schoolUserId;
    var hasSchoolSession = false;
    final rawSchoolUser = prefs.getString('school_user_v1');
    if (rawSchoolUser != null) {
      try {
        final account = jsonDecode(rawSchoolUser);
        if (account is Map && account['id'] != null) {
          schoolUserId = account['id'].toString();
          hasSchoolSession = true;
        }
      } catch (_) {}
    }

    String first(List<String> keys) {
      for (final key in keys) {
        final scopedKey = studentProfilePreferenceKey(key, userId: schoolUserId);
        // Once signed into a school account, never fall back to another user's
        // legacy personal name/profile fields.
        final value = prefs.getString(scopedKey)?.trim();
        if (value != null && value.isNotEmpty) return value;
        if (!hasSchoolSession) {
          final legacy = prefs.getString(key)?.trim();
          if (legacy != null && legacy.isNotEmpty) return legacy;
        }
      }
      return '';
    }

    var classId = first([
      'student_class_id',
      'student_class_name',
      'class_id',
      'class_name',
    ]);
    // These two legacy keys are rewritten from the active SSO account on every
    // successful login and removed on sign-out, so they are safe session scope
    // fallbacks when a user has not manually completed the DOP profile yet.
    if (classId.isEmpty && hasSchoolSession) {
      classId = (prefs.getString('student_class_name') ??
          prefs.getString('student_class_id') ?? '').trim();
    }

    final classMatch = RegExp(
      r'^(\d{1,2})\s*([А-ЯЁA-Z])$',
      caseSensitive: false,
    ).firstMatch(classId);

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
        storedNumber.isNotEmpty ? storedNumber : (classMatch?.group(1) ?? '');
    final classLetter = storedLetter.isNotEmpty
        ? storedLetter
        : (classMatch?.group(2) ?? '').toUpperCase();

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

    return DopStudent(lastName:lastName,firstName:firstName,classNumber:classNumber,classLetter:classLetter,profile:profile,residenceType:'auto');
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

class DopParseResult {
  final DopApplication application;
  final int availablePrograms;

  const DopParseResult({
    required this.application,
    required this.availablePrograms,
  });
}

class DopParserException implements Exception {
  final String message;

  const DopParserException(this.message);

  @override
  String toString() => 'DopParserException: ' + message;
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
        'В хранилище профиля «Поколение» не найдены данные ученика.',
      );
    }

    for (final residence in const ['day', 'campus']) {
      final session = _DopSession();
      try {
        final candidate = DopStudent(lastName:student.lastName,firstName:student.firstName,classNumber:student.classNumber,classLetter:student.classLetter,profile:student.profile,residenceType:residence);
        final firstPage = await session.get(baseUri);
        final csrf = _inputValue(firstPage.body, 'csrf_token');
        if (csrf.isEmpty) throw const DopParserException('Не найден csrf_token на стартовой странице intranet.');
        final catalogPage = await session.post(firstPage.uri, {'csrf_token':csrf,'last_name':candidate.lastName,'first_name':candidate.firstName,'class_number':candidate.classNumber,'class_letter':candidate.classLetter,'profile':candidate.profile,'residence_type':residence});
        final programs = _parseCatalog(catalogPage.body);
        final currentPage = await session.get(catalogPage.uri.resolve('current_application.php'));
        final currentChoices = _parseCurrentApplication(currentPage.body);
        if (currentChoices.isEmpty) continue;
        final disciplines=<DopSubgroup>[];
        for(final choice in currentChoices){
          final program=_findProgram(programs,choice.name);
          if(program==null){disciplines.add(DopSubgroup(programId:0,subgroupId:0,name:choice.name,hours:choice.hours,limitHours:choice.hours,teacher:choice.teacher,schedule:choice.schedule,supplies:null));continue;}
          final subgroup = _findBestSubgroup(program, choice);
          if (subgroup != null) {
            disciplines.add(subgroup);
          } else {
            // Never silently substitute an arbitrary subgroup: current_application.php
            // is the source of truth for the student's actual selection.
            final hours = choice.hours > 0 ? choice.hours : program.hours;
            disciplines.add(DopSubgroup(
              programId: program.programId,
              subgroupId: 0,
              name: choice.name,
              hours: hours,
              limitHours: hours,
              teacher: choice.teacher,
              schedule: choice.schedule,
              supplies: null,
            ));
          }
        }
        if(disciplines.isNotEmpty){
          return DopParseResult(application:DopApplication(student:candidate,updatedAt:DateTime.now(),disciplines:disciplines),availablePrograms:programs.length);
        }
      } finally {
        session.close();
      }
    }
    throw const DopParserException('Не удалось автоматически определить тип проживания (дневное/пансион) или найти текущие ДОПы.');
  }

  List<DopProgram> _parseCatalog(String html) {
    final result = <DopProgram>[];
    final cards = RegExp(
      r'<article\b([^>]*)>([\s\S]*?)</article>',
      caseSensitive: false,
    ).allMatches(html);

    for (final card in cards) {
      final attributes = card.group(1) ?? '';
      final programId = int.tryParse(_attr(attributes, 'data-program-card'));
      if (programId == null) continue;
      final body = card.group(2) ?? '';
      final name = _textTag(body, 'h2');
      if (name.isEmpty) continue;

      final direction = _textClass(body, 'direction-badge');
      final hours = _number(_textClass(body, 'hours-badge'));
      final classes = _textClass(body, 'program-class-badge');
      final startDate = _nullable(_textClass(body, 'start-date-badge'));
      final subgroups = <DopSubgroup>[];
      final subgroupMatches = RegExp(
        r'<section\b[^>]*\bdata-subgroup-card\b[^>]*>([\s\S]*?)</section>',
        caseSensitive: false,
      ).allMatches(body);

      for (final match in subgroupMatches) {
        final subgroupHtml = match.group(1) ?? '';
        String? input;
        for (final inputMatch in RegExp(r'<input\b[^>]*>', caseSensitive: false).allMatches(subgroupHtml)) {
          final candidate = inputMatch.group(0) ?? '';
          if (_attr(candidate, 'class').split(RegExp(r'\s+')).contains('discipline-checkbox')) {
            input = candidate;
            break;
          }
        }
        if (input == null) continue;

        final subgroupId = int.tryParse(_attr(input, 'data-subgroup-id'));
        if (subgroupId == null) continue;
        final inputProgramId = int.tryParse(_attr(input, 'data-program-id')) ?? programId;
        final dataName = _attr(input, 'data-name');
        final subgroupHours = int.tryParse(_attr(input, 'data-hours')) ?? hours;
        final limitHours = int.tryParse(_attr(input, 'data-limit-hours')) ?? subgroupHours;
        final schedule = _parseJsonSchedule(_decode(_attr(input, 'data-schedule')));
        final teacher = _teacherFromSubgroup(subgroupHtml);
        final supplies = _nullable(_textClass(subgroupHtml, 'supplies-inline-text'));

        subgroups.add(DopSubgroup(
          programId: inputProgramId,
          subgroupId: subgroupId,
          name: dataName.isNotEmpty ? dataName : name,
          hours: subgroupHours,
          limitHours: limitHours,
          teacher: teacher,
          schedule: schedule,
          supplies: supplies,
        ));
      }

      result.add(DopProgram(
        programId: programId,
        name: name,
        direction: direction,
        hours: hours,
        classes: classes,
        startDate: startDate,
        subgroups: subgroups,
      ));
    }
    return result;
  }

  /// current_application.php содержит карточки:
  /// article.success-program-card
  ///   strong.success-program-name
  ///   span.hours-badge
  ///   b внутри .program-subgroup-teacher
  ///   span внутри .program-subgroup-schedule
  List<_DopCurrentChoice> _parseCurrentApplication(String html) {
    final result = <_DopCurrentChoice>[];
    final cards = RegExp(
      r'<article\b([^>]*)>([\s\S]*?)</article>',
      caseSensitive: false,
    ).allMatches(html);

    for (final card in cards) {
      final attributes = card.group(1) ?? '';
      final classes = _attr(attributes, 'class').split(RegExp(r'\s+'));
      if (!classes.contains('success-program-card')) continue;
      final body = card.group(2) ?? '';

      final name = _textClass(body, 'success-program-name', tag: 'strong');
      if (name.isEmpty) continue;

      final hours = _number(_textClass(body, 'hours-badge'));
      final teacher = _teacherFromSubgroup(body);
      final scheduleText = _textClass(body, 'program-subgroup-schedule');

      result.add(_DopCurrentChoice(
        name: name,
        hours: hours,
        teacher: teacher,
        schedule: _parseDisplayedSchedule(scheduleText),
      ));
    }
    return result;
  }

  List<DopScheduleItem> _parseDisplayedSchedule(String text) {
    if (text.trim().isEmpty) return const [];

    final result = <DopScheduleItem>[];

    final matches = RegExp(
      r'(Понедельник|Вторник|Среда|Четверг|Пятница|Суббота)\s*·\s*уроки\s+(\d+)\s*[–-]\s*(\d+)\s*·\s*(.+?)(?=\s*(?:Понедельник|Вторник|Среда|Четверг|Пятница|Суббота)\s*·|$)',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(text);

    for (final match in matches) {
      final room = (match.group(4) ?? '')
          .replaceFirst(
            RegExp(r'\s*КАБИНЕТ\s*$', caseSensitive: false),
            '',
          )
          .trim();

      result.add(
        DopScheduleItem(
          day: _dayNumber(match.group(1) ?? ''),
          start: int.tryParse(match.group(2) ?? '') ?? 0,
          end: int.tryParse(match.group(3) ?? '') ?? 0,
          room: room,
        ),
      );
    }

    return result;
  }

  int _dayNumber(String text) {
    switch (text.trim().toLowerCase()) {
      case 'понедельник':
        return 1;
      case 'вторник':
        return 2;
      case 'среда':
        return 3;
      case 'четверг':
        return 4;
      case 'пятница':
        return 5;
      case 'суббота':
        return 6;
    }
    return 0;
  }

  List<DopScheduleItem> _parseJsonSchedule(String value) {
    if (value.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(value);

      if (decoded is! List) return const [];

      return decoded.whereType<Map>().map((raw) {
        final map = Map<String, dynamic>.from(raw);

        return DopScheduleItem(
          day: _toInt(map['day']),
          start: _toInt(map['start']),
          end: _toInt(map['end']),
          room: (map['room'] ?? '').toString().trim(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  DopProgram? _findProgram(
    List<DopProgram> programs,
    String name,
  ) {
    final wanted = _normalizeName(name);

    for (final program in programs) {
      if (_normalizeName(program.name) == wanted) {
        return program;
      }
    }

    return null;
  }

  String _normalizeName(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  DopSubgroup? _findBestSubgroup(
    DopProgram program,
    _DopCurrentChoice choice,
  ) {
    if (program.subgroups.isEmpty) return null;

    if (choice.teacher.isNotEmpty) {
      for (final subgroup in program.subgroups) {
        if (subgroup.teacher.trim() == choice.teacher.trim()) {
          return subgroup;
        }
      }
    }

    if (choice.schedule.isNotEmpty) {
      for (final subgroup in program.subgroups) {
        if (_sameSchedule(subgroup.schedule, choice.schedule)) {
          return subgroup;
        }
      }
    }

    return null;
  }

  bool _sameSchedule(
    List<DopScheduleItem> a,
    List<DopScheduleItem> b,
  ) {
    if (a.length != b.length) return false;

    for (final x in a) {
      final found = b.any(
        (y) =>
            x.day == y.day &&
            x.start == y.start &&
            x.end == y.end &&
            _normalizeRoom(x.room) == _normalizeRoom(y.room),
      );

      if (!found) return false;
    }

    return true;
  }

  String _attr(String tag, String name) {
    final match = RegExp(
      r'''(?:\b)''' +
          RegExp.escape(name) +
          r'''(?:\s*=\s*["'])(.*?)(?:["'])''',
      caseSensitive: false,
    ).firstMatch(tag);

    return _decode(match?.group(1) ?? '').trim();
  }

  String _textTag(String html, String tag) {
    return _clean(
      RegExp(
        '<' + tag + r'\b[^>]*>([\s\S]*?)</' + tag + '>',
        caseSensitive: false,
      ).firstMatch(html)?.group(1) ?? '',
    );
  }

  String _textClass(
    String html,
    String className, {
    String? tag,
  }) {
    final tagName = tag ?? r'[A-Za-z][A-Za-z0-9-]*';

    final doubleQuote = RegExp(
      '<' +
          tagName +
          r'\b[^>]*class\s*=\s*"[^"]*\b' +
          RegExp.escape(className) +
          r'\b[^"]*"[^>]*>([\s\S]*?)</' +
          tagName +
          r'>',
      caseSensitive: false,
    ).firstMatch(html);

    final match = doubleQuote ??
        RegExp(
          "<" +
              tagName +
              r"\b[^>]*class\s*=\s*'[^']*\b" +
              RegExp.escape(className) +
              r"\b[^']*'[^>]*>([\s\S]*?)</" +
              tagName +
              r">",
          caseSensitive: false,
        ).firstMatch(html);

    return _clean(match?.group(1) ?? '');
  }

  String _teacherFromSubgroup(String html) {
    final container = _textClass(
      html,
      'program-subgroup-teacher',
    );

    final teacher = _textTag(container, 'b');
    return teacher.isNotEmpty ? teacher : container;
  }

  String _clean(String value) {
    var v = _decode(value);
    v = v.replaceAll(
      RegExp(r'<script\b[\s\S]*?</script>', caseSensitive: false),
      '',
    );
    v = v.replaceAll(
      RegExp(r'<style\b[\s\S]*?</style>', caseSensitive: false),
      '',
    );
    v = v.replaceAll(RegExp(r'<[^>]+>'), ' ');
    v = v.replaceAll(RegExp(r'\s+'), ' ');
    return v.trim();
  }

  String _decode(String value) {
    var result = value
        .replaceAll('&nbsp;', '\u00A0')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '…')
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll('&rsquo;', '’')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”')
        .replaceAll('&bull;', '•')
        .replaceAll('&deg;', '°')
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');

    result = result.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) => String.fromCharCode(int.tryParse(match.group(1)!, radix: 16) ?? 0),
    );
    result = result.replaceAllMapped(
      RegExp(r'&#([0-9]+);'),
      (match) => String.fromCharCode(int.tryParse(match.group(1)!) ?? 0),
    );
    return result;
  }

  String _nullableString(String value) =>
      value.trim();

  String? _nullable(String value) {
    final v = _nullableString(value);
    return v.isEmpty ? null : v;
  }

  int _number(String value) {
    return int.tryParse(
          RegExp(r'\d+').firstMatch(value)?.group(0) ?? '',
        ) ??
        0;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _inputValue(String html, String name) {
    for (final match in RegExp(r'<input\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = match.group(0) ?? '';
      if (_attr(tag, 'name') == name) return _attr(tag, 'value');
    }
    return '';
  }

  String _normalizeRoom(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'^\s*кабинет\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

}

class _DopCurrentChoice {
  final String name;
  final int hours;
  final String teacher;
  final List<DopScheduleItem> schedule;

  const _DopCurrentChoice({
    required this.name,
    required this.hours,
    required this.teacher,
    required this.schedule,
  });
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
      final request = await _client
          .openUrl(currentMethod, currentUri)
          .timeout(const Duration(seconds: 20));

      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Navigator-Dop-Parser/1.0',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml',
      );
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'ru-RU,ru;q=0.9',
      );

      for (final cookie in _cookies.entries) {
        request.cookies.add(
          Cookie(cookie.key, cookie.value),
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

      final response = await request.close().timeout(const Duration(seconds: 20));

      for (final cookie in response.cookies) {
        if (cookie.expires != null &&
            cookie.expires!.isBefore(DateTime.now())) {
          _cookies.remove(cookie.name);
        } else {
          _cookies[cookie.name] = cookie.value;
        }
      }

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));

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

        currentUri = currentUri.resolve(location);
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

  void close() {
    _client.close(force: true);
  }
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

