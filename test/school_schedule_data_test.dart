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
        expect(lesson['group'], anyOf(1, 2));
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
}