import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/ai_navigation_intent.dart';

void main() {
  const catalog = <String>{'201', '215', 'place_canteen'};

  group('AiNavigationIntent', () {
    test('resolves a destination with a named routing request', () {
      final intent = AiNavigationIntent.parse(
        'Как пройти в кабинет 215?',
        knownRoomIds: catalog,
      );

      expect(intent, isNotNull);
      expect(intent!.destinationId, '215');
      expect(intent.startLocationId, isNull);
    });

    test('resolves explicit start and destination rooms', () {
      final intent = AiNavigationIntent.parse(
        'Построй маршрут от кабинета 215 до кабинета 201',
        knownRoomIds: catalog,
      );

      expect(intent, isNotNull);
      expect(intent!.startLocationId, '215');
      expect(intent.destinationId, '201');
    });

    test('does not treat an ordinary room-number mention as a route request', () {
      expect(
        AiNavigationIntent.parse(
          'Расскажи, что находится в кабинете 215',
          knownRoomIds: catalog,
        ),
        isNull,
      );
    });

    test('rejects neural candidates that name a room outside the bundled catalog', () {
      final intent = AiNavigationIntent.fromModelCandidate(
        {'destinationId': '999', 'startLocationId': '215'},
        knownRoomIds: catalog,
      );

      expect(intent, isNull);
    });

    test('accepts a neural candidate only when all referenced rooms exist', () {
      final intent = AiNavigationIntent.fromModelCandidate(
        {'destinationId': '201', 'startLocationId': '215'},
        knownRoomIds: catalog,
      );

      expect(intent, isNotNull);
      expect(intent!.startLocationId, '215');
      expect(intent.destinationId, '201');
    });

    test('does not invent a route for a room absent from the offline catalog', () {
      expect(
        AiNavigationIntent.parse(
          'Как пройти в кабинет 999?',
          knownRoomIds: catalog,
        ),
        isNull,
      );
    });
  });
}
