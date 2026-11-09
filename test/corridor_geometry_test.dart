import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/corridor_roads.dart';

void main() {
  group('Corridor geometry', () {
    const mapWidth = 7016.0;
    const mapHeight = 4960.0;

    double distance(Offset a, Offset b) => math.sqrt(
          math.pow((a.dx - b.dx) * mapWidth, 2) +
              math.pow((a.dy - b.dy) * mapHeight, 2),
        );

    test('every corridor segment has a valid floor and normalized endpoints', () {
      for (final segment in CorridorRoads.all) {
        expect(segment.floor, inInclusiveRange(1, 3), reason: segment.label);
        for (final point in [segment.a, segment.b]) {
          expect(point.dx, inInclusiveRange(0, 1), reason: '${segment.label} x');
          expect(point.dy, inInclusiveRange(0, 1), reason: '${segment.label} y');
        }
        expect(distance(segment.a, segment.b), greaterThan(1),
            reason: 'Zero-length or near-zero corridor: ${segment.label}');
      }
      for (final floor in [1, 2, 3]) {
        expect(CorridorRoads.all.any((segment) => segment.floor == floor), isTrue,
            reason: 'No corridor segments exist for floor $floor');
      }
    });

    test('no same-floor collinear lines duplicate a long walkable segment', () {
      final segments = CorridorRoads.all;
      for (var i = 0; i < segments.length; i++) {
        final a = segments[i];
        final ax = (a.b.dx - a.a.dx) * mapWidth;
        final ay = (a.b.dy - a.a.dy) * mapHeight;
        final aLength = math.sqrt(ax * ax + ay * ay);
        if (aLength < 100) continue;
        final ux = ax / aLength;
        final uy = ay / aLength;
        for (var j = i + 1; j < segments.length; j++) {
          final b = segments[j];
          if (a.floor != b.floor) continue;
          final bx = (b.b.dx - b.a.dx) * mapWidth;
          final by = (b.b.dy - b.a.dy) * mapHeight;
          final bLength = math.sqrt(bx * bx + by * by);
          if (bLength < 100) continue;

          final parallel = ((ax * bx + ay * by) / (aLength * bLength)).abs();
          if (parallel < .999) continue;

          double projection(Offset p) =>
              ((p.dx - a.a.dx) * mapWidth * ux) +
              ((p.dy - a.a.dy) * mapHeight * uy);
          double perpendicular(Offset p) =>
              (((p.dx - a.a.dx) * mapWidth * uy) -
                      ((p.dy - a.a.dy) * mapHeight * ux))
                  .abs();

          final p0 = projection(b.a);
          final p1 = projection(b.b);
          final bLow = math.min(p0, p1);
          final bHigh = math.max(p0, p1);
          final overlap = math.max(0.0, math.min(aLength, bHigh) - math.max(0.0, bLow));
          final maxOffset = math.max(perpendicular(b.a), perpendicular(b.b));

          expect(
            overlap > 400 && maxOffset <= 12,
            isFalse,
            reason: 'Overlapping same-floor segments need review: ${a.label} / ${b.label}',
          );
        }
      }
    });

    test('no pair of same-floor corridor segments is an exact duplicate', () {
      final segments = CorridorRoads.all;
      for (var i = 0; i < segments.length; i++) {
        for (var j = i + 1; j < segments.length; j++) {
          final a = segments[i];
          final b = segments[j];
          if (a.floor != b.floor) continue;
          final same = (distance(a.a, b.a) < 2 && distance(a.b, b.b) < 2) ||
              (distance(a.a, b.b) < 2 && distance(a.b, b.a) < 2);
          expect(same, isFalse, reason: 'Exact duplicate corridor: ${a.label} / ${b.label}');
        }
      }
    });
  });
}
