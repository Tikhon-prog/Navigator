part of '../main.dart';

class RouteEngine {
  // Маршрутизация строится по реальным линиям коридоров из corridor_roads.dart.
  // Двери и лестницы подключаются к ближайшему отрезку перпендикулярной связью.
  // Близкие концы отрезков (< 25 px исходной карты) считаются одним узлом.
  static const double _mapW = 7016.0;
  static const double _mapH = 4960.0;
  static const double _snapPx = 32.0;
  // A room/stair anchor must be close to a mapped corridor. Without this limit,
  // an incorrectly placed door can be connected through a wall to a distant wing.
  static const double _maxAnchorConnectorPx = 450.0;
  // A stair transition is intentionally more expensive than any plausible
  // horizontal route across a school floor. This minimizes floor changes first;
  // within the same number of transitions, A* minimizes real map-pixel distance.
  static const double _stairTransitionPenaltyPx = 100000.0;

  // Переводим нормализованные координаты обратно в пиксели исходной карты.
  // Важно учитывать обе оси: карта 7016x4960, поэтому умножать
  // евклидово расстояние только на ширину было неточно по Y.
  static double _pxDistance(Offset a, Offset b) {
    final dx = (a.dx - b.dx) * _mapW;
    final dy = (a.dy - b.dy) * _mapH;
    return math.sqrt(dx * dx + dy * dy);
  }

  static final Map<String, Offset> _anchors = {
    'entry': DoorPoints.all['place_entrance']!,
    ...DoorPoints.all,
  };

  // Эти места нельзя использовать как транзитные узлы: через них не прокладываем
  // маршрут, но ими можно начать или закончить маршрут.
  static const Set<String> _blockedTransit = {
    'place_canteen',
    'place_pool',
    'place_sport',
    'place_auditorium',
  };

  static List<List<String>> _verticalStairs() => const [
    ['stair_green_upper', 'stair_green_2_upper', 'stair_green_3_upper'],
    ['stair_green_121', 'stair_green_2_lower', 'stair_green_3_lower'],
    ['stair_blue_center', 'stair_blue_2_center', 'stair_blue_3_center'],
    ['stair_purple_108', 'stair_purple_2_lower', 'stair_purple_3_lower'],
    ['stair_purple_upper', 'stair_purple_2_upper', 'stair_purple_3_upper'],
    ['stair_turquoise_lower', 'stair_turquoise_2', 'stair_turquoise_3'],
    // The bottom turquoise stair connects floors 1↔2, but not floor 3.
    ['stair_turquoise_bottom', 'stair_turquoise_2_closed'],
  ];

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  static Offset _project(Offset p, Offset a, Offset b) {
    // Projection must be perpendicular in source-map pixels. The map is 7016×4960,
    // so projecting directly in normalized 0..1 coordinates distorts the angle.
    final pp = Offset(p.dx * _mapW, p.dy * _mapH);
    final aa = Offset(a.dx * _mapW, a.dy * _mapH);
    final bb = Offset(b.dx * _mapW, b.dy * _mapH);
    final v = bb - aa;
    final len2 = v.dx * v.dx + v.dy * v.dy;
    if (len2 <= 1e-12) return a;
    final t = (((pp.dx - aa.dx) * v.dx) + ((pp.dy - aa.dy) * v.dy)) / len2;
    final clamped = t.clamp(0.0, 1.0);
    final projected = Offset(aa.dx + v.dx * clamped, aa.dy + v.dy * clamped);
    return Offset(projected.dx / _mapW, projected.dy / _mapH);
  }

  static Offset? _intersection(Offset a, Offset b, Offset c, Offset d) {
    final r = b - a;
    final s = d - c;
    final den = _cross(r, s);
    if (den.abs() < 1e-10) return null;
    final qmp = c - a;
    final t = _cross(qmp, s) / den;
    final u = _cross(qmp, r) / den;
    if (t < -1e-8 || t > 1.00000001 || u < -1e-8 || u > 1.00000001) return null;
    return Offset(a.dx + r.dx * t, a.dy + r.dy * t);
  }

  static Offset _nearestPointOnSegment(Offset p, CorridorSegment s) => _project(p, s.a, s.b);

  static RouteResult? build(String destinationId, {int startFloor = 1, String? startLocationId}) {
    // startFloor is kept for callers that also select which floor to browse;
    // the real origin is the main entrance unless an explicit location is saved.
    assert(startFloor >= 1 && startFloor <= 3);
    final destination = SchoolData.tryRoom(destinationId);
    if (destination == null) return null;
    final startRoom = startLocationId == null ? null : SchoolData.tryRoom(startLocationId);
    if (startLocationId != null && startRoom == null) return null;
    final effectiveStartFloor = startRoom?.floor ?? 1;

    // A same-location request must succeed even when that point has no corridor
    // connector, and should not build the full graph or show walking directions.
    if (startRoom != null && startRoom.id == destination.id) {
      final point = DoorPoints.of(destination.id, destination.point);
      return RouteResult(
        [RouteNode('same_start', destination.floor, point, 'Точка назначения')],
        destination, 0, destination.floor, startLocationId,
      );
    }

    final segments = CorridorRoads.all;
    final nodes = <String, RouteNode>{};
    final segmentNodeIds = <int, List<String>>{};
    var serial = 0;

    String addNode(int floor, Offset point, String label, {String? preferredId}) {
      final id = preferredId ?? 'road_${serial++}';
      // Snap nearby graph points so tiny coordinate errors do not create holes.
      for (final existing in nodes.values) {
        if (existing.floor == floor && _pxDistance(existing.point, point) <= _snapPx) {
          return existing.id;
        }
      }
      nodes[id] = RouteNode(id, floor, point, label);
      return id;
    }

    String addPointToSegment(int floor, Offset point, String label, int segIndex, {String? preferredId}) {
      final id = addNode(floor, point, label, preferredId: preferredId);
      segmentNodeIds.putIfAbsent(segIndex, () => <String>[]).add(id);
      return id;
    }

    // Every road endpoint is a graph node.
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      addPointToSegment(s.floor, s.a, s.label, i);
      addPointToSegment(s.floor, s.b, s.label, i);
    }

    // Split roads at every true intersection.
    for (var i = 0; i < segments.length; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        final a = segments[i];
        final b = segments[j];
        if (a.floor != b.floor) continue;
        final p = _intersection(a.a, a.b, b.a, b.b);
        if (p == null) continue;
        final id = addNode(a.floor, p, 'Перекрёсток');
        segmentNodeIds.putIfAbsent(i, () => <String>[]).add(id);
        segmentNodeIds.putIfAbsent(j, () => <String>[]).add(id);
      }
    }

    // Add perpendicular connectors from doors/places/stairs to roads.
    // Transit-restricted spaces stay disconnected unless they are the explicit
    // start or destination of this route.
    final anchorNode = <String, String>{};
    final anchorRoadNode = <String, String>{};
    final requestedAnchors = <String>{destination.id};
    if (startLocationId != null) requestedAnchors.add(startLocationId);
    // Keep the hand-mapped door points, but do not make routing depend on every
    // room already having an explicit DoorPoints entry: use its catalog point
    // as a safe, bounded fallback for the requested origin/destination.
    final routeAnchors = <String, Offset>{..._anchors};
    routeAnchors.putIfAbsent(destination.id, () => DoorPoints.of(destination.id, destination.point));
    if (startRoom != null) {
      routeAnchors.putIfAbsent(startRoom.id, () => DoorPoints.of(startRoom.id, startRoom.point));
    }
    for (final entry in routeAnchors.entries) {
      final id = entry.key;
      if (_blockedTransit.contains(id) && !requestedAnchors.contains(id)) continue;
      final p = entry.value;
      final floor = _anchorFloor(id);
      if (floor == null) continue;
      var bestDistance = double.infinity;
      var bestSegment = -1;
      var bestPoint = p;
      for (var i = 0; i < segments.length; i++) {
        final s = segments[i];
        if (s.floor != floor) continue;
        final q = _nearestPointOnSegment(p, s);
        final d = _pxDistance(p, q);
        if (d < bestDistance) {
          bestDistance = d;
          bestSegment = i;
          bestPoint = q;
        }
      }
      // Do not invent a corridor connection when the nearest mapped corridor is
      // too far away: that usually means the door anchor or corridor graph is wrong.
      if (bestSegment < 0 || bestDistance > _maxAnchorConnectorPx) continue;
      final roadId = addPointToSegment(floor, bestPoint, 'Подключение: $id', bestSegment);
      final aId = addNode(floor, p, 'Точка: $id', preferredId: 'anchor_$id');
      anchorNode[id] = aId;
      anchorRoadNode[id] = roadId;
    }

    // Build bidirectional graph from each ordered set of points on a segment.
    final graph = <String, List<RouteEdge>>{};
    void connect(String a, String b, double cost) {
      if (a == b) return;
      graph.putIfAbsent(a, () => []).add(RouteEdge(a, b, cost));
      graph.putIfAbsent(b, () => []).add(RouteEdge(b, a, cost));
    }

    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final ids = <String>{...(segmentNodeIds[i] ?? const <String>[])}.toList();
      ids.sort((a, b) {
        final pa = nodes[a]!.point;
        final pb = nodes[b]!.point;
        final v = s.b - s.a;
        final ta = ((pa.dx - s.a.dx) * v.dx + (pa.dy - s.a.dy) * v.dy);
        final tb = ((pb.dx - s.a.dx) * v.dx + (pb.dy - s.a.dy) * v.dy);
        return ta.compareTo(tb);
      });
      for (var k = 1; k < ids.length; k++) {
        final a = nodes[ids[k - 1]]!;
        final b = nodes[ids[k]]!;
        connect(a.id, b.id, _pxDistance(a.point, b.point));
      }
    }

    // Connect every anchor to its own perpendicular projection on the road.
    for (final entry in anchorNode.entries) {
      final anchorId = entry.value;
      final roadId = anchorRoadNode[entry.key];
      if (roadId == null || anchorId == roadId) continue;
      final anchorPoint = nodes[anchorId]!.point;
      final roadPoint = nodes[roadId]!.point;
      connect(anchorId, roadId, _pxDistance(anchorPoint, roadPoint));
    }

    // Vertical stair links. The closed turquoise stair is deliberately omitted from 2↔3.
    for (final chain in _verticalStairs()) {
      for (var i = 0; i + 1 < chain.length; i++) {
        final aId = anchorNode[chain[i]];
        final bId = anchorNode[chain[i + 1]];
        if (aId == null || bId == null) continue;
        final a = nodes[aId]!;
        final b = nodes[bId]!;
        // Смена этажа должна стоить заметно дороже обычного участка коридора,
      // иначе алгоритм выбирает лестницу даже для маршрута на том же этаже.
      connect(a.id, b.id, _stairTransitionPenaltyPx + _pxDistance(a.point, b.point));
      }
    }

    // Main entrance is always on floor 1. A browsing-floor selection must not
    // fabricate an origin point on the second or third floor.
    final sourceAnchor = startRoom == null ? 'entry' : startRoom.id;
    final source = anchorNode[sourceAnchor];
    final target = anchorNode[destination.id];
    if (source == null || target == null) return null;

    // Prefer a fully same-floor path whenever one exists. A large stair penalty
    // alone is not a guarantee: bad/overlapping map geometry can make a valid
    // same-floor path appear more expensive than a stair shortcut.
    (Map<String, double>, Map<String, String?>) search({required bool sameFloorOnly}) {
      final distance = <String, double>{source: 0};
      final previous = <String, String?>{source: null};
      final open = <_QueueItem>[_QueueItem(source, 0, 0)];

      double heuristic(String id) {
        final a = nodes[id];
        final b = nodes[target];
        if (a == null || b == null) return 0;
        return _pxDistance(a.point, b.point) +
            (sameFloorOnly ? 0 : (a.floor - b.floor).abs() * _stairTransitionPenaltyPx);
      }

      while (open.isNotEmpty) {
        open.sort((a, b) => a.priority.compareTo(b.priority));
        final current = open.removeAt(0);
        final best = distance[current.id];
        if (best == null || current.g > best + 1e-9) continue;
        if (current.id == target) break;
        for (final edge in graph[current.id] ?? const <RouteEdge>[]) {
          if (sameFloorOnly && nodes[edge.a]!.floor != nodes[edge.b]!.floor) continue;
          final nextG = best + edge.cost;
          if (nextG < (distance[edge.b] ?? double.infinity)) {
            distance[edge.b] = nextG;
            previous[edge.b] = current.id;
            open.add(_QueueItem(edge.b, nextG, nextG + heuristic(edge.b)));
          }
        }
      }
      return (distance, previous);
    }

    final preferSameFloor = effectiveStartFloor == destination.floor;
    final firstSearch = search(sameFloorOnly: preferSameFloor);
    final selectedSearch = firstSearch.$1.containsKey(target)
        ? firstSearch
        : search(sameFloorOnly: false);
    final distance = selectedSearch.$1;
    final previous = selectedSearch.$2;
    if (!distance.containsKey(target)) return null;

    final ids = <String>[];
    String? cursor = target;
    while (cursor != null) {
      ids.add(cursor);
      cursor = previous[cursor];
    }
    final path = ids.reversed.map((id) => nodes[id]!).toList();

    // Graph anchor nodes exactly represent the same doorway points added below
    // for display. Drop those duplicates so the route has one clean start and end.
    if (path.isNotEmpty && path.first.id == source) path.removeAt(0);
    if (path.isNotEmpty && path.last.id == target) path.removeLast();

    // Replace technical anchor nodes with readable door/start labels.
    if (startRoom != null) {
      path.insert(0, RouteNode('start_room_${startRoom.id}', startRoom.floor, DoorPoints.of(startRoom.id, startRoom.point), SchoolData.title(startRoom)));
    }
    if (startRoom == null) {
      path.insert(0, RouteNode('start_entry', effectiveStartFloor, DoorPoints.all['place_entrance']!, 'Главный вход'));
    }
    path.add(RouteNode('destination_door_${destination.id}', destination.floor, DoorPoints.of(destination.id, destination.point), SchoolData.title(destination)));

    final displayPath = _simplifyPath(path);
    return RouteResult(displayPath, destination, distance[target]!, effectiveStartFloor, startLocationId);
  }

  static List<RouteNode> _simplifyPath(List<RouteNode> input) {
    if (input.length < 3) return List<RouteNode>.unmodifiable(input);
    final points = List<RouteNode>.from(input);
    var changed = true;
    // Remove only geometry nodes that sit on a straight continuation. Semantic
    // endpoints and stair anchors are retained; topology itself is never edited.
    while (changed) {
      changed = false;
      for (var i = 1; i < points.length - 1; i++) {
        final prev = points[i - 1];
        final current = points[i];
        final next = points[i + 1];
        if (prev.floor != current.floor || current.floor != next.floor) continue;
        if (!current.id.startsWith('road_')) continue;
        final v1 = Offset(
          (current.point.dx - prev.point.dx) * _mapW,
          (current.point.dy - prev.point.dy) * _mapH,
        );
        final v2 = Offset(
          (next.point.dx - current.point.dx) * _mapW,
          (next.point.dy - current.point.dy) * _mapH,
        );
        final len1 = v1.distance;
        final len2 = v2.distance;
        if (len1 < 2 || len2 < 2) continue;
        final cross = _cross(v1, v2).abs();
        final dot = v1.dx * v2.dx + v1.dy * v2.dy;
        // Only collapse forward collinear points, not U-turns or tight corners.
        if (dot <= 0 || cross / (len1 * len2) > 0.035) continue;
        // Compute the projection in original map pixels. Projecting in normalized
        // 0..1 coordinates would distort the result because the source map is not square.
        final prevPx = Offset(prev.point.dx * _mapW, prev.point.dy * _mapH);
        final currentPx = Offset(current.point.dx * _mapW, current.point.dy * _mapH);
        final nextPx = Offset(next.point.dx * _mapW, next.point.dy * _mapH);
        final chord = nextPx - prevPx;
        final chordLength2 = chord.dx * chord.dx + chord.dy * chord.dy;
        if (chordLength2 <= 1e-12) continue;
        final t = (((currentPx.dx - prevPx.dx) * chord.dx) +
                ((currentPx.dy - prevPx.dy) * chord.dy)) /
            chordLength2;
        final projectedPx = Offset(
          prevPx.dx + chord.dx * t,
          prevPx.dy + chord.dy * t,
        );
        final projected = Offset(projectedPx.dx / _mapW, projectedPx.dy / _mapH);
        if (_pxDistance(current.point, projected) > 10) continue;
        points.removeAt(i);
        changed = true;
        break;
      }
    }
    return List<RouteNode>.unmodifiable(points);
  }

  static int? _anchorFloor(String id) {
    if (id == 'entry') return 1;
    final r = SchoolData.tryRoom(id);
    if (r != null) return r.floor;
    if (id.contains('_2_') || id.endsWith('_2')) return 2;
    if (id.contains('_3_') || id.endsWith('_3')) return 3;
    if (id == 'stair_green_upper' || id == 'stair_green_121' || id == 'stair_blue_center' || id == 'stair_purple_108' || id == 'stair_purple_upper' || id == 'stair_turquoise_lower' || id == 'stair_turquoise_bottom') return 1;
    return null;
  }

  static List<RouteStep> instructions(RouteResult result) {
    final path = _simplifyPath(result.nodes);
    if (path.isEmpty) return const [];
    if (path.any((node) => node.id == 'same_start')) {
      return [RouteStep(
        result.destination.floor,
        'Вы уже находитесь у места «${SchoolData.title(result.destination)}».',
        Icons.check_circle_outline_rounded,
      )];
    }
    final steps = <RouteStep>[];
    if (result.startLocationId == null) {
      steps.add(RouteStep(1, 'Начните от главного входа на 1-м этаже.', Icons.directions_walk_rounded));
    } else {
      final start = SchoolData.tryRoom(result.startLocationId!);
      if (start == null) return const [];
      steps.add(RouteStep(start.floor, 'Выйдите из ${SchoolData.title(start)} через дверь в коридор.', Icons.exit_to_app_rounded));
    }
    for (var i = 1; i < path.length; i++) {
      final prev = path[i - 1];
      final cur = path[i];
      if (cur.floor != prev.floor) {
        steps.add(RouteStep(cur.floor, cur.floor > prev.floor
            ? 'Поднимитесь по лестнице на ${cur.floor}-й этаж.'
            : 'Спуститесь по лестнице на ${cur.floor}-й этаж.', Icons.stairs_rounded));
        continue;
      }
      if (cur.id.startsWith('destination_door_')) {
        steps.add(RouteStep(cur.floor, 'Вы прибыли: ${SchoolData.title(result.destination)}.', Icons.flag_rounded));
        continue;
      }
      if (i + 1 < path.length) {
        final next = path[i + 1];
        final v1 = Offset(
          (cur.point.dx - prev.point.dx) * _mapW,
          (cur.point.dy - prev.point.dy) * _mapH,
        );
        final v2 = Offset(
          (next.point.dx - cur.point.dx) * _mapW,
          (next.point.dy - cur.point.dy) * _mapH,
        );
        if (v1.distance < 2 || v2.distance < 2) continue;
        final cross = _cross(v1, v2);
        final dot = v1.dx * v2.dx + v1.dy * v2.dy;
        final angle = math.atan2(cross, dot) * 180 / math.pi;
        if (angle.abs() < 28) continue;
        if (angle.abs() >= 150) {
          steps.add(RouteStep(cur.floor, 'Развернитесь и двигайтесь в обратном направлении.', Icons.turn_left_rounded));
        } else {
          final right = angle > 0;
          steps.add(RouteStep(
            cur.floor,
            '${right ? 'Поверните направо' : 'Поверните налево'} и продолжайте по коридору.',
            right ? Icons.turn_right_rounded : Icons.turn_left_rounded,
          ));
        }
      }
    }
    return _dedupe(steps);
  }

  static List<RouteStep> _dedupe(List<RouteStep> source) {
    final out = <RouteStep>[];
    for (final step in source) {
      if (out.isNotEmpty && out.last.floor == step.floor && out.last.text == step.text) continue;
      out.add(step);
    }
    return out;
  }
}

class _QueueItem {
  final String id;
  final double g;
  final double priority;
  const _QueueItem(this.id, this.g, this.priority);
}
