# Документация проекта «Поколение»

Единый источник практической информации — **[PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md)**. Начинай с него: там описаны архитектура, сборка, backend, конфигурация, API, роли, SSO, уведомления, тесты, выпуск и ограничения.

## Основные документы

| Документ | Содержание |
|---|---|
| [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) | Полное техническое руководство по проекту |
| [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) | Настройка Windows и сборка APK/Windows |
| [DOCKER_DEVELOPMENT.md](DOCKER_DEVELOPMENT.md) | Единое Docker-окружение Flutter/Dart, Android SDK и Python |
| [SERVER_INTEGRATION.md](SERVER_INTEGRATION.md) | Развёртывание сервера, OIDC, переменные окружения и API |
| [SERVER_FEATURES.md](SERVER_FEATURES.md) | Подробные заметки о серверных функциях |
| [SECURITY.md](SECURITY.md) | Модель безопасности и production-чек-лист |
| [ROUTING_AUDIT.md](ROUTING_AUDIT.md) | Аудит геометрии и ограничений маршрутизации |
| [CHANGELOG.md](CHANGELOG.md) | История изменений |
| [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) | Карта исходников |
| [RELEASE_0.2.0.md](RELEASE_0.2.0.md) | Заметки к выпуску 0.2.0 |
| [ROADMAP_2_1.md](ROADMAP_2_1.md) | План будущего развития; не подтверждение реализованных функций |
| [UX_REWORK_1_0.md](UX_REWORK_1_0.md) | Заметки о переработке UX |
| [ADMIN_SECURITY.md](ADMIN_SECURITY.md) | Дополнительные заметки по административной безопасности |
| [backend/README.md](backend/README.md) | Короткая инструкция для сервера |
| [qa/README.md](qa/README.md) | QA-документы |
| [platform/](platform/) | Справочные документы платформ |

Архивные заметки о старых исправлениях и списках задач перемещены в [history/](history/). Документы Android, iOS, backend и QA собраны в подпапках `docs/`, чтобы вне корня оставался только главный пользовательский `README.md`.

## Проверка

Из корня репозитория:

```powershell
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

Backend:

```powershell
python -m pip install -r backend/requirements.txt
python backend/security_check.py
python -m unittest discover -s backend/tests -v
```

Эти команды — инструкция для воспроизводимой проверки, а не отчёт о фактически пройденных тестах. Перед production-сборкой нужно проверить актуальные переменные окружения, подпись APK, серверные настройки и права доступа.
