# Сборка школьного приложения «Поколение» 0.2.0

## Требования
- Flutter stable SDK, Dart из комплекта Flutter.
- Android SDK с лицензиями и JDK 21.
- Python 3.12+ для серверных тестов.

## Сборка одной командой

В корне проекта запусти `build_apk_0.2.0.bat`. Скрипт проверит версию, восстановит зависимости, выполнит Flutter-тесты и анализ, затем соберёт APK. Сервер не требуется: по умолчанию это offline-first сборка.

## Android APK (Windows / PowerShell)

Из корня репозитория:

```powershell
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Готовый APK после ручной сборки: `build/app/outputs/flutter-apk/app-release.apk`. Скрипт `build_apk_0.2.0.bat` также копирует его в `dist/Pokolenie-0.2.0+2.apk` и создаёт рядом файл `Pokolenie-0.2.0+2.apk.sha256`.

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

Workflow `.github/workflows/flutter-ci.yml` выполняет сканирование секретов, проверку уязвимых Python-зависимостей, серверные тесты, Flutter-тесты, анализ и release-сборку APK. После успешной сборки CI публикует APK с именем `Pokolenie-0.2.0+2.apk` и контрольную сумму SHA-256 в артефакте `pokolenie-0.2.0+2-apk`.

Если CI не запускает job или выдаёт ошибку до первого шага, это не доказывает ошибку исходного кода: проверь состояние runner и повтори запуск после восстановления GitHub Actions.
