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

  group('Route detour regression checks', () {
    void expectShortSymmetricRoute({
      required String from,
      required String to,
      required int floor,
      required double maximumPixels,
    }) {
      final forward = RouteEngine.build(to, startFloor: floor, startLocationId: from);
      final backward = RouteEngine.build(from, startFloor: floor, startLocationId: to);

      expect(forward, isNotNull, reason: '$from → $to should be routable');
      expect(backward, isNotNull, reason: '$to → $from should be routable');
      expect(forward!.changesFloor, isFalse);
      expect(backward!.changesFloor, isFalse);
      expect(forward.nodes.every((node) => node.floor == floor), isTrue);
      expect(backward.nodes.every((node) => node.floor == floor), isTrue);
      expect(forward.distance, lessThan(maximumPixels),
          reason: '$from → $to contains an unexpectedly long detour');
      expect((forward.distance - backward.distance).abs(), lessThan(1.0),
          reason: 'The corridor graph should be direction-symmetric');
    }

    test('third-floor corridor around 317/318 is short in both directions', () {
      expectShortSymmetricRoute(from: '317', to: '318', floor: 3, maximumPixels: 300);
    });

    test('third-floor local connection around 315–317 has no long detour', () {
      expectShortSymmetricRoute(from: '317', to: '315', floor: 3, maximumPixels: 600);
      expectShortSymmetricRoute(from: '316', to: '317', floor: 3, maximumPixels: 450);
    });

    test('second-floor route 201–209 stays within that floor', () {
      expectShortSymmetricRoute(from: '201', to: '209', floor: 2, maximumPixels: 2500);
    });

    test('first-floor route 101–130 stays within that floor', () {
      expectShortSymmetricRoute(from: '101', to: '130', floor: 1, maximumPixels: 2000);
    });

    test('route to room 214 from room 215 is symmetric and same-floor', () {
      expectShortSymmetricRoute(from: '215', to: '214', floor: 2, maximumPixels: 6000);
    });
  });

