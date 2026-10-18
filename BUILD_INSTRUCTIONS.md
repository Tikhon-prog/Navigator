# Сборка школьного приложения «Поколение» 0.2.0

## Требования
- Flutter stable SDK версии из текущего CI (3.47.4) и Dart из комплекта Flutter.
- Android SDK с лицензиями и JDK 21 для APK.
- Visual Studio 2022 с workload **Desktop development with C++** для локальной Windows-сборки.
- Python 3.12+ для серверных тестов.

## Получение APK и Windows EXE из GitHub Actions

Workflow `.github/workflows/flutter-ci.yml` выполняет серверные проверки, Flutter-тесты и анализ, собирает APK на Ubuntu и Windows-приложение на Windows runner.

В разделе **Actions → Flutter CI → успешный запуск → Artifacts** будут доступны:
- `pokolenie-android-<версия>` — `Pokolenie-<версия>.apk` и его SHA-256.
- `pokolenie-windows-<версия>` — `Pokolenie-Setup-<версия>.exe` (установщик) и `Pokolenie.exe` (основной исполняемый файл).

Для обычной установки Windows используй **Pokolenie-Setup-*.exe**. Файл `Pokolenie.exe` — основной бинарный файл приложения и должен оставаться вместе с Flutter runtime DLL и папкой `data`; сам по себе он не является переносимым single-file приложением. Артефакты GitHub Actions скачиваются как контейнеры загрузки; после извлечения внутри находятся указанные APK/EXE-файлы. Срок хранения артефактов — 14 дней.

## Локальная сборка Android APK (Windows / PowerShell)

Из корня репозитория:

```powershell
flutter doctor
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

APK после ручной сборки: `build/app/outputs/flutter-apk/app-release.apk`. Скрипты `build_apk_0.2.0.bat` и `build_release.bat` также копируют его в `dist/Pokolenie-0.2.0+2.apk` и создают рядом контрольную сумму `Pokolenie-0.2.0+2.apk.sha256`.

## Локальная сборка Windows EXE

В Windows установи Visual Studio 2022 с workload **Desktop development with C++**, Inno Setup 6, затем из корня проекта запусти:

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" /DMyAppVersion=0.2.0+2 windows/installer.iss
```

Основной бинарный файл: `build/windows/x64/runner/Release/pokolenie.exe`. Установщик создаётся в `dist/Pokolenie-Setup-0.2.0+2.exe` и включает DLL/runtime-файлы и папку данных, нужные приложению.

## Локальные серверные проверки

```powershell
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
```

Для Firebase push-уведомлений отдельно установи `backend/requirements-firebase.txt`. Реальные ключи и заполненный `.env` не помещай в репозиторий.

## Подпись

CI создаёт тестовый APK с текущей конфигурацией сборки; при отсутствии постоянного ключа релиза Android Gradle использует debug-подпись. Для стабильных Android-обновлений создай и надёжно сохрани отдельный ключ подписи вне Git. Windows installer также не подписан сертификатом издателя и поэтому может показывать предупреждения SmartScreen.
