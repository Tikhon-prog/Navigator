/// Small, deterministic route-intent resolver used before loading the local LLM.
///
/// It only returns IDs that exist in the packaged school location catalog. The
/// actual route is always calculated by RouteEngine; this class never creates
/// corridor geometry or guesses a destination.
typedef AiNavigationLocation = ({String id, String name});

class AiNavigationIntent {
  final String destinationId;
  final String? startLocationId;

  const AiNavigationIntent({
    required this.destinationId,
    this.startLocationId,
  });

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\\s+'), ' ').trim();

  static bool looksLikeRouteRequest(String value) {
    final query = _normalize(value);
    const markers = [
      'маршрут',
      'пролож',
      'как пройти',
      'как дойти',
      'как попасть',
      'построй путь',
      'путь до',
      'путь от',
      'пройти до',
      'дойди до',
      'добраться до',
      'дорога до',
    ];
    return markers.any(query.contains);
  }

  /// Resolves numeric room IDs and unambiguous location names from the catalog.
  ///
  /// An explicit "от ... до ..." request uses its first and last resolved
  /// locations as origin and destination. Otherwise the last matching location
  /// is treated as the destination and the app's saved start point is retained.
  static AiNavigationIntent? parse(
    String rawQuery, {
    required Iterable<AiNavigationLocation> locations,
  }) {
    final query = _normalize(rawQuery);
    if (!looksLikeRouteRequest(query)) return null;

    final known = locations
        .where((location) => location.id.trim().isNotEmpty)
        .toList(growable: false);
    if (known.isEmpty) return null;

    final candidates = <({int index, int length, String id})>[];
    final knownIds = known.map((location) => location.id.trim()).toSet();

    final numericPattern = RegExp(r'(?<!\\d)(\\d{3}(?:\\.\\d+)?)(?!\\d)');
    for (final match in numericPattern.allMatches(query)) {
      final id = match.group(1);
      if (id != null && knownIds.contains(id)) {
        candidates.add((
          index: match.start,
          length: match.end - match.start,
          id: id,
        ));
      }
    }

    for (final location in known) {
      final name = _normalize(location.name);
      if (name.length < 4) continue;

      var index = query.indexOf(name);
      var matchedLength = name.length;
      if (index < 0) {
        // Russian location names often appear in a declined form:
        // "библиотека" -> "к библиотеке", "столовая" -> "в столовую".
        final stem = name.replaceFirst(RegExp(r'[аяоеиы]$'), '');
        if (stem.length < 4) continue;
        index = query.indexOf(stem);
        matchedLength = stem.length;
      }

      if (index >= 0) {
        candidates.add((
          index: index,
          length: matchedLength,
          id: location.id.trim(),
        ));
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byPosition = a.index.compareTo(b.index);
      if (byPosition != 0) return byPosition;
      return b.length.compareTo(a.length);
    });

    // Several catalog labels may resolve to one ID (for example, a room's
    // numeric ID and its full display name). Keep one occurrence per ID.
    final unique = <({int index, int length, String id})>[];
    for (final candidate in candidates) {
      if (!unique.any((entry) => entry.id == candidate.id)) {
        unique.add(candidate);
      }
    }
    if (unique.isEmpty) return null;

    final explicitOrigin = RegExp(r'\\b(?:от|из)\\b').hasMatch(query) &&
        RegExp(r'\\bдо\\b').hasMatch(query);
    if (explicitOrigin) {
      if (unique.length < 2) return null;
      final origin = unique.first;
      final destination = unique.last;
      if (origin.id == destination.id) return null;
      return AiNavigationIntent(
        destinationId: destination.id,
        startLocationId: origin.id,
      );
    }

    // At one textual position, prefer the most specific full location name.
    // If two different IDs are equally specific, ask the user to clarify.
    final lastPosition = unique.last.index;
    final atDestination = unique
        .where((candidate) => candidate.index == lastPosition)
        .toList();
    final longest = atDestination
        .map((candidate) => candidate.length)
        .reduce((a, b) => a > b ? a : b);
    final best = atDestination
        .where((candidate) => candidate.length == longest)
        .toList();
    if (best.length != 1) return null;

    return AiNavigationIntent(destinationId: best.single.id);
  }
}
