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

    test('main entrance remains on the first floor when another map floor is selected', () {
      final result = RouteEngine.build('104', startFloor: 3);

      expect(result, isNotNull);
      expect(result!.startFloor, 1);
      expect(result.changesFloor, isFalse);
      expect(result.nodes.every((node) => node.floor == 1), isTrue);
    });

    test('main entrance to another floor reports the real origin', () {
      final result = RouteEngine.build('201', startFloor: 3);

      expect(result, isNotNull);
      expect(result!.startFloor, 1);
      expect(result.nodes.first.floor, 1);
      expect(result.destination.floor, 2);
      expect(result.changesFloor, isTrue);
    });

    test('unknown route destination returns null rather than throwing', () {
      expect(RouteEngine.build('not-a-real-room'), isNull);
    });

    test('unknown route origin returns null rather than throwing', () {
      expect(RouteEngine.build('201', startLocationId: 'not-a-real-room'), isNull);
    });

    test('same room produces a zero-distance route', () {
      final result = RouteEngine.build('311', startFloor: 3, startLocationId: '311');

      expect(result, isNotNull);
      expect(result!.distance, 0);
      expect(result.changesFloor, isFalse);
      expect(RouteEngine.instructions(result).single.text, contains('Вы уже находитесь'));
    });
  });

  group('SchoolData room catalog regression tests', () {
    const firstFloorRooms = <String>[
      '101', '101.1', '102', '103', '104',
      '105', '106', '107', '108', '109',
      '110', '111', '112', '113', '114',
      '115', '116', '117', '118', '119',
    ];

    for (final roomId in firstFloorRooms) {
      test('room $roomId exists in the catalog on floor 1', () {
        final room = SchoolData.tryRoom(roomId);

        expect(room, isNotNull, reason: 'Room $roomId should be searchable');
        expect(room!.id, roomId);
        expect(room.floor, 1);
        expect(SchoolData.locations.contains(room), isTrue);
      });
    }
  });
}
