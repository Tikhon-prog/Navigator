import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/main.dart';

void main() {
  group('RouteEngine school navigation', () {
    test('311 to 317 stays on the third floor', () {
      final result = RouteEngine.build('317', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.changesFloor, isFalse);
      expect(result.nodes.first.floor, 3);
      expect(result.nodes.last.floor, 3);
      expect(result.destination.id, '317');
    });

    test('311 to 316 stays on the third floor', () {
      final result = RouteEngine.build('316', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.changesFloor, isFalse);
      expect(result.nodes.every((node) => node.floor == 3), isTrue);
      expect(result.destination.id, '316');
    });

    test('311 to 318 stays on the third floor', () {
      final result = RouteEngine.build('318', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.changesFloor, isFalse);
      expect(result.nodes.every((node) => node.floor == 3), isTrue);
      expect(result.destination.id, '318');
    });

    test('311 to 201 changes from third to second floor', () {
      final result = RouteEngine.build('201', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.changesFloor, isTrue);
      expect(result.startFloor, 3);
      expect(result.destination.floor, 2);
      expect(result.nodes.any((node) => node.floor == 2), isTrue);
    });

    test('104 to food block stays on the first floor', () {
      final result = RouteEngine.build(
        'place_food',
        startFloor: 1,
        startLocationId: '104',
      );

      expect(result, isNotNull);
      expect(result!.destination.id, 'place_food');
      expect(result.changesFloor, isFalse);
      expect(result.nodes.every((node) => node.floor == 1), isTrue);
    });

    test('215 to 201 stays on the second floor', () {
      final result = RouteEngine.build(
        '201',
        startFloor: 2,
        startLocationId: '215',
      );

      expect(result, isNotNull);
      expect(result!.changesFloor, isFalse);
      expect(result.nodes.every((node) => node.floor == 2), isTrue);
    });

    test('same room produces a zero-distance route', () {
      final result = RouteEngine.build('311', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.distance, 0);
      expect(result.changesFloor, isFalse);
    });
  });
}
