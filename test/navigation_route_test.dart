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

    test('311 to 201 changes from third to second floor', () {
      final result = RouteEngine.build('201', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.changesFloor, isTrue);
      expect(result.startFloor, 3);
      expect(result.destination.floor, 2);
      expect(result.nodes.any((node) => node.floor == 2), isTrue);
    });

    test('same room produces a zero-distance route', () {
      final result = RouteEngine.build('311', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.distance, 0);
      expect(result.changesFloor, isFalse);
    });
  });
}
