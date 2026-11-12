import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class DopStudent {
  /// Exact option values and visible labels from the intranet profile select.
  static const List<String> grade10Profiles = [
    'инженерно-математический',
    'медико-биологический',
    'агротехнологический',
    'информационно-технологический',
    'социально-гуманитарный',
  ];

  static const Map<String, String> grade10ProfileLabels = {
    'инженерно-математический': 'Инженерно-математический',
    'медико-биологический': 'Медико-биологический',
    'агротехнологический': 'Агротехнологический',
    'информационно-технологический': 'Информационно-технологический',
    'социально-гуманитарный': 'Социально-гуманитарный',
  };

  static String grade10ProfileLabel(String value) =>
      grade10ProfileLabels[value] ?? value;

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
  bool get requiresProfile => classNumber.trim() == '10';
  bool get hasValidProfile => !requiresProfile || profile.trim().isNotEmpty;
}

/// Keeps personally entered profile/supplement data isolated between school
/// accounts on shared devices. Unauthenticated/offline-only use retains the
/// original legacy preference keys for backward compatibility.
String studentProfilePreferenceKey(String key, {String? userId}) {
  final id = (userId ?? '').trim();
  return id.isEmpty ? key : '${key}_$id';
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
    final rawSchoolUser = prefs.getString('school_user_v1');
    final hasSchoolSession =
        rawSchoolUser != null && rawSchoolUser.trim().isNotEmpty;
    var validSchoolSession = false;
    if (hasSchoolSession) {
      try {
        final account = jsonDecode(rawSchoolUser);
        final identity = account is Map
            ? (account['id'] ?? '').toString().trim()
            : '';
        if (identity.isNotEmpty) {
          schoolUserId = identity;
          validSchoolSession = true;
        }
      } catch (_) {
        // Do not expose the anonymous/local profile if the persisted school
        // session is malformed or missing a stable account identifier.
      }
      schoolUserId ??= 'invalid-school-session';
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
    if (classId.isEmpty && validSchoolSession) {
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

/// Compares DOP schedules as multisets, consuming each matched item once.
/// This avoids treating duplicate lesson slots as multiple matches for one row.
bool dopSchedulesEqual(
  List<DopScheduleItem> left,
  List<DopScheduleItem> right,
) {
  if (left.length != right.length) return false;
  final unmatched = List<DopScheduleItem>.of(right);
  for (final item in left) {
    final index = unmatched.indexWhere((candidate) =>
        item.day == candidate.day &&
        item.start == candidate.start &&
        item.end == candidate.end &&
        _normalizeDopRoom(item.room) == _normalizeDopRoom(candidate.room));
    if (index < 0) return false;
    unmatched.removeAt(index);
  }
  return unmatched.isEmpty;
}

String _normalizeDopRoom(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'^\s*кабинет\s*'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class DopSubgroup {
  final int programId;
  final int subgroupId;
  final String name;
  final int hours;
  final int limitHours;
  final String teacher;
  final List<DopScheduleItem> schedule;
  final String? supplies;
  final String selectionName;
  final String selectionValue;
  final bool preselected;
  final bool selectionDisabled;

  const DopSubgroup({
    required this.programId,
    required this.subgroupId,
    required this.name,
    required this.hours,
    required this.limitHours,
    required this.teacher,
    required this.schedule,
    required this.supplies,
    this.selectionName = '',
    this.selectionValue = '',
    this.preselected = false,
    this.selectionDisabled = false,
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
  String toString() => 'DopParserException: $message';
}

class DopParser {
  static final Uri baseUri =
      Uri.parse('https://intranet.pokolenie.school/');

  /// Only the configured school intranet origin may receive the session cookies.
  static bool isTrustedUri(Uri uri) =>
      uri.scheme == baseUri.scheme &&
      uri.host.toLowerCase() == baseUri.host.toLowerCase() &&
      uri.port == baseUri.port &&
      uri.userInfo.isEmpty;

  final NavigatorStudentProvider studentProvider;

  const DopParser({
    this.studentProvider = const NavigatorStudentProvider(),
  });

  /// Reads the profile values from the intranet form. The built-in list is
  /// retained as an offline fallback so profile editing remains available.
  Future<List<String>> loadGrade10Profiles() async {
    final session = _DopSession();
    try {
      final page = await session.get(baseUri);
      final parsed = DopProfileCatalogParser.parse(page.body);
      return parsed.isEmpty ? DopStudent.grade10Profiles : parsed;
    } catch (_) {
      return DopStudent.grade10Profiles;
    } finally {
      session.close();
    }
  }

  /// Opens the live DOP catalogue and keeps its cookie session for submissions.
  Future<DopCatalogSession> openCatalog() async {
    final student = await studentProvider.load();
    if (student == null) {
      throw const DopParserException(
        'Сначала заполни профиль ученика для загрузки каталога ДОПов.',
      );
    }
    if (student.requiresProfile && !student.hasValidProfile) {
      throw const DopParserException(
        'Для 10 класса сначала выбери направление обучения в профиле ученика.',
      );
    }

    DopParserException? lastError;
    // The school page expects one of these exact residence values. "auto" is
    // an app-only sentinel and must never be sent to the intranet.
    for (final residence in const ['day', 'boarding']) {
      final session = _DopSession();
      try {
        final firstPage = await session.get(baseUri);
        final csrf = _inputValue(firstPage.body, 'csrf_token');
        if (csrf.isEmpty) {
          throw const DopParserException(
            'Не найден csrf_token на стартовой странице intranet.',
          );
        }
        final catalogPage = await session.post(firstPage.uri, {
          'csrf_token': csrf,
          'last_name': student.lastName,
          'first_name': student.firstName,
          'class_number': student.classNumber,
          'class_letter': student.classLetter,
          'profile': student.profile,
          'residence_type': residence,
        });
        final programs = _parseCatalog(catalogPage.body);
        if (programs.isNotEmpty) {
          final form = DopSelectionFormParser.parse(
            catalogPage.body,
            catalogPage.uri,
          );
          final catalogStudent = DopStudent(
            lastName: student.lastName,
            firstName: student.firstName,
            classNumber: student.classNumber,
            classLetter: student.classLetter,
            profile: student.profile,
            residenceType: residence,
          );
          return DopCatalogSession._(
            student: catalogStudent,
            programs: programs,
            session: session,
            parser: this,
            form: form,
            maxHours: form?.maxHours ?? 10,
          );
        }
        session.close();
      } catch (error) {
        session.close();
        lastError = error is DopParserException
            ? error
            : DopParserException(error.toString());
      }
    }
    throw lastError ??
        const DopParserException(
          'Intranet не вернул каталог ДОПов. Проверь профиль и доступность сайта.',
        );
  }

  /// Exposed for deterministic fixture tests; production uses [openCatalog].
  List<DopProgram> parseCatalogHtml(String html) => _parseCatalog(html);

  /// Parses the student's current_application.php page independently.
  List<DopCurrentApplicationItem> parseCurrentApplicationHtml(String html) =>
      _parseCurrentApplication(html);

  Future<DopParseResult> parse() async {
    final student = await studentProvider.load();

    if (student == null) {
      throw const DopParserException(
        'В хранилище профиля «Поколение» не найдены данные ученика.',
      );
    }
    if (student.requiresProfile && !student.hasValidProfile) {
      throw const DopParserException(
        'Для 10 класса сначала выбери направление обучения в профиле ученика.',
      );
    }

    for (final residence in const ['day', 'boarding']) {
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
    var freshSelection = false;
    for (final form in RegExp(
      r'<form\b([^>]*)>',
      caseSensitive: false,
    ).allMatches(html)) {
      final attributes = form.group(1) ?? '';
      if (_attr(attributes, 'id') == 'disciplines-form') {
        freshSelection = _attr(attributes, 'data-fresh-selection') == '1';
        break;
      }
    }

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
        final selectionName = _attr(input, 'name');
        final selectionValue = _attr(input, 'value');
        final preselected = !freshSelection &&
            RegExp(
              r'(?:^|\s)checked(?:\s|=|>)',
              caseSensitive: false,
            ).hasMatch(input);
        final selectionDisabled = _hasAttribute(input, 'disabled') ||
            _attr(input, 'aria-disabled').toLowerCase() == 'true';

        subgroups.add(DopSubgroup(
          programId: inputProgramId,
          subgroupId: subgroupId,
          name: dataName.isNotEmpty ? dataName : name,
          hours: subgroupHours,
          limitHours: limitHours,
          teacher: teacher,
          schedule: schedule,
          supplies: supplies,
          selectionName: selectionName,
          selectionValue: selectionValue,
          preselected: preselected,
          selectionDisabled: selectionDisabled,
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
  List<DopCurrentApplicationItem> _parseCurrentApplication(String html) {
    final result = <DopCurrentApplicationItem>[];
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
      result.add(DopCurrentApplicationItem(
        name: name,
        hours: hours,
        teacher: teacher,
        schedule: _parseSubgroupSchedule(body),
      ));
    }
    return result;
  }

  /// The intranet wraps every lesson slot in its own span. Parse those
  /// elements independently so one slot cannot swallow the following day.
  List<DopScheduleItem> _parseSubgroupSchedule(String html) {
    final result = <DopScheduleItem>[];
    final containers = RegExp(
      r'<div\b([^>]*)>([\s\S]*?)</div>',
      caseSensitive: false,
    ).allMatches(html);

    for (final container in containers) {
      final attributes = container.group(1) ?? '';
      final classes = _attr(attributes, 'class').split(RegExp(r'\s+'));
      if (!classes.contains('program-subgroup-schedule')) continue;
      final content = container.group(2) ?? '';
      final spans = RegExp(
        r'<span\b[^>]*>([\s\S]*?)</span>',
        caseSensitive: false,
      ).allMatches(content);

      if (spans.isEmpty) {
        result.addAll(_parseDisplayedSchedule(_clean(content)));
      } else {
        for (final span in spans) {
          result.addAll(
            _parseDisplayedSchedule(_clean(span.group(1) ?? '')),
          );
        }
      }
    }

    return result.isNotEmpty
        ? result
        : _parseDisplayedSchedule(
            _textClass(html, 'program-subgroup-schedule'),
          );
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
            RegExp(
              r'^\s*(?:кабинет|каб\.?|аудитория|ауд\.?)\s*(?:№\s*)?',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      final day = _dayNumber(match.group(1) ?? '');
      final start = int.tryParse(match.group(2) ?? '') ?? 0;
      final end = int.tryParse(match.group(3) ?? '') ?? 0;
      // The intranet stores lesson numbers, not clock minutes.
      if (day < 1 || day > 6 || start < 1 || end < start || end > 20) {
        continue;
      }
      result.add(DopScheduleItem(
        day: day,
        start: start,
        end: end,
        room: room,
      ));
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

      final result = <DopScheduleItem>[];
      for (final raw in decoded.whereType<Map>()) {
        final map = Map<String, dynamic>.from(raw);
        final day = _toInt(map['day']);
        final start = _toInt(map['start']);
        final end = _toInt(map['end']);
        if (day < 1 || day > 6 || start < 1 || end < start || end > 20) {
          continue;
        }
        result.add(DopScheduleItem(
          day: day,
          start: start,
          end: end,
          room: (map['room'] ?? '').toString().trim(),
        ));
      }
      return result;
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
    DopCurrentApplicationItem choice,
  ) {
    if (program.subgroups.isEmpty) return null;

    final teacher = choice.teacher.trim();
    final teacherMatches = teacher.isEmpty
        ? <DopSubgroup>[]
        : program.subgroups
            .where((item) => item.teacher.trim() == teacher)
            .toList();

    final scheduleMatches = choice.schedule.isEmpty
        ? <DopSubgroup>[]
        : program.subgroups
            .where((item) => _sameSchedule(item.schedule, choice.schedule))
            .toList();

    // If both pieces of evidence exist, require both to match. A common
    // teacher may supervise several parallel subgroups with different rooms.
    if (teacher.isNotEmpty && choice.schedule.isNotEmpty) {
      final exactMatches = teacherMatches
          .where((item) => _sameSchedule(item.schedule, choice.schedule))
          .toList();
      return exactMatches.length == 1 ? exactMatches.single : null;
    }

    if (teacher.isNotEmpty) {
      return teacherMatches.length == 1 ? teacherMatches.single : null;
    }

    if (choice.schedule.isNotEmpty) {
      return scheduleMatches.length == 1 ? scheduleMatches.single : null;
    }

    return null;
  }

  bool _sameSchedule(
    List<DopScheduleItem> a,
    List<DopScheduleItem> b,
  ) => dopSchedulesEqual(a, b);

  String _attr(String tag, String name) {
    final match = RegExp(
      r'(?:^|\s)' +
          RegExp.escape(name) +
          r'\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))',
      caseSensitive: false,
    ).firstMatch(tag);

    final value = match?.group(1) ?? match?.group(2) ?? match?.group(3) ?? '';
    return _decode(value).trim();
  }

  bool _hasAttribute(String tag, String name) => RegExp(
        r'(?:^|\s)' + RegExp.escape(name) + r'(?:\s*=|\s|/?>)',
        caseSensitive: false,
      ).hasMatch(tag);

  String _textTag(String html, String tag) {
    return _clean(
      RegExp(
        '<$tag\\b[^>]*>([\\s\\S]*?)</$tag>',
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

    final escapedClassName = RegExp.escape(className);
    final doubleQuote = RegExp(
      '<$tagName\\b[^>]*class\\s*=\\s*"[^"]*\\b$escapedClassName\\b[^"]*"[^>]*>([\\s\\S]*?)</$tagName>',
      caseSensitive: false,
    ).firstMatch(html);

    final match = doubleQuote ??
        RegExp(
          "<$tagName\\b[^>]*class\\s*=\\s*'[^']*\\b$escapedClassName\\b[^']*'[^>]*>([\\s\\S]*?)</$tagName>",
          caseSensitive: false,
        ).firstMatch(html);

    return _clean(match?.group(1) ?? '');
  }

  String _teacherFromSubgroup(String html) {
    final rawMatch = RegExp(
      r'''<([A-Za-z][A-Za-z0-9-]*)\b[^>]*class\s*=\s*(?:"[^"]*\bprogram-subgroup-teacher\b[^"]*"|'[^']*\bprogram-subgroup-teacher\b[^']*')[^>]*>([\s\S]*?)</\1>''',
      caseSensitive: false,
    ).firstMatch(html);
    final raw = rawMatch?.group(2) ?? '';
    final teacher = _textTag(raw, 'b');
    if (teacher.isNotEmpty) return teacher;

    return _clean(raw)
        .replaceFirst(
          RegExp(
            r'^(?:педагог|учитель|преподаватель)\s*[:—-]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
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

}

class DopCurrentApplicationItem {
  final String name;
  final int hours;
  final String teacher;
  final List<DopScheduleItem> schedule;

  const DopCurrentApplicationItem({
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


/// Extracts the exact grade-10 profile options offered by the live intranet.
class DopProfileCatalogParser {
  static List<String> parse(String html) {
    final parser = const DopParser();
    final values = <String>[];
    final selects = RegExp(
      r'<select\b([^>]*)>([\s\S]*?)</select>',
      caseSensitive: false,
    ).allMatches(html);

    for (final select in selects) {
      final attributes = select.group(1) ?? '';
      final name = parser._attr(attributes, 'name').toLowerCase();
      final id = parser._attr(attributes, 'id').toLowerCase();
      if (name != 'profile' &&
          id != 'profile' &&
          name != 'study_profile' &&
          id != 'study_profile') {
        continue;
      }
      final body = select.group(2) ?? '';
      final options = RegExp(
        r'<option\b([^>]*)>([\s\S]*?)</option>',
        caseSensitive: false,
      ).allMatches(body);
      for (final option in options) {
        final optionAttributes = option.group(1) ?? '';
        final hasValue = RegExp(
          r'\bvalue\s*=',
          caseSensitive: false,
        ).hasMatch(optionAttributes);
        final rawValue = parser._attr(optionAttributes, 'value');
        final label = parser._clean(option.group(2) ?? '');
        final value = hasValue ? rawValue : label;
        final isPlaceholder = RegExp(
          r'^(?:выберите|выбрать|не выбрано|select\b|—|-)$',
          caseSensitive: false,
        ).hasMatch(label.trim());
        if (value.trim().isEmpty ||
            rawValue.trim() == '0' ||
            isPlaceholder ||
            RegExp(
              r'(?:^|\s)disabled(?:\s|=|$)',
              caseSensitive: false,
            ).hasMatch(optionAttributes)) {
          continue;
        }
        if (!values.contains(value.trim())) values.add(value.trim());
      }
      if (values.isNotEmpty) break;
    }
    return List<String>.unmodifiable(values);
  }
}

/// Finds the actual form that owns the catalogue checkboxes. It preserves all
/// hidden fields and the repeated checkbox names required by PHP forms.
class DopSelectionFormParser {
  static DopSelectionFormInfo? parse(String html, Uri pageUri) {
    final parser = const DopParser();
    final forms = RegExp(
      r'<form\b([^>]*)>([\s\S]*?)</form>',
      caseSensitive: false,
    ).allMatches(html);

    for (final form in forms) {
      final attributes = form.group(1) ?? '';
      final body = form.group(2) ?? '';
      if (!body.contains('discipline-checkbox')) continue;

      final action = parser._attr(attributes, 'action');
      final target = action.isEmpty ? pageUri : pageUri.resolve(action);
      if (!DopParser.isTrustedUri(target)) continue;

      final method = parser._attr(attributes, 'method').toUpperCase();
      final formClasses =
          parser._attr(attributes, 'class').split(RegExp(r'\s+'));
      var selectionLocked = formClasses.contains('selection-locked') ||
          parser._attr(attributes, 'aria-disabled').toLowerCase() == 'true';
      final hidden = <MapEntry<String, String>>[];
      var hasUnsupportedControls = false;
      String submitName = '';
      String submitValue = '';

      for (final inputMatch in RegExp(
        r'<input\b[^>]*>',
        caseSensitive: false,
      ).allMatches(body)) {
        final tag = inputMatch.group(0) ?? '';
        final type = parser._attr(tag, 'type').toLowerCase();
        final name = parser._attr(tag, 'name');
        final value = parser._attr(tag, 'value');
        if (type == 'hidden' && name.isNotEmpty) {
          hidden.add(MapEntry(name, value));
        } else if (type == 'submit' || type == 'image') {
          if (parser._hasAttribute(tag, 'disabled') ||
              parser._attr(tag, 'aria-disabled').toLowerCase() == 'true') {
            selectionLocked = true;
          }
          if (name.isNotEmpty && submitName.isEmpty) {
            submitName = name;
            submitValue = value;
          }
        } else if (type == 'checkbox') {
          final classes = parser._attr(tag, 'class').split(RegExp(r'\s+'));
          if (name.isNotEmpty && !classes.contains('discipline-checkbox')) {
            hasUnsupportedControls = true;
          }
        } else if (name.isNotEmpty && type != 'button' && type != 'reset') {
          hasUnsupportedControls = true;
        }
      }

      if (RegExp(
        r'<(?:select|textarea)\b[^>]*\bname\s*=',
        caseSensitive: false,
      ).hasMatch(body)) {
        hasUnsupportedControls = true;
      }

      for (final button in RegExp(
        r'<button\b[^>]*>',
        caseSensitive: false,
      ).allMatches(body)) {
        final buttonAttributes = button.group(0) ?? '';
        final type = parser._attr(buttonAttributes, 'type').toLowerCase();
        if (type.isNotEmpty && type != 'submit') continue;
        if (parser._hasAttribute(buttonAttributes, 'disabled') ||
            parser._attr(buttonAttributes, 'aria-disabled').toLowerCase() ==
                'true') {
          selectionLocked = true;
        }
        final name = parser._attr(buttonAttributes, 'name');
        if (name.isNotEmpty && submitName.isEmpty) {
          submitName = name;
          submitValue = parser._attr(buttonAttributes, 'value');
        }
      }

      final selectionBar = RegExp(
        r'<[^>]*\bid\s*=\s*(?:"selection-bar"|\x27selection-bar\x27)[^>]*>',
        caseSensitive: false,
      ).firstMatch(html)?.group(0) ?? '';
      final parsedMaxHours =
          double.tryParse(parser._attr(selectionBar, 'data-max-hours')) ?? 10;
      final maxHours = parsedMaxHours > 0 ? parsedMaxHours : 10.0;

      return DopSelectionFormInfo(
        action: target,
        method: method.isEmpty ? 'GET' : method,
        hiddenFields: List<MapEntry<String, String>>.unmodifiable(hidden),
        submitName: submitName,
        submitValue: submitValue,
        hasUnsupportedControls: hasUnsupportedControls,
        selectionLocked: selectionLocked,
        maxHours: maxHours,
      );
    }
    return null;
  }
}

class DopSelectionFormInfo {
  final Uri action;
  final String method;
  final List<MapEntry<String, String>> hiddenFields;
  final String submitName;
  final String submitValue;
  final bool hasUnsupportedControls;
  final bool selectionLocked;
  final double maxHours;

  const DopSelectionFormInfo({
    required this.action,
    required this.method,
    required this.hiddenFields,
    required this.submitName,
    required this.submitValue,
    this.hasUnsupportedControls = false,
    this.selectionLocked = false,
    this.maxHours = 10,
  });
}

/// A live catalogue and its authenticated intranet cookie session.
class DopCatalogSession {
  final DopStudent student;
  final List<DopProgram> programs;
  final _DopSession _session;
  final DopParser _parser;
  final DopSelectionFormInfo? _form;
  final double maxHours;
  bool _closed = false;

  DopCatalogSession._({
    required this.student,
    required this.programs,
    required _DopSession session,
    required DopParser parser,
    required DopSelectionFormInfo? form,
    required this.maxHours,
  })  : _session = session,
        _parser = parser,
        _form = form;

  bool get selectionLocked => _form?.selectionLocked ?? false;

  bool get canSubmit =>
      !_closed &&
      _form != null &&
      _form.method == 'POST' &&
      !_form.hasUnsupportedControls &&
      !_form.selectionLocked &&
      programs.any((program) => program.subgroups.any((group) =>
          !group.selectionDisabled &&
          group.selectionName.trim().isNotEmpty &&
          group.selectionValue.trim().isNotEmpty));

  /// Submits only real name/value pairs parsed from the school's form.
  /// No guessed endpoint, checkbox name, or subgroup ID is ever sent.
  Future<String> submit(List<DopSubgroup> selections) async {
    if (_closed) {
      throw const DopParserException('Сеанс каталога уже закрыт. Обнови каталог.');
    }
    if (selections.isEmpty) {
      throw const DopParserException('Сначала выбери хотя бы одну группу.');
    }
    final form = _form;
    if (form == null ||
        form.method != 'POST' ||
        form.hasUnsupportedControls ||
        form.selectionLocked) {
      throw DopParserException(
        form?.selectionLocked == true
            ? 'Школа временно закрыла приём заявок на ДОПы. Каталог доступен только для просмотра.'
            : 'На странице каталога не найдена поддерживаемая форма отправки. '
                'Просмотр доступен, но записывать через приложение пока небезопасно.',
      );
    }

    final fields = <MapEntry<String, String>>[
      ...form.hiddenFields,
    ];
    final unique = <String>{};
    final selectedPrograms = <int>{};
    var totalLimitHours = 0;
    for (final group in selections) {
      if (group.selectionDisabled) {
        throw const DopParserException(
          'Школа отключила выбор этой подгруппы. Обнови каталог.',
        );
      }
      if (!selectedPrograms.add(group.programId)) {
        throw const DopParserException(
          'Можно выбрать только одну подгруппу каждой программы.',
        );
      }
      totalLimitHours += group.limitHours;
      if (group.selectionName.trim().isEmpty ||
          group.selectionValue.trim().isEmpty) {
        throw const DopParserException(
          'У выбранной группы не найдены точные параметры checkbox. '
          'Сайт не будет получать выдуманные значения.',
        );
      }
      final key = group.selectionName + '\u0000' + group.selectionValue;
      if (unique.add(key)) {
        fields.add(MapEntry(group.selectionName, group.selectionValue));
      }
    }
    if (totalLimitHours > maxHours + 0.0001) {
      throw DopParserException(
        'Нагрузка, учитываемая школой, составит ' +
            totalLimitHours.toString() +
            ' ч/нед. Допустимый предел — ' +
            maxHours.toStringAsFixed(0) +
            ' ч/нед.',
      );
    }
    for (var i = 0; i < selections.length; i++) {
      for (var j = i + 1; j < selections.length; j++) {
        if (selections[i].programId == selections[j].programId) continue;
        for (final first in selections[i].schedule) {
          for (final second in selections[j].schedule) {
            if (first.day == second.day &&
                first.start <= second.end &&
                second.start <= first.end) {
              throw DopParserException(
                'Расписание «' +
                    selections[i].name +
                    '» пересекается с «' +
                    selections[j].name +
                    '».',
              );
            }
          }
        }
      }
    }
    if (form.submitName.isNotEmpty) {
      fields.add(MapEntry(form.submitName, form.submitValue));
    }

    final response = await _session.postEntries(form.action, fields);
    final error = _parser._textClass(response.body, 'alert-danger');
    if (error.isNotEmpty) {
      throw DopParserException('Intranet отклонил выбор: ' + error);
    }
    final success = _parser._textClass(response.body, 'alert-success');
    if (success.isNotEmpty) return success;
    final notice = _parser._textClass(response.body, 'alert');
    if (notice.isNotEmpty) return notice;
    return 'Ответ intranet получен. Проверь статус выбранных занятий в разделе «Мои ДОПы».';
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _session.close();
  }
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

  Future<_DopResponse> postEntries(
    Uri uri,
    List<MapEntry<String, String>> fields,
  ) =>
      _request('POST', uri, formFields: fields);

  Future<_DopResponse> _request(
    String method,
    Uri uri, {
    Map<String, String> data = const {},
    List<MapEntry<String, String>>? formFields,
  }) async {
    var currentUri = uri;
    var currentMethod = method;
    var currentData = data;

    for (var i = 0; i < 6; i++) {
      if (!DopParser.isTrustedUri(currentUri)) {
        throw const DopParserException(
          'Школьный intranet перенаправил запрос на недоверенный адрес. Cookies не отправлены.',
        );
      }
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

        final fields = formFields ?? currentData.entries.toList();
        request.write(
          fields
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
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
          formFields = null;
        }

        currentUri = currentUri.resolve(location);
        continue;
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 400) {
        throw DopParserException(
          'HTTP ${response.statusCode} при обращении к $currentUri',
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
