enum AiNavigationCommandType {
  avoidLocation,
  allowLocation,
  routeFeedback,
}

class AiNavigationCommand {
  final AiNavigationCommandType type;
  final String locationId;
  final String text;

  const AiNavigationCommand({
    required this.type,
    required this.locationId,
    required this.text,
  });
}

/// Conservative phrase parser. It only accepts room IDs from the real catalog.
class AiNavigationCommandParser {
  static List<AiNavigationCommand> parse(
    String text, {
    required Iterable<String> knownLocationIds,
  }) {
    final known = knownLocationIds.map((id) => id.trim()).toSet();
    final ids = RegExp(r'(?<!\d)(\d{3}(?:\.\d+)?)(?!\d)')
        .allMatches(text)
        .map((match) => match.group(1)!)
        .where(known.contains)
        .toList();
    if (ids.isEmpty) return const [];

    final normalized = text.toLowerCase().replaceAll('ё', 'е');
    final result = <AiNavigationCommand>[];

    final isFeedback = <String>[
      'неправильно',
      'неверно',
      'ошиб',
      'перепроверь',
      'проверь маршрут',
      'путь невер',
      'маршрут невер',
    ].any(normalized.contains);

    final removeAvoidance = <String>[
      'не избегай',
      'убери ограничение',
      'сними ограничение',
      'можно ходить через',
      'разреши проходить',
      'больше не обходи',
    ].any(normalized.contains);

    final addAvoidance = <String>[
      'не хочу идти',
      'не хочу ходить',
      'не хочу проходить',
      'не иди через',
      'не проходи через',
      'избегай',
      'избегать',
      'обходи',
      'обойди',
      'не ходи около',
      'не ходи рядом',
      'не хочу около',
      'альтернативу около',
      'альтернативный маршрут около',
    ].any(normalized.contains);

    for (final id in ids.toSet()) {
      if (isFeedback) {
        result.add(AiNavigationCommand(
          type: AiNavigationCommandType.routeFeedback,
          locationId: id,
          text: text.trim(),
        ));
      }
      if (removeAvoidance) {
        result.add(AiNavigationCommand(
          type: AiNavigationCommandType.allowLocation,
          locationId: id,
          text: text.trim(),
        ));
      } else if (addAvoidance) {
        result.add(AiNavigationCommand(
          type: AiNavigationCommandType.avoidLocation,
          locationId: id,
          text: text.trim(),
        ));
      }
    }
    return result;
  }
}
