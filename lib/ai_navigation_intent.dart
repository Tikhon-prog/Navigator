/// A deterministic front-end for natural-language navigation commands.
/// It resolves room identifiers against the bundled catalog before asking the
/// route engine to calculate a verified path.
class AiNavigationIntent {
  final String destinationId;
  final String? startLocationId;

  const AiNavigationIntent({
    required this.destinationId,
    this.startLocationId,
  });

  static bool looksLikeRouteRequest(String query) {
    final normalized = query.toLowerCase();
    return <String>[
      'маршрут', 'как пройти', 'как дойти', 'проведи', 'проложи',
      'добраться', 'от кабинета', 'из кабинета', 'от ', 'из ',
      'до кабинета',
    ].any(normalized.contains);
  }

  static AiNavigationIntent? fromModelCandidate(
    dynamic candidate, {
    required Iterable<String> knownRoomIds,
  }) {
    if (candidate is! Map) return null;
    final known = knownRoomIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    final destination = '${candidate['destinationId'] ?? ''}'.trim();
    if (!known.contains(destination)) return null;
    final rawStart = candidate['startLocationId'];
    final start = rawStart == null ? '' : rawStart.toString().trim();
    if (start.isNotEmpty && (!known.contains(start) || start == destination)) return null;
    return AiNavigationIntent(destinationId: destination, startLocationId: start.isEmpty ? null : start);
  }

  static AiNavigationIntent? parse(
    String query, {
    required Iterable<String> knownRoomIds,
  }) {
    final normalized = query.toLowerCase();
    if (!looksLikeRouteRequest(query)) return null;

    final known = knownRoomIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    final matched = RegExp(r'(?<!\\d)(\\d{3}(?:\\.\\d+)?)(?!\\d)')
        .allMatches(normalized)
        .map((match) => match.group(1)!)
        .where(known.contains)
        .toList();
    if (matched.isEmpty) return null;

    final hasExplicitOrigin = matched.length > 1 &&
        (normalized.contains('от ') || normalized.contains('из '));
    return AiNavigationIntent(
      destinationId: matched.last,
      startLocationId: hasExplicitOrigin ? matched.first : null,
    );
  }
}
