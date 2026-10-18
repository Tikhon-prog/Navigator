# Сервер школьного приложения «Поколение» 0.2.0

FastAPI-сервис поддерживает публичные справочники и отдельные авторизованные маршруты `/api/v2` для аккаунтов, назначений, ДОПов, объявлений, устройств и аудита.

## Быстрый запуск

1. Установить Python 3.12 или новее.
2. Скопировать корневой `.env.example` в `.env` и заполнить серверные параметры.
3. Подготовить JSON-источник или HTTPS API согласно [SERVER_INTEGRATION.md](../docs/SERVER_INTEGRATION.md).
4. Установить зависимости:

```bash
python -m pip install -r backend/requirements.txt
uvicorn backend.main:app --host 127.0.0.1 --port 8000
```

Для Docker:

```bash
docker compose up --build -d
docker compose logs -f navigator-api
```

Контейнер слушает `127.0.0.1:8000`; опубликовывать его наружу можно только через настроенный HTTPS reverse proxy.

Firebase push по умолчанию выключен. Для его включения настрой сервисный JSON и публичные настройки Android, установи `NAVIGATOR_ENABLE_FIREBASE=true` в `.env`, затем обязательно пересобери образ командой `docker compose up --build -d`: Firebase Admin SDK устанавливается на этапе сборки. Без этих шагов серверные ленты работают, но push-доставка не выполняется.

## Источники данных

`NAVIGATOR_DATA_SOURCE=json` читает UTF-8 JSON из `NAVIGATOR_DATA_JSON_PATH`. Верхний уровень — объект, ключи — имена коллекций, значения — массивы объектов. Поддерживаемые коллекции: `Classes`, `BaseSchedule`, `Supplements`, `Rooms`, `Places`, `Announcements`.

`NAVIGATOR_DATA_SOURCE=http` вызывает `{NAVIGATOR_DATA_API_URL}/{CollectionName}`. Ответ может быть массивом объектов или объектом с полем `data`, содержащим такой массив. Для удалённых систем используется только HTTPS; HTTP разрешён лишь для loopback-хоста разработки. Токен источника задаётся на сервере в `NAVIGATOR_DATA_API_TOKEN`.

## Проверки

```bash
python backend/security_check.py
python -m unittest discover -s backend/tests -v
```

Секрет подписи токенов должен быть случайным и не короче 32 символов. Пароль технического администратора должен быть не короче 14 символов. Не используй примерные значения из `.env.example` в развёртывании. Все административные маршруты требуют серверной авторизации.
