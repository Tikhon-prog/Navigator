import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('встроенное расписание содержит все 33 класса и непустые уроки', () async {
    final raw = await rootBundle.loadString(
      'assets/data/school_schedule_2026-10-05.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final classes = data['classes'] as Map<String, dynamic>;
    final order = data['class_order'] as Map<String, dynamic>;
    final orderedClasses = order.values
        .expand((value) => value as List<dynamic>)
        .cast<String>()
        .toList();

    expect(classes.length, 33);
    expect(orderedClasses.length, 33);
    expect(orderedClasses.toSet().length, 33);
    expect(orderedClasses.toSet(), classes.keys.toSet());

    for (final className in orderedClasses) {
      final classData = classes[className] as Map<String, dynamic>;
      final variants = classData['variants'] as List<dynamic>;
      expect(variants, isNotEmpty, reason: 'Нет уроков у $className');
      for (final item in variants) {
        final lesson = item as Map<String, dynamic>;
        expect(lesson['day'], inInclusiveRange(1, 7));
        expect((lesson['time'] as String?)?.trim(), isNotEmpty);
        expect((lesson['subject'] as String?)?.trim(), isNotEmpty);
        final room = (lesson['room'] as String?)?.trim() ?? '';
        final rawLesson = (lesson['raw'] as String?)?.trim() ?? '';
        // Some real source rows (for example, swimming lessons) do not name a room.
        // Do not invent a cabinet; verify that the original source row is retained.
        if (room.isEmpty) {
          expect(rawLesson, isNotEmpty, reason: 'У урока без кабинета потеряна исходная строка: $className');
          expect(RegExp(r'\bауд\.\s*\d+', caseSensitive: false).hasMatch(rawLesson), isFalse,
              reason: 'В исходной строке есть номер кабинета, но он не извлечён: $className');
        }
        expect(lesson['group'], anyOf(0, 1, 2, 3));
      }
    }
  });

  test('время уроков содержит распознаваемое начало HH:mm', () async {
    final raw = await rootBundle.loadString(
      'assets/data/school_schedule_2026-10-05.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final classes = data['classes'] as Map<String, dynamic>;
    final startPattern = RegExp(r'^\s*\d{1,2}:\d{2}');
    for (final entry in classes.entries) {
      final variants =
          (entry.value as Map<String, dynamic>)['variants'] as List<dynamic>;
      for (final item in variants) {
        final lesson = item as Map<String, dynamic>;
        expect(
          startPattern.hasMatch('${lesson['time']}'),
          isTrue,
          reason: 'Некорректное время в классе ${entry.key}: ${lesson['time']}',
        );
      }
    }
  });


  test('расписание 8В обновлено на вторую четверть без изменения остальных классов', () async {
    final raw = await rootBundle.loadString(
      'assets/data/school_schedule_2026-10-05.json',
    );
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final classes = data['classes'] as Map<String, dynamic>;
    final class8v = classes['8В'] as Map<String, dynamic>;
    final variants = (class8v['variants'] as List).cast<Map<String, dynamic>>();

    expect(class8v['period'], '2 четверть');
    expect(class8v['local_override'], isTrue);
    expect(variants, hasLength(64));
    expect(classes['8А'], isNot(class8v));
    expect((classes['8А'] as Map<String, dynamic>)['period'], isNull);

    bool hasLesson({
      required int day,
      required String time,
      required int group,
      required String subject,
      String? room,
    }) =>
        variants.any((lesson) =>
            lesson['day'] == day &&
            lesson['time'] == time &&
            lesson['group'] == group &&
            (lesson['subject'] as String).contains(subject) &&
            (room == null || lesson['room'] == room));

    expect(
      hasLesson(
        day: 1,
        time: '08:00 - 08:40',
        group: 0,
        subject: 'Разговоры о важном',
        room: '125',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 2,
        time: '10:20 - 11:00',
        group: 1,
        subject: 'Математика',
        room: '103',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 2,
        time: '10:20 - 11:00',
        group: 2,
        subject: 'Математика',
        room: '102',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 3,
        time: '16:30 - 17:10',
        group: 1,
        subject: 'Великие достижения',
        room: '323',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 3,
        time: '16:30 - 17:10',
        group: 2,
        subject: 'Введение в искусственный интеллект',
        room: '130',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 4,
        time: '10:20 - 11:00',
        group: 1,
        subject: 'Информатика',
        room: '312',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 4,
        time: '11:20 - 12:00',
        group: 1,
        subject: 'Информатика',
        room: '226',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 4,
        time: '14:40 - 15:20',
        group: 2,
        subject: 'Алгоритмизация и программирование',
        room: '130',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 5,
        time: '08:30 - 09:10',
        group: 0,
        subject: 'Физическая культура',
      ),
      isTrue,
    );
    expect(
      hasLesson(
        day: 6,
        time: '08:30 - 09:10',
        group: 1,
        subject: 'Математика',
        room: '103',
      ),
      isTrue,
    );
  });
}