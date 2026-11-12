# Сборка тестовой офлайн-версии без секретов

Для локальной проверки APK и Windows EXE используй [`build_test.ps1`](../build_test.ps1). Он собирает оба отладочных клиента без API URL, SSO, Firebase secrets и серверного `.env`. Для release APK используй [`build_apk.bat`](../build_apk.bat), а для APK + Windows installer + portable EXE — [`build_all_release.ps1`](../build_all_release.ps1). Текущая версия приложения — 0.2.1+8. Для Windows EXE нужны Visual Studio 2026 или Build Tools 2026 с workload Desktop development with C++ и ATL.

# Быстрая установка на чистый Windows 10/11 x64

Открой **Windows PowerShell или Windows Terminal от имени администратора** и вставь всю строку ниже. Скрипт подготовит зависимости и Flutter, добавит SDK в пользовательский PATH, скачает репозиторий, запустит тесты и соберёт APK + EXE. Для доступа к закрытому репозиторию может потребоваться вход через Git Credential Manager в браузере; отдельная команда `gh` не обязательна.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; $p = Join-Path $env:TEMP 'setup_and_build.ps1'; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/Tikhon-prog/Navigator/main/setup_and_build.ps1' -OutFile $p; & $p
```

Нужны интернет и желательно **25 ГБ свободного места**. Скрипт устанавливает Git, Python 3.12, Oracle JDK 27, Android command-line SDK, Flutter 3.47.9 (если совместимый SDK не найден), Visual Studio 2026 Build Tools (workload Desktop development with C++, ATL и Windows SDK) и Inno Setup 6. JDK 27 загружается из официального Oracle ZIP; перед установкой скрипт сверяет SHA-256 контрольную сумму. Android-лицензии принимаются в консоли.

Скрипт использует официальные источники и проверяет SHA-256 загружаемых архивов Flutter и Android tools. Он не записывает GitHub token, школьные пароли или другие секреты в исходники. Если URL backend не задан, клиент соберётся в офлайн-режиме. Пароли, серверные токены и Firebase service-account ключи не нужны для клиентской сборки и не должны встраиваться в APK/EXE.

Готовые файлы появятся в `C:\Dev\Pokolenie\dist\`. Для обычной установки Windows запускай Pokolenie-Setup-*.exe. Переносная сборка требует весь каталог Pokolenie-Windows-Portable-*. Android-файл — Pokolenie-*.apk и соседний файл .sha256.

Если Visual Studio попросит перезагрузку, перезагрузи компьютер и повтори команду. Если winget отсутствует, установи или обнови App Installer из Microsoft Store и повтори команду. Повторный запуск проверяет уже установленные компоненты.

> Скрипт настраивает среду и собирает клиенты. Он не разворачивает школьный сервер, не создаёт реальные аккаунты учеников/директора, не регистрирует школьный OIDC-клиент и не может угадать закрытое расписание или Firebase service-account credentials.


## Android Studio 2026: компоненты SDK

Открой **Tools → SDK Manager**.

Вкладка **SDK Platforms**:
- Android API 36.

Вкладка **SDK Tools** (включи **Show Package Details**, если нужно выбрать точную версию):
- Android SDK Build-Tools **36.0.0**;
- Android SDK Platform-Tools;
- Android SDK Command-line Tools **19.0** — локальный bootstrap проекта закрепляет эту версию для совместимого вызова лицензий;
- NDK (Side by side) **28.2.13676358**;
- CMake **3.22.1**.

Android Emulator и LLDB для сборки не нужны, если приложение запускается на физическом телефоне. NDK и CMake нужны нативной зависимости `llm_llamacpp`. Если используешь `setup_and_build.ps1`, он проверит эти компоненты и установит отсутствующие; существующий Android SDK по `ANDROID_SDK_ROOT`, `ANDROID_HOME` или стандартному пути Android Studio будет переиспользован.

В Android Studio открой **File → Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK** и выбери установленный **Oracle JDK 27**. Не выбирай встроенный JBR Android Studio, если там другая версия Java. Для терминала выставь `JAVA_HOME` на ту же папку JDK 27. Gradle 9.9.0 запускается на JDK 27; Java/Kotlin bytecode приложения остаётся на target 21.

**Важно:** Android Studio 2026 — это IDE и менеджер Android SDK. Для Windows EXE отдельно нужен **Visual Studio 2026** или **Build Tools 2026** с workload **Desktop development with C++**, MSVC x64/x86, CMake tools, Windows SDK и ATL.

---
## 1. Что собирается

После успешного выполнения **Actions → Flutter CI** доступны два артефакта:

| Артефакт | Что внутри | Для чего |
|---|---|---|
| `pokolenie-android-0.2.1+8` | `Pokolenie-0.2.1+8.apk` и файл SHA-256 | Установка на Android |
| `pokolenie-windows-0.2.1+8` | `Pokolenie-Setup-0.2.1+8.exe` и каталог `Pokolenie-Windows-Portable-0.2.1+8` со всеми DLL и данными | Установка Windows или переносной запуск |

**Для обычной установки Windows запускай `Pokolenie-Setup-*.exe`.** Если используешь переносную сборку, запускай `pokolenie.exe` внутри каталога `Pokolenie-Windows-Portable-*`; не выноси его отдельно от соседних DLL и папки `data`.

Артефакты хранятся 14 дней. GitHub может упаковать скачиваемый артефакт в транспортный ZIP, но внутри будут APK/EXE и все runtime-файлы приложения. Установщик Windows пока не подписан сертификатом издателя; Windows SmartScreen может показать предупреждение.

## 2. Ошибка оплаты или лимита GitHub Actions

В истории запусков получена точная ошибка GitHub: **“The job was not started because recent account payments have failed or your spending limit needs to be increased.”** Это ограничение аккаунта/биллинга GitHub. Job не получает runner и не запускает Flutter, Python или компилятор; исправления Dart-кода не могут обойти эту блокировку.

Проверь настройки именно аккаунта-владельца репозитория:

1. Открой **аватар GitHub → Settings → Billing & Licensing → Payment information**. Проверь и **Payment history**. Если платёж действительно отклонён или просрочен, владелец аккаунта должен исправить это в платёжных настройках. Для репозитория организации это должен делать владелец организации или billing manager.
2. В **Billing & Licensing → Plans and usage** проверь включённую квоту GitHub Actions, использование минут и хранилища. По официальной документации GitHub Free включает 2 000 минут и 500 MB хранилища артефактов для стандартных runner в приватных репозиториях; точные лимиты зависят от плана. Когда квота исчерпана и действующего способа оплаты нет, использование блокируется. См. [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
3. Проверь бюджет и предел расходов на Actions. **Не увеличивай лимит и не включай потенциально платные расходы, пока не согласен с возможным списанием**. Для сборки есть локальная альтернатива в разделе 7.
4. Если страница Billing не показывает причину, прочитай [документацию GitHub о блокировке аккаунта из-за биллинга](https://docs.github.com/en/billing/how-tos/troubleshooting/locked-account). Неудачная проверочная авторизация при оформлении подписки или увеличении бюджета иногда может блокировать Actions даже без активной платной подписки. Если после проверки проблема не видна, обратись в [GitHub Support](https://support.github.com/).

Когда GitHub снимет ограничение, открой **Actions → Flutter CI → Run workflow → main**. После этого задачи смогут получить runner, появятся шаги и настоящие логи компиляции. В workflow Linux runner закреплён на `ubuntu-24.04`, чтобы не зависеть от миграции псевдонима `ubuntu-latest` на Ubuntu 26. Само предупреждение в старых запусках не было причиной ошибки.

## 3. Получить файлы из GitHub Actions

1. Перейди на вкладку **Actions** репозитория.
2. Выбери успешный запуск **Flutter CI** на нужном коммите.
3. Внизу страницы в **Artifacts** скачай Android- или Windows-артефакт.
4. Распакуй скачанный GitHub ZIP-контейнер. Внутри находятся именно APK/EXE и контрольная сумма, не исходники.
5. Android: передай `.apk` на устройство и установи его; если Android попросит, разреши установку из выбранного источника.
6. Windows: запусти `Pokolenie-Setup-<версия>.exe` и следуй мастеру установки.

## 4. Указать адрес школьного API

Онлайн-функции отключены, если сервер не развёрнут или его адрес не задан. Карта, локальные планы, локальное расписание и личные заметки рассчитаны на работу без сервера.

Для новой сборки с предустановленным адресом:

1. Убедись, что школьный API доступен через публичный **HTTPS** URL.
2. В репозитории открой **Settings → Secrets and variables → Actions → Variables**.
3. Создай repository variable `POKOLENIE_API_BASE_URL`, например `https://api.example.school`. Это пример адреса, не настоящий сервер.
4. Повтори **Run workflow**.

Адрес API — публичная конфигурация. Не помещай туда пароли, токены, закрытые ключи, содержимое `.env` или Firebase service-account JSON. Уже установленные приложения сохраняют пользовательские настройки; изменение переменной действует на новую сборку.

## 5. Подготовить сервер и реальные функции

Сервер — отдельное приложение в `backend/`. Прежде чем включать функции, требующие сети:

1. Разверни backend согласно [документации серверной интеграции](SERVER_INTEGRATION.md) и [перечню функций](SERVER_FEATURES.md). Для контейнерного запуска проверь `docker-compose.yml`.
2. На сервере создай настоящий `.env` из корневого `.env.example` или `backend/.env.example` согласно выбранному способу запуска. Не коммить заполненный файл.
3. Задай уникальный `NAVIGATOR_TOKEN_SECRET` (минимум 32 случайных символа), постоянное записываемое хранилище SQLite и bootstrap-данные технического администратора. Не используй пример `CHANGE_ME` в реальной установке.
4. Подготовь официальный источник школьных данных. При `NAVIGATOR_DATA_SOURCE=json` он должен содержать коллекции `Classes`, `BaseSchedule`, `Rooms`, `Places` и `Announcements`; каждая коллекция — массив объектов. При необходимости добавь `Supplements`. Альтернатива — HTTPS API с подходящими полями. Данные реального расписания и назначений должен подтвердить ответственный сотрудник.
5. Опубликуй API за HTTPS reverse proxy, проверь health/readiness endpoint и сохранность SQLite после перезапуска. Не открывай базу напрямую в интернет.

В проекте реализованы серверные API для ролей и прав доступа, учеников и сотрудников, назначений наставников/учителей, ДОПов, уведомлений, журнала аудита, сессий и синхронизации. Наличие кода не создаёт настоящие школьные аккаунты, не заполняет расписание и не связывает его с intranet автоматически — источник и правила школы должны быть настроены и проверены отдельно.

### Школьный вход (OIDC/SSO)

Школьный IT-администратор должен выдать HTTPS issuer и client ID и зарегистрировать разрешённые redirect URI. Для мобильного приложения используется:

```text
ru.pokolenie.navigator:/oauthredirect
```

Для Windows-клиента требуется ещё loopback redirect URI. По умолчанию это:

```text
http://127.0.0.1:43827/oauth/callback
```

Задай на сервере `NAVIGATOR_OIDC_DESKTOP_REDIRECT_URI` в соответствии с зарегистрированным адресом. Значение передаётся клиенту через публичную конфигурацию; пароль клиента и `client_secret` не нужны и не должны встраиваться в EXE. Windows вход открывает системный браузер и использует Authorization Code + PKCE. На OIDC-провайдере должен быть разрешён этот точный адрес loopback и метод PKCE S256; некоторые провайдеры требуют отдельную регистрацию desktop-клиента. Без регистрации redirect URI школьный SSO не заработает.

Также необходимо настроить `NAVIGATOR_OIDC_ISSUER`, `NAVIGATOR_OIDC_CLIENT_ID`, корректный mobile `NAVIGATOR_OIDC_REDIRECT_URI` и правила привязки `sub`/учётной записи в соответствии с [моделью безопасности](SECURITY.md).

### Общешкольные оповещения и Firebase

Лента школьных оповещений, права их публикации, аудит, роли и история доставки используют backend API. Push-доставка Firebase остаётся необязательной и требует Firebase-конфигурации на клиенте и service-account credentials на сервере.

`firebase_messaging` не поддерживает нативную Windows-платформу как стандартный целевой plugin. Поэтому Windows EXE не регистрирует FCM-токен и не получает FCM push. Вместо этого, пока EXE запущен, приложение опрашивает авторизованную ленту уведомлений каждые 45 секунд и показывает Windows toast для новых сообщений. При первом запуске существующая лента только запоминается, чтобы не показать старые сообщения повторно. Если приложение закрыто, Windows-опрос не выполняется; для настоящих push-уведомлений при закрытом приложении нужна отдельная Windows-служба/пакетная интеграция, она не маскируется под реализованную функцию. Android push включается только после настройки Firebase. Не полагайся на push как на единственный канал экстренного оповещения.

## 6. Что включает приложение

- **Офлайн:** планы этажей, поиск кабинетов, построение маршрутов и пошаговые подсказки, локальные данные расписания, таймер урока/перемены, заметки.
- **Дополнительные занятия:** локальные/импортированные записи, маршрут до кабинета, напоминания при корректном времени занятий и активированных разрешениях.
- **Школьный аккаунт:** SSO, безопасное хранение токенов, обновление/отзыв сессии и роль пользователя.
- **Школьный кабинет:** данные в соответствии с серверными правами, управления аккаунтами/назначениями/ДОПами/оповещениями и журнал аудита — когда соответствующие функции разрешены сервером текущей роли.
- **Онлайн-данные:** API, расписание, объявления, синхронизация и push требуют развернутой серверной инфраструктуры и достоверного источника данных.

Доступные кнопки и роли не заменяют серверные проверки. Для каждого класса и должности нужно проверить набор прав; не заполняй аккаунты реальными персональными данными до подтверждения модели доступа школой.

## 7. Локальная сборка на Windows 10/11

### Одна команда для локальной сборки обоих форматов

Если Actions пока заблокирован биллингом, можно собрать клиент локально. Нужны Flutter 3.47.9, Python 3.12+, Android SDK + JDK 27, Visual Studio 2026/Build Tools с workload **Desktop development with C++** (включая ATL и Windows SDK) и Inno Setup 6. Gradle запускается на JDK 27, Android bytecode остаётся на target 21. Выполни PowerShell из корня репозитория:

```powershell
# Необязательно: задать реальный публичный HTTPS адрес API для новой сборки.
# Если переменную не задавать, приложение собирается в офлайн-режиме.
$env:POKOLENIE_API_BASE_URL = "https://api.school.example"

Set-ExecutionPolicy -Scope Process Bypass
.\build_all_release.ps1
```

Скрипт выполняет проверки backend (secret scan и Python-тесты), Flutter-тесты/анализ, собирает APK и Windows release, проверяет состав Windows-пакета и создаёт установщик. Готовые результаты появляются в `dist\`: APK с SHA-256, `Pokolenie-Setup-<версия>.exe` и каталог `Pokolenie-Windows-Portable-<версия>\`. Не используй пример `api.school.example` как реальный адрес.

Установи:

- Flutter stable **3.47.9** и Dart из того же SDK;
- JDK 27 и Android SDK с принятыми лицензиями; Gradle Wrapper использует Gradle 9.9.0;
- Visual Studio 2026 или Build Tools 2026 с workload **Desktop development with C++**, включая ATL для `flutter_secure_storage_windows`;
- Inno Setup 6 для сборки установщика.

Открой PowerShell в корне репозитория:

```powershell
flutter doctor -v
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter build apk --release
flutter build windows --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`.

Основная Windows-сборка: `build/windows/x64/runner/Release/pokolenie.exe` вместе с DLL и `data`. Чтобы собрать установщик, после Windows-сборки выполни:

```powershell
New-Item -ItemType Directory -Force -Path dist | Out-Null
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DMyAppVersion=0.2.1+8" "windows/installer.iss"
```

Установщик будет создан в `dist/Pokolenie-Setup-0.2.1+8.exe`. Если путь `ISCC.exe` отличается, выбери путь, куда установлен Inno Setup 6. Для локальной Windows-сборки потребуется настроенный MSVC/CMake toolchain; `flutter doctor -v` покажет отсутствующие компоненты.

## 8. Тесты и выпуск

Workflow запускает сканирование репозитория на секреты, серверные regression-тесты, Flutter unit/widget-тесты и анализ. После успешных проверок отдельные задачи собирают APK и Windows installer EXE. Аудит уязвимостей Python-зависимостей выполняется отдельной задачей и не блокирует сборку пользовательских приложений; результат аудита всё равно отображается в Actions и его нужно устранить до production-развёртывания backend.

После изменения кода проверь:
```powershell
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Для Android в текущей конфигурации используется резервная debug-подпись, пока не настроен постоянный ключ релиза. Это подходит для тестирования, но может потребовать удалить старую тестовую версию перед установкой следующей. Для стабильных Android-обновлений сохрани отдельный ключ релиза и `android/key.properties` вне Git. Windows EXE/установщик тоже не подписаны сертификатом издателя.

## 9. Что требуется именно от владельца

Код, workflow, Windows OAuth loopback client flow, локальные Windows toast-уведомления с опросом ленты и инструкции уже в репозитории. От владельца требуются только недоступные из коммита внешние настройки: разрешение/квота GitHub Actions, настоящий API URL и развернутый backend, регистрация callback в школьном OIDC-провайдере и (если нужен push на Android) Firebase credentials. Не публикуй эти секреты в issue, логах CI или исходниках.
