import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/ai_navigation_intent.dart';

void main() {
  const locations = <AiNavigationLocation>[
    (id: '214', name: 'Кабинет 214'),
    (id: '215', name: 'Кабинет 215'),
    (id: 'place_library', name: 'Библиотека'),
  ];

  group('AiNavigationIntent', () {
    test('resolves a known room when the local model is not needed', () {
      final intent = AiNavigationIntent.parse(
        'Как пройти в кабинет 215?',
        locations: locations,
      );

      expect(intent?.destinationId, '215');
      expect(intent?.startLocationId, isNull);
    });

    test('preserves an explicit start and destination', () {
      final intent = AiNavigationIntent.parse(
        'Построй маршрут от кабинета 214 до кабинета 215',
        locations: locations,
      );

      expect(intent?.startLocationId, '214');
      expect(intent?.destinationId, '215');
    });

    test('resolves an inflected Russian place name', () {
      final intent = AiNavigationIntent.parse(
        'Как дойти до библиотеки?',
        locations: locations,
      );

      expect(intent?.destinationId, 'place_library');
    });

    test('does not invent destinations absent from the location catalog', () {
      final intent = AiNavigationIntent.parse(
        'Как пройти в кабинет 999?',
        locations: locations,
      );

      expect(intent, isNull);
    });

    test('does not treat an ordinary room mention as a route request', () {
      final intent = AiNavigationIntent.parse(
        'Что находится в кабинете 215?',
        locations: locations,
      );

      expect(intent, isNull);
    });
  });
}
