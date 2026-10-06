# Структура Navigator 1.0.0

## Клиент
- lib/main.dart — основной Flutter-клиент.
- lib/security_service.dart — локальная защита администраторов.
- lib/online_data_service.dart — HTTPS-клиент backend.
- lib/door_points.dart — точки входа в кабинеты для маршрутизации.
- lib/corridor_roads.dart — граф коридоров.
- lib/local_notification_service.dart — расписание локальных уведомлений.
- lib/admin_panel.dart — админ-панель.
- lib/supplements_page.dart — ДОПы.

## Данные
- assets/data/ — расписание, кабинеты, места и точки.
- assets/routing/ — коридорные дороги.
- assets/maps/ — карты этажей и исходные планы.

## Android
- android/app/ — Android application module.
- Java 21 / Kotlin 2.2.20 / AGP 8.11.1.
- локальные ключи подписи исключены через .gitignore.

## Backend
- backend/create_tables.py
- backend/yandex_cloud_function/

## QA
- qa/ — аудит маршрутизации и материалы проверки.

## Сборка
flutter pub get
flutter analyze
flutter build apk --release

Полный архив Navigator_18.zip содержит также бинарные карты, PDF и XLSX. Большие бинарные файлы намеренно не дублируются в Git-репозитории через текущий коннектор.
