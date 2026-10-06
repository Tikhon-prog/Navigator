# Navigator backend для Яндекс Облака

Backend рассчитан на HTTPS Cloud Function + динамические таблицы Яндекс Вики. Яндекс официально предоставляет API динамических таблиц: таблицы, столбцы, строки и ячейки можно создавать и изменять через API.

Нужны переменные окружения:
- `WIKI_TOKEN` — OAuth-токен серверной функции, не APK.
- `ORG_ID` — идентификатор организации.
- `GRID_IDS_JSON` — JSON с ID таблиц, например `{"Admins":"...","BaseSchedule":"...","Supplements":"...","Announcements":"..."}`.

Никогда не кладите OAuth-токен или секретный API-ключ в Flutter-приложение.

## Эндпоинты
- `GET /health`
- `GET /schedule?class_id=8-informatics`
- `GET /supplements`
- `GET /announcements`
- `POST /admin/login`

В production к login следует добавить серверную сессию/JWT, rate-limit, аудит и проверку роли. Прототип уже хранит пароль только как SHA-256 и не отправляет секреты в клиентскую таблицу.
