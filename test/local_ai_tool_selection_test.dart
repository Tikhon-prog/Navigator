import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/local_ai_chat_page.dart';

void main() {
  test('ordinary chat does not attach school context or tool schemas', () {
    expect(localAiQueryNeedsSchoolContext('Привет!'), isFalse);
    expect(localAiToolNamesForQuery('Привет!'), isEmpty);
  });

  test('schedule questions expose only the school-context tool', () {
    expect(localAiQueryNeedsSchoolContext('Покажи расписание на завтра'), isTrue);
    expect(
      localAiToolNamesForQuery('Покажи расписание на завтра'),
      {'get_school_context'},
    );
  });

  test('route questions expose only navigation tools', () {
    expect(
      localAiToolNamesForQuery('Построй маршрут до кабинета 317'),
      {'search_school_map', 'plan_school_route'},
    );
  });

  test('favorites require map search and the favorite action', () {
    expect(
      localAiToolNamesForQuery('Добавь кабинет 317 в избранное'),
      {'search_school_map', 'set_favorite_location'},
    );
  });

  test('math renaming exposes the math-specific action', () {
    expect(
      localAiToolNamesForQuery(
        'Переименуй второй урок математики во вторник в геометрию',
      ),
      containsAll({'get_school_context', 'set_math_lesson_name'}),
    );
  });

  test('saving a note does not attach unrelated school tools', () {
    expect(
      localAiToolNamesForQuery('Сохрани заметку: подготовиться к контрольной'),
      {'get_school_context', 'save_personal_note'},
    );
  });
}
