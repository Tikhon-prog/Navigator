# Историческая заметка — исправления Flutter Analyze для «Поколения»

Этот файл фиксирует старые исправления линтера и не заменяет текущие инструкции по выпуску 0.2.0.

Исправления после `flutter analyze`:
- заменён spread в _allNodes на обычный цикл;
- заменён несуществующий List.reverse() на reversed.toList();
- заменён deprecated Matrix4.scale() на scaleByDouble();
- DropdownButtonFormField использует initialValue;
- исправлены однострочные if для lint;
- удалены лишние multiple underscores в callback-параметрах.

Проверка на машине разработчика:
flutter pub get
flutter analyze
flutter build apk --release
