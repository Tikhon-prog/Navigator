import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/room_categories.dart';

void main() {
  group('RoomCategories', () {
    test('separates teacher rooms and administration', () {
      expect(RoomCategories.classify('104', 'Учительская'), 'Учительские');
      expect(RoomCategories.classify('101.1', 'Кабинет директора'), 'Администрация');
    });

    test('recognizes mathematics and science rooms', () {
      expect(RoomCategories.classify('208', 'Кабинет математики'), 'Математика');
      expect(RoomCategories.classify('319', 'Лаборатория медицинской физики'), 'Наука и лаборатории');
    });

    test('recognizes computer science and technology rooms', () {
      expect(
        RoomCategories.classify('311', 'Центр информационных технологий и искусственного интеллекта'),
        'Информатика и технологии',
      );
    });

    test('groups shared school spaces separately', () {
      expect(RoomCategories.classify('place_canteen', 'Столовая'), 'Общие пространства');
      expect(RoomCategories.classify('place_library', 'Информационно-библиотечный центр'), 'Общие пространства');
    });

    test('all option is present in the filter catalogue', () {
      expect(RoomCategories.labels.first, RoomCategories.all);
    });
  });
}
