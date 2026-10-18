# Сборка школьного приложения «Поколение» 0.2.0

## Требования
- Flutter stable SDK, Dart из комплекта Flutter.
- Android SDK с лицензиями и JDK 21.
- Python 3.12+ для серверных тестов.

## Android APK (Windows / PowerShell)

Из корня репозитория:

```powershell
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Готовый APK: `build/app/outputs/flutter-apk/app-release.apk`.

Проверить, что версия — 0.2.0 и build number — 2:

```powershell
Select-String -Path pubspec.yaml -Pattern '^version:'
```

## Серверные проверки

```powershell
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
```

Для Firebase push-уведомлений отдельно установи `backend/requirements-firebase.txt`. Реальные ключи и заполненный `.env` не помещай в репозиторий.

## CI

Workflow `.github/workflows/flutter-ci.yml` выполняет сканирование секретов, проверку уязвимых Python-зависимостей, серверные тесты, Flutter-тесты, анализ и release-сборку APK. Артефакт сборки публикуется под именем `navigator-release-apk`.

Если CI не запускает job или выдаёт ошибку до первого шага, это не доказывает ошибку исходного кода: проверь состояние runner и повтори запуск после восстановления GitHub Actions.
