# Настройка среды разработки после переустановки Windows

Эта инструкция предназначена для Windows 10/11 x64. Она разделяет обязательные инструменты для Flutter/Android и дополнительные компоненты для Windows EXE и backend. На ноутбуке с 4 ГБ ОЗУ используй физический Android-телефон вместо эмулятора.

## Что установить

| Программа | Для чего | Нужно ли |
|---|---|---|
| [Git for Windows](https://git-scm.com/download/win) | Клонирование репозитория и работа с ветками | Обязательно |
| [Visual Studio Code](https://code.visualstudio.com/Download) | Лёгкий редактор | Рекомендуется |
| Расширения **Flutter** и **Dart** в VS Code | Подсказки, запуск и анализ Flutter | Рекомендуется |
| [Flutter SDK](https://docs.flutter.dev/install) | Сам Flutter и Dart | Обязательно |
| [JDK 21 (Temurin)](https://adoptium.net/temurin/releases/?version=21) | Android/Gradle | Обязательно для APK |
| [Android Studio](https://developer.android.com/studio) | Установка Android SDK и platform-tools через SDK Manager | Нужна для удобной настройки SDK; IDE и эмулятор запускать не обязательно |
| [Python 3.12](https://www.python.org/downloads/) | Тесты школьного backend и security-check | Только если проверяешь backend |
| [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) | Компилятор C++ для Windows EXE | Только для Windows-клиента |
| [Inno Setup 6](https://jrsoftware.org/isinfo.php) | Создание установщика EXE из Windows bundle | Только для установщика, не для обычного `pokolenie.exe` |

### Версии проекта

- Проект и существующий CI закреплены на Flutter **3.47.4** и Dart **3.13.3**. Используй эту версию для максимального совпадения с CI.
- Java: **JDK 21**. В `android/app/build.gradle.kts` явно настроен Java 21.
- Android SDK: platform **API 36**, Build-tools **36.0.0**, Platform-tools и Command-line Tools **19.0**. Скрипт настройки репозитория закрепляет именно эти пакеты.
- Python: **3.12** для backend-тестов.

Не устанавливай Java 25 вместо Java 21: Gradle-проект настроен на Java 21.

## Android SDK

В Android Studio открой **More Actions → SDK Manager** (после первого запуска: **Tools → SDK Manager**) и установи:

- Android SDK Platform 36;
- Android SDK Build-Tools 36.0.0;
- Android SDK Platform-Tools;
- Android SDK Command-line Tools 19.0.

Путь SDK должен быть известен Flutter. При ручной установке можно задать переменные среды:

```powershell
[Environment]::SetEnvironmentVariable('ANDROID_HOME', "$env:LOCALAPPDATA\Android\Sdk", 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', "$env:LOCALAPPDATA\Android\Sdk", 'User')
```

Открой новое окно PowerShell после изменения PATH или переменных среды. Затем выполни:

```powershell
flutter doctor --android-licenses
flutter doctor -v
```

Если Android Studio установит другую версию Command-line Tools, проверь, что Flutter видит SDK и принимает лицензии. В проектном setup-скрипте закреплена версия 19.0 из-за совместимости используемого сценария принятия лицензий.

## Windows EXE

В Visual Studio Installer выбери **Visual Studio 2022 Build Tools → Desktop development with C++**. Нужны MSVC v143, Windows 10/11 SDK, C++ CMake tools и ATL. После установки проверь:

```powershell
flutter config --enable-windows-desktop
flutter doctor -v
```

Visual Studio Community IDE устанавливать необязательно: достаточно Build Tools. Компоненты C++ занимают несколько гигабайт и могут быть тяжёлыми для ноутбука с HDD и 4 ГБ ОЗУ. На таком ноутбуке сначала настрой Android и проверь проект, а Build Tools добавь только когда понадобится Windows EXE.

## Проверка установок

Открой новое окно PowerShell:

```powershell
git --version
flutter --version
dart --version
java -version
python --version
flutter doctor -v
```

Для Java должен отображаться выпуск 21. Для backend желательно, чтобы `python --version` показывал 3.12.x.

После клонирования репозитория из его корневой папки:

```powershell
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
```

Эти команды получают зависимости и запускают тесты/анализ. Они **не собирают APK или EXE**.

## Что не нужно устанавливать

- **Ollama и отдельный llama.cpp** не нужны для работы встроенного ИИ-чата: приложение использует локальную библиотеку `llm_llamacpp`.
- Не нужно вручную класть модель в папку Flutter assets. Пользователь скачивает её кнопкой в чате; она хранится отдельно от APK.
- **GitHub CLI (`gh`)** необязателен. Для Git достаточно Git for Windows и Git Credential Manager.
- Android Emulator не рекомендуется для ноутбука с 4 ГБ ОЗУ. Используй реальный Android-телефон с включённой USB-отладкой.

Для полной автоматической настройки и сборки см. [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md). Эта инструкция намеренно описывает ручную установку инструментов и проверку без сборки.
