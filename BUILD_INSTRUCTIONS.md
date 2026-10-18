# Сборка школьного приложения «Поколение» 0.2.0

## Требования
- Flutter stable SDK, Dart из комплекта Flutter.
- Android SDK с лицензиями и JDK 21.
- Python 3.12+ для серверных тестов.

## Сборка одной командой

В корне проекта запусти `build_apk_0.2.0.bat` для быстрой автономной сборки: скрипт проверит версию, восстановит зависимости, выполнит Flutter-тесты и анализ, соберёт APK и контрольную сумму. Он использует резервную debug-подпись, если `android/key.properties` ещё нет; такой APK подходит для тестирования, но подписанный другим ключом APK нельзя установить поверх предыдущей версии.

## Android APK (Windows / PowerShell)

Из корня репозитория:

```powershell
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Готовый APK после ручной сборки: `build/app/outputs/flutter-apk/app-release.apk`. Скрипты `build_apk_0.2.0.bat` и `build_release.bat` также копируют его в `dist/Pokolenie-0.2.0+2.apk` и создают рядом файл `Pokolenie-0.2.0+2.apk.sha256`. Для долгосрочных установок предпочитай `build_release.bat`: он создаёт локальный ключ при первом запуске и проверяет подпись. Сохрани `android/app/navigator-release.jks` и `android/key.properties` в надёжном месте; без ключа нельзя выпускать совместимые обновления.

Проверить, что версия — 0.2.0 и build number — 2:

```powershell
Select-String -Path pubspec.yaml -Pattern '^version:'
```

## ZIP-пакеты

GitHub Actions после успешных тестов и сборки публикует два разных архива:

- `Pokolenie-<версия>.zip` — APK, контрольная сумма SHA-256 и инструкция по установке Android.
- `Pokolenie-<версия>-source.zip` — исходный код репозитория на commit, для которого выполнялась сборка.

В разделе **Actions → Flutter CI → нужный запуск → Artifacts** скачай `pokolenie-<версия>-android` для APK и установочного ZIP, а `pokolenie-<версия>-source` — для исходников. Артефакты CI хранятся 7 дней. ZIP установочного пакета можно распаковать на компьютере или телефоне; для установки приложения на Android нужен именно APK.

## Серверные проверки

```powershell
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
```

Для Firebase push-уведомлений отдельно установи `backend/requirements-firebase.txt`. Реальные ключи и заполненный `.env` не помещай в репозиторий.

## CI

Workflow `.github/workflows/flutter-ci.yml` выполняет сканирование секретов, проверку уязвимых Python-зависимостей, серверные тесты, Flutter-тесты, анализ и release-сборку APK. После успешной сборки публикует APK, SHA-256, ZIP для установки и отдельный ZIP с исходниками. Все ZIP-пакеты проверяются командой `unzip -t` до загрузки артефактов.

Если CI не запускает шаги и выдаёт ошибку сразу после старта job, это не доказывает ошибку исходного кода: проверь ограничения GitHub Actions/runner и повтори запуск после восстановления доступа к runner.
