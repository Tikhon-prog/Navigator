# Структура исходников — версия 0.2.0

## Flutter-клиент
- `lib/main.dart` — главный интерфейс, локальное расписание, каталог помещений и маршруты.
- `lib/corridor_roads.dart`, `lib/door_points.dart` — граф коридоров и точки входа.
- `lib/admin_panel.dart`, `lib/security_service.dart` — локальные административные инструменты и защита прототипа.
- `lib/announcements_page.dart` — объявления.
- `lib/dop_parser.dart`, `lib/supplements_page.dart` — данные и интерфейс ДОПов.
- `lib/school_account_service.dart`, `lib/school_portal_page.dart` — серверная учётная запись и школьный портал.
- `lib/online_data_service.dart`, `lib/api_security.dart` — безопасная конфигурация клиентского API.
- `lib/local_notification_service.dart` — локальные напоминания.

## Данные и карты
- `assets/data/` — каталог помещений, места, координаты дверей и локальное расписание.
- `assets/maps/` — три офлайн-карты и исходные планы школы.
- `assets/routing/` — материалы по коридорным сегментам.

## Сервер
- `backend/main.py` — публичный API и регистрация маршрутов.
- `backend/data_sources.py` — источники школьных данных: JSON и HTTPS API.
- `backend/school_api.py` — аккаунты, сессии, ученики и индивидуальные записи.
- `backend/sso_api.py` — интеграция с OIDC.
- `backend/rbac_api.py` — должности, области доступа и синхронизация.
- `backend/notification_api.py` — push-уведомления и напоминания.
- `backend/tests/` — серверные регрессионные и security-тесты.
- `docker-compose.yml`, `backend/Dockerfile` — контейнерный запуск.

## Проверки и сборка

```powershell
flutter pub get
flutter analyze
flutter test
python backend/security_check.py
python -m unittest discover -s backend/tests -v
flutter build apk --release
```

Секреты сервера и ключи подписи должны оставаться вне Git. Версия приложения задаётся в `pubspec.yaml`.
