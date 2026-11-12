# Единое окружение разработки в Docker

## Зачем оно нужно

Docker-контейнер хранит одинаковые версии инструментов для разработки и Android-сборки. На хостовой системе не нужно отдельно устанавливать Flutter, Dart, JDK, Android command-line tools и Python-пакеты backend.

Окружение закрепляет:

- Flutter 3.47.9 и Dart 3.13.7;
- Eclipse Temurin JDK 21.0.13+9 (проверка SHA-256);
- Android SDK command-line tools 19.0;
- Android platform 36, build-tools 36.0.0 и NDK 28.2.13676358 (устанавливаются в persistent volume после принятия лицензий);
- Python 3.12 с зависимостями из backend/requirements.txt.

Это локальное окружение разработки. Оно не запускает GitHub Actions, не публикует релизы, не разворачивает школьный сервер и не запускает сборку автоматически после открытия репозитория.

## Что должно быть на компьютере

Нужно установить только Docker с Compose:

- Windows: Docker Desktop с WSL 2 backend. По актуальным требованиям Docker нужны Windows 10 22H2 (build 19045) или Windows 11 23H2 (build 22631) и новее, WSL 2.1.5+, аппаратная виртуализация и не менее 8 ГБ RAM. Проверь версию командой winver и WSL командой wsl --version до установки. Официальные требования: https://docs.docker.com/desktop/setup/install/windows-install/. Для Windows EXE дополнительно понадобится нативная Windows-среда с Visual Studio Build Tools.
- Lubuntu: Docker Desktop не нужен — используется Docker Engine и Compose plugin. Инструкция Docker для Ubuntu: https://docs.docker.com/engine/install/ubuntu/ и https://docs.docker.com/compose/install/linux/. Lubuntu является производной Ubuntu; Docker отдельно предупреждает, что Ubuntu derivatives не относятся к официально поддерживаемым конфигурациям, хотя установка может работать.

Нужен доступ к интернету для первой загрузки образа и зависимостей. Образ крупный: Flutter SDK сам по себе занимает около 1,5 ГБ в архиве; дополнительно загружаются JDK и Android SDK. После первого запуска Docker сохраняет SDK, Gradle и Pub-кеши в отдельных volumes.

На компьютере с 4 ГБ RAM Android-сборка может быть очень медленной или завершаться из-за нехватки памяти. Для комфортной сборки используй ноутбук с 8–16 ГБ RAM и свободным диском. Не запускай Android Emulator внутри контейнера без необходимости: APK можно собрать в контейнере, а установить на телефон отдельно.

## Запуск

Открой терминал в корне репозитория.

### Windows PowerShell

~~~powershell
.\scripts\dev-container.ps1
~~~

### Lubuntu / Linux

~~~bash
bash scripts/dev-container.sh
~~~

При первом запуске Docker соберёт образ. Затем откроется shell контейнера. Корень проекта доступен внутри контейнера в /workspace; изменения файлов сразу видны на хостовой системе.

## Однократная настройка Android SDK

Внутри открывшегося контейнера выполни:

~~~bash
bash scripts/docker/prepare-android-sdk.sh
~~~

Команда покажет Android SDK license prompts. Прочитай их и подтверди принятие вручную, только если согласен. После этого будут скачаны platform-tools, Android API 36, build-tools 36.0.0 и NDK 28.2.13676358.

Эта настройка нужна один раз на каждый новый Docker volume. Не удаляй volumes, если хочешь сохранить уже загруженный SDK.

## Работа с проектом внутри контейнера

Обычная проверка Flutter/Dart:

~~~bash
flutter pub get
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

Android APK:

~~~bash
flutter build apk --release
~~~

Готовый файл появится на хосте в build/app/outputs/flutter-apk/app-release.apk, потому что папка проекта подключена как bind mount.

Полный набор локальных проверок одной командой:

~~~bash
bash scripts/docker/verify.sh
~~~

Он запускает secret scan, backend regression tests, flutter pub get, flutter test и flutter analyze. Скрипт останавливается на первой ошибке.

Сборка Android APK отдельной командой (после однократной настройки SDK):

~~~bash
bash scripts/docker/build-android-apk.sh
~~~

Если переменная POKOLENIE_API_BASE_URL не задана, приложение собирается в офлайн-режиме. Для онлайн-сборки перед запуском контейнера задай публичный HTTPS URL.

Windows PowerShell:

~~~powershell
$env:POKOLENIE_API_BASE_URL = "https://api.example.school"
.\scripts\dev-container.ps1
~~~

Lubuntu/Linux:

~~~bash
export POKOLENIE_API_BASE_URL="https://api.example.school"
bash scripts/dev-container.sh
~~~

Адрес api.example.school здесь только пример. Не передавай в эту переменную токены, пароли или другие секреты.

Для обновления Python-зависимостей измени backend/requirements.txt и пересобери образ. Для обновления Flutter/JDK/Android tools синхронно меняй версии и SHA-256 в docker/dev/Dockerfile и compose.dev.yaml.

Чтобы выйти из контейнера, выполни exit. Сам контейнер удаляется после выхода, но кеши и Android SDK остаются в volumes.

## Windows EXE: важное ограничение

Linux-контейнер собирает Android APK и запускает Flutter/Dart/Python проверки, но не компилирует нативный Windows EXE. Для Windows release нужны Windows host, Flutter Windows desktop toolchain и MSVC из Visual Studio Build Tools (workload Desktop development with C++), Windows SDK и ATL. Для установщика дополнительно нужен Inno Setup.

Поэтому практичная схема для этого проекта:

1. Разрабатывать Flutter/Dart и собирать Android APK в Docker-контейнере на Windows или Lubuntu.
2. Windows EXE собирать на библиотечном Windows-ноутбуке нативным Windows toolchain.
3. iOS-сборку выполнять только на macOS с Xcode.

Docker не превращает Linux-сборку в Windows-сборку и не заменяет Xcode.

## Кеши и очистка

Docker Compose сохраняет следующие volumes:

- android_sdk — лицензии, платформы, build-tools и NDK;
- flutter_artifacts — Flutter engine artifacts;
- flutter_pub_cache — Dart/Flutter packages;
- gradle_cache — Gradle wrapper и зависимости.

Обычный выход из shell не удаляет эти данные. Команда docker compose down -v удаляет volumes и заставит скачивать SDK и зависимости заново; не используй её для обычной очистки контейнера.

Файл compose.dev.yaml намеренно отделён от основного docker-compose.yml, который относится к backend-сервису. Не запускай backend compose для подготовки Flutter-разработки.
