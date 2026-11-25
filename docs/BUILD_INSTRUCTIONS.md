# Локальная проверка и сборка «Поколения»

**Текущая версия исходников:** `0.2.2+8` (значение `version` в `pubspec.yaml`).  
**Сборка:** локальная. GitHub Actions workflow в текущей ветке отсутствуют, поэтому артефакты APK/EXE в Actions не публикуются.

## 1. Быстро подготовить Windows-среду

Для автоматической настройки чистой Windows 10/11 x64 открой PowerShell от имени администратора и выполни:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
$p = Join-Path $env:TEMP 'setup_and_build.ps1'
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Tikhon-prog/Navigator/main/setup_and_build.ps1' -OutFile $p
& $p
```

Сценарий установки готовит инструменты разработки и запускает предусмотренные им локальные проверки/сборки. Для доступа к репозиторию может потребоваться авторизация Git Credential Manager. Нужны интернет и запас свободного места (ориентир — 25 ГБ).

Основные требования, закреплённые документацией и сценариями проекта:

- Flutter stable **3.47.9** и Dart из этого SDK;
- Python **3.12+** для backend-проверок;
- JDK **21** и Android SDK с принятыми лицензиями;
- для Windows EXE — Visual Studio 2026 или Build Tools 2026 с workload **Desktop development with C++**, Windows SDK и ATL;
- Inno Setup 6 или 7 для Windows installer.

Для Android native dependency `llm_llamacpp` нужны NDK **28.2.13676358** и CMake **3.22.1**. В документации проекта также закреплены Android API 36, Build Tools 36.0.0 и Android Command-line Tools 19.0.

## 2. Проверить код без сборки

Из корня репозитория:

```powershell
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Это проверки исходников и тестов. Они не создают APK или EXE.

## 3. Тестовая сборка APK и Windows EXE

Для debug-сборки без API URL, Firebase credentials, серверного `.env` и школьных секретов:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\build_test.ps1
```

Сценарий выполняет `flutter pub get`, Flutter-тесты и анализ, затем собирает debug APK и Windows debug package. Результаты:

- `dist/test/android/Pokolenie-debug.apk`;
- `dist/test/windows/` — EXE вместе с необходимыми DLL и каталогом `data`.

Это тестовые сборки, не предназначенные для публичного распространения.

## 4. Release APK для Android

`build_apk.bat` — отдельный сценарий только для Android. Он читает версию непосредственно из `pubspec.yaml`, выполняет `flutter pub get`, `flutter test` и `flutter analyze`, затем собирает release APK для `android-arm64` и `android-x64`.

Запуск из проводника или CMD:

```bat
build_apk.bat
```

Результат сохраняется в `dist/Pokolenie-<версия>.apk`, рядом создаётся файл `.sha256`. Этот сценарий не запускает Python backend-тесты и не собирает Windows EXE.

## 5. Полный локальный release: Android + Windows

Для полного набора проверок и release-артефактов используй PowerShell из корня проекта:

```powershell
# Необязательно: адрес публичного HTTPS API для новой установки.
# Если переменная не задана, сборка остаётся офлайн-ориентированной.
$env:POKOLENIE_API_BASE_URL = ""
Set-ExecutionPolicy -Scope Process Bypass -Force
.\build_all_release.ps1
```

Сценарий:

1. Проверяет версию Python и `pubspec.yaml`.
2. Устанавливает Python-зависимости backend, запускает сканер секретов и backend unit/regression tests.
3. Запускает `flutter pub get`, Flutter tests и анализ Dart.
4. Собирает release APK и Windows release.
5. Проверяет наличие основных runtime-файлов Windows, копирует portable-пакет, создаёт SHA-256 APK и компилирует Inno Setup installer.

При версии `0.2.2+8` ожидаемые пути:

- `dist/Pokolenie-0.2.2+8.apk` и `dist/Pokolenie-0.2.2+8.apk.sha256`;
- `dist/Pokolenie-Setup-0.2.2+8.exe`;
- `dist/Pokolenie-Windows-Portable-0.2.2+8/`.

**Подпись Android:** если `android/key.properties` и постоянный release keystore не настроены, сценарий предупреждает и использует debug signing fallback. Такой APK подходит для внутреннего тестирования, но не является production-подписью. Не меняй постоянный ключ между выпусками: Android может отказаться обновлять установленное приложение, подписанное другим ключом. Храни keystore и пароли вне Git с резервной копией.

Windows installer также не подписывается сертификатом издателя автоматически; Windows SmartScreen может показывать предупреждение.

## 6. API и внешняя школьная инфраструктура

Для включения онлайн-функций при сборке задай публичный HTTPS URL:

```powershell
$env:POKOLENIE_API_BASE_URL = "https://api.example.school"
```

`api.example.school` — только пример, не настоящий адрес школы. Не помещай в клиентскую сборку пароли, access/refresh tokens, `.env` или Firebase service-account JSON. Клиентский APK/EXE можно исследовать и извлечь из него конфигурацию.

Сборка приложения не разворачивает backend, не создаёт школьные аккаунты и не настраивает OIDC/SSO, источник расписания или Firebase. Для этих действий смотри [инструкцию серверной интеграции](SERVER_INTEGRATION.md) и [серверные функции](SERVER_FEATURES.md).

## 7. Ручная сборка Windows installer

После успешной команды `flutter build windows --release` и при установленном Inno Setup можно запустить:

```powershell
$versionLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' } | Select-Object -First 1
$version = ($versionLine -split ':', 2)[1].Trim().Trim("'").Trim('"')
New-Item -ItemType Directory -Force -Path dist | Out-Null
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "/DMyAppVersion=$version" "windows/installer.iss"
```

Если `ISCC.exe` установлен в другом каталоге или используется Inno Setup 7, укажи его фактический путь. Полный сценарий `build_all_release.ps1` ищет компилятор автоматически.

## 8. Что проверить перед распространением

- Все Python и Flutter тесты, security check и анализ завершились успешно на текущем commit.
- Android APK собран с постоянным release key, если он предназначен для обновления реальной установки.
- APK и Windows installer установлены и запущены на поддерживаемых целевых устройствах.
- Проверены вход/выход аккаунта, роли, уведомления, опросы, ДОПы, расписание и маршруты по утверждённым планам школы.
- Школа согласовала источник данных и обработку персональных сведений; реальные SSO/API/Firebase credentials заданы только на сервере.
- Сохранены commit SHA, логи проверок, артефакты и SHA-256.

Наличие тестовых файлов в репозитории не означает, что тесты прошли. В этой инструкции нет заявления о том, что текущий commit уже собран или проверен на устройствах.

## Linux (Ubuntu, Lubuntu и др.)

```bash
sudo apt install -y git curl clang cmake ninja-build pkg-config libgtk-3-dev
flutter clean
flutter pub get
flutter build linux --release
```

Готовая программа лежит в `build/linux/x64/release/bundle/` — запускать файл `pokolenie` оттуда, папки `data` и `lib` должны оставаться рядом с ним.

Локальная нейросеть:

- Нативные библиотеки (`libllama.so`, `libggml*.so`) скачивает сама сборка из GitHub, поэтому при `flutter build linux` нужен интернет.
- У этих библиотек SONAME вида `libggml.so.0`, а файлы кладутся без `.0`. `linux/cmake/link_sonames.cmake` на этапе сборки создаёт недостающие ссылки `*.so.0` в `bundle/lib`, а приложение дополнительно заранее подгружает библиотеки по полному пути. Ничего вручную делать не нужно.
- Проверка: `ls -l build/linux/x64/release/bundle/lib | grep -E "llama|ggml"` — рядом с `libllama.so` и `libggml.so` должны быть ссылки `libllama.so.0`, `libggml.so.0`, `libggml-base.so.0`.
- **Процессор без AVX (Celeron N4000 и подобные).** Готовая `libggml-cpu.so` собрана с AVX, и на таком CPU приложение молча закрывается при первом сообщении нейросети (код выхода 132, SIGILL). Проверка: `grep -c avx /proc/cpuinfo` (0 = AVX нет). Решение — один раз собрать llama.cpp без AVX (нужны `git cmake g++`, 10–20 минут, интернет):

  ```bash
  sudo apt install -y git cmake g++
  bash tool/build_llama_cpu.sh
  flutter clean && flutter build linux --release
  ```

  Скрипт кладёт `libllama.so`, `libggml*.so` в `linux/native_cpu/` (папка в `.gitignore`), сборка Linux подставляет их в bundle вместо готовых. Заодно он патчит llama.cpp, чтобы `llama_chat_apply_template` не бросал C++-исключение (в процессе Flutter оно заканчивается `terminate`). Коммит llama.cpp зафиксирован в скрипте и должен совпадать с версией, под которую собран `llm_llamacpp`.
- **GPU-бэкенды отключены.** Нейросеть работает на CPU. Если на машине нет CUDA, `linux/cmake/strip_cuda.cmake` создаёт заглушки `libcudart.so.12`, `libcublas.so.12` и т.п., а `linux/cmake/strip_vulkan.cmake` кладёт заглушки `libggml-vulkan.so.0` и `libggml-cuda.so.0`; приложение загружает их первыми, поэтому чужие версии из `/usr/local/lib` не подхватываются (они роняли процесс на Intel UHD/Mesa).
- `linux/runner/CMakeLists.txt` линкует `libgcc_s` раньше Flutter: `libflutter_linux_gtk.so` экспортирует свой `_Unwind_RaiseException`, из-за чего штатные исключения C++ в нативных библиотеках заканчивались `terminate`.
- Диагностика молчаливого закрытия: `./build/linux/x64/debug/bundle/pokolenie; echo EXIT=$?` (132 — SIGILL, 139 — segfault, 134 — abort).
- Модель (`.gguf`, около 490 МБ) скачивается из приложения в папку данных приложения. Если загрузка или запуск не удались, в тексте ошибки показаны причина и путь к журналу `ai.log` (лежит рядом с моделью).
