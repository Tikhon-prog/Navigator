# Navigator backend

HTTPS Cloud Function + динамические таблицы Яндекс Вики.

Переменные окружения:
- WIKI_TOKEN
- ORG_ID
- GRID_IDS_JSON

OAuth-токен и секреты не должны попадать во Flutter APK.

Эндпоинты:
- GET /health
- GET /schedule?class_id=...
- GET /supplements
- GET /announcements
- POST /admin/login

Для production серверный login требует сессию/JWT, rate-limit, аудит и серверную проверку роли.
