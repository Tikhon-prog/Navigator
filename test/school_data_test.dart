import 'package:flutter_test/flutter_test.dart';
import 'package:navigator/main.dart';

void main() {
  test('особые помещения называются по назначению', () {
    expect(SchoolData.title(SchoolData.room('108')), 'Лекторий 108');
    expect(SchoolData.title(SchoolData.room('102')), 'Кабинет 102');
  });

  test('учительские выделены в отдельную категорию', () {
    expect(SchoolData.category(SchoolData.room('104')), SchoolLocationCategory.teachers);
    expect(SchoolData.category(SchoolData.room('315')), SchoolLocationCategory.teachers);
  });

  test('для обеда маршрут ведёт в столовую', () {
    expect(SchoolData.locationForLesson('Обед', '')?.id, 'place_canteen');
    expect(SchoolData.locationForLesson('Математика', '102')?.id, '102');
    expect(SchoolData.locationForLesson('Математика', ''), isNull);
  });
}
