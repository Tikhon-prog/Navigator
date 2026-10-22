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

  static AiNavigationIntent? parse(
    String query, {
    required Iterable<String> knownRoomIds,
  }) {
    final normalized = query.toLowerCase();
    final asksForRoute = <String>[
      'маршрут',
      'как пройти',
      'как дойти',
      'проведи',
      'проложи',
      'добраться',
      'от кабинета',
      'из кабинета',
      'от ',
      'из ',
      'до кабинета',
    ].any(normalized.contains);
    if (!asksForRoute) return null;

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
