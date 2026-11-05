import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/ai_schedule_commands.dart';

void main() {
  group('AiMathScheduleParser', () {
    test('one named subject fills every mathematics slot for that day', () {
      final draft = AiMathScheduleParser.parse(
        'Во вторник геома',
        mathSlotsByDay: {2: 3},
      );

      expect(draft, isNotNull);
      expect(draft!.errors, isEmpty);
      expect(draft.isComplete, isTrue);
      expect(draft.completedAssignments[2], [
        'Геометрия',
        'Геометрия',
        'Геометрия',
      ]);
    });

    test('asks for an unspecified third mathematics lesson', () {
      final draft = AiMathScheduleParser.parse(
        'В среду ВиС и алгебра',
        mathSlotsByDay: {3: 3},
      );

      expect(draft, isNotNull);
      expect(draft!.assignments[3], [
        'Вероятность и статистика',
        'Алгебра',
        null,
      ]);
      expect(draft.missingSlots, [const AiMathSlot(3, 2)]);
      expect(draft.isComplete, isFalse);
    });

    test('the missing lesson can be supplied, then the complete draft is ready', () {
      final draft = AiMathScheduleParser.parse(
        'В среду ВиС и алгебра',
        mathSlotsByDay: {3: 3},
      )!;

      expect(draft.fillNext('геома'), 'Геометрия');
      expect(draft.isComplete, isTrue);
      expect(draft.completedAssignments[3], [
        'Вероятность и статистика',
        'Алгебра',
        'Геометрия',
      ]);
    });

    test('parses multiple days independently', () {
      final draft = AiMathScheduleParser.parse(
        'Во вторник геома, а в среду ВиС и алгебра',
        mathSlotsByDay: {2: 3, 3: 3},
      );

      expect(draft, isNotNull);
      expect(draft!.assignments[2], [
        'Геометрия',
        'Геометрия',
        'Геометрия',
      ]);
      expect(draft.assignments[3], [
        'Вероятность и статистика',
        'Алгебра',
        null,
      ]);
      expect(draft.missingSlots.length, 1);
      expect(draft.missingSlots.single.day, 3);
    });

    test('does not invent a mathematics slot on a day without maths', () {
      final draft = AiMathScheduleParser.parse(
        'В четверг алгебра',
        mathSlotsByDay: {4: 0},
      );

      expect(draft, isNotNull);
      expect(draft!.assignments, isEmpty);
      expect(draft.errors, isNotEmpty);
    });

    test('rejects more subjects than available mathematics lessons', () {
      final draft = AiMathScheduleParser.parse(
        'В среду геома, алгебра и ВиС',
        mathSlotsByDay: {3: 2},
      );

      expect(draft, isNotNull);
      expect(draft!.assignments, isEmpty);
      expect(draft.errors, isNotEmpty);
    });

    test('ordinary text without a weekday is not a schedule command', () {
      expect(
        AiMathScheduleParser.parse(
          'Поставь геометрию',
          mathSlotsByDay: {2: 3},
        ),
        isNull,
      );
    });
  });
}
