import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/ai_navigation_commands.dart';

void main() {
  const catalog = <String>{'202', '319'};

  group('AiNavigationCommandParser', () {
    test('remembers a request to avoid a known classroom', () {
      final commands = AiNavigationCommandParser.parse(
        'Я не хочу идти около 202, проложи альтернативу.',
        knownLocationIds: catalog,
      );

      expect(commands, hasLength(1));
      expect(commands.single.type, AiNavigationCommandType.avoidLocation);
      expect(commands.single.locationId, '202');
    });

    test('removes an avoidance preference when asked', () {
      final commands = AiNavigationCommandParser.parse(
        'Больше не обходи кабинет 202.',
        knownLocationIds: catalog,
      );

      expect(commands, hasLength(1));
      expect(commands.single.type, AiNavigationCommandType.allowLocation);
      expect(commands.single.locationId, '202');
    });

    test('stores route feedback but does not convert it into an avoidance rule', () {
      final commands = AiNavigationCommandParser.parse(
        'Ты неправильно построил маршрут около 319. Перепроверь.',
        knownLocationIds: catalog,
      );

      expect(commands, hasLength(1));
      expect(commands.single.type, AiNavigationCommandType.routeFeedback);
      expect(commands.single.locationId, '319');
    });

    test('rejects a room number absent from the school catalogue', () {
      final commands = AiNavigationCommandParser.parse(
        'Не хочу идти около 999, проложи альтернативу.',
        knownLocationIds: catalog,
      );

      expect(commands, isEmpty);
    });

    test('ordinary mentions do not create preferences', () {
      final commands = AiNavigationCommandParser.parse(
        'На уроке будем обсуждать кабинет 202.',
        knownLocationIds: catalog,
      );

      expect(commands, isEmpty);
    });
  });
}
