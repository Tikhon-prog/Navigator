import json
import re
import sys
import urllib.parse
import urllib.request
import http.cookiejar
from html import unescape

BASE_URL = "https://intranet.pokolenie.school/"


DAY_NUMBERS = {
    "понедельник": 1,
    "вторник": 2,
    "среда": 3,
    "четверг": 4,
    "пятница": 5,
    "суббота": 6,
}


def clean_text(value):
    value = unescape(value or "")
    value = re.sub(r"<script\b[\s\S]*?</script>", " ", value, flags=re.I)
    value = re.sub(r"<style\b[\s\S]*?</style>", " ", value, flags=re.I)
    value = re.sub(r"<[^>]+>", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def attr(tag, name):
    if not tag:
        return ""
    match = re.search(
        rf"\b{re.escape(name)}\s*=\s*([\"'])(.*?)\1",
        tag,
        flags=re.I | re.S,
    )
    return unescape(match.group(2)).strip() if match else ""


def text_tag(html, tag):
    match = re.search(
        rf"<{tag}\b[^>]*>([\s\S]*?)</{tag}>",
        html,
        flags=re.I,
    )
    return clean_text(match.group(1)) if match else ""


def text_class(html, class_name, tag=r"[A-Za-z][A-Za-z0-9-]*"):
    match = re.search(
        rf"<{tag}\b[^>]*class\s*=\s*([\"'])"
        rf"(?=[^\"']*\b{re.escape(class_name)}\b)"
        rf"[^\"']*\1[^>]*>"
        rf"([\s\S]*?)"
        rf"</{tag}>",
        html,
        flags=re.I,
    )
    return clean_text(match.group(2)) if match else ""


def input_value(html, name):
    match = re.search(
        rf"<input\b[^>]*\bname\s*=\s*([\"']){re.escape(name)}\1[^>]*>",
        html,
        flags=re.I,
    )
    return attr(match.group(0), "value") if match else ""


def number(value):
    match = re.search(r"\d+", value or "")
    return int(match.group()) if match else 0


def parse_json_schedule(value):
    if not value:
        return []

    try:
        data = json.loads(unescape(value))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []

    if not isinstance(data, list):
        return []

    result = []

    for item in data:
        if not isinstance(item, dict):
            continue

        result.append({
            "day": int(item.get("day", 0) or 0),
            "start": int(item.get("start", 0) or 0),
            "end": int(item.get("end", 0) or 0),
            "room": str(item.get("room", "")).strip(),
        })

    return result


def parse_displayed_schedule(text):
    if not text:
        return []

    pattern = re.compile(
        r"(Понедельник|Вторник|Среда|Четверг|Пятница|Суббота)"
        r"\s*·\s*уроки\s+(\d+)\s*[–-]\s*(\d+)"
        r"\s*·\s*(.+?)"
        r"(?=\s*(?:Понедельник|Вторник|Среда|Четверг|"
        r"Пятница|Суббота)\s*·|$)",
        flags=re.I,
    )

    result = []

    for match in pattern.finditer(text):
        room = re.sub(
            r"\s*КАБИНЕТ\s*$",
            "",
            match.group(4).strip(),
            flags=re.I,
        )

        result.append({
            "day": DAY_NUMBERS.get(
                match.group(1).strip().lower(),
                0,
            ),
            "start": int(match.group(2)),
            "end": int(match.group(3)),
            "room": room.strip(),
        })

    return result


def parse_catalog(html):
    programs = []

    cards = re.finditer(
        r'<article\b[^>]*\bdata-program-card\s*=\s*(["\'])(\d+)\1[^>]*>'
        r'([\s\S]*?)</article>',
        html,
        flags=re.I,
    )

    for card in cards:
        program_id = int(card.group(2))
        body = card.group(3)

        name = text_tag(body, "h2")
        if not name:
            continue

        direction = text_class(body, "direction-badge")
        hours = number(text_class(body, "hours-badge"))
        classes = text_class(body, "program-class-badge")
        start_date = text_class(body, "start-date-badge")

        subgroups = []

        for sg_match in re.finditer(
            r'<section\b[^>]*\bdata-subgroup-card\b[^>]*>'
            r'([\s\S]*?)</section>',
            body,
            flags=re.I,
        ):
            subgroup_html = sg_match.group(1)

            input_match = re.search(
                r'<input\b[^>]*\bclass\s*=\s*(["\'])'
                r'[^"\']*\bdiscipline-checkbox\b[^"\']*\1[^>]*>',
                subgroup_html,
                flags=re.I,
            )

            if not input_match:
                continue

            input_tag = input_match.group(0)
            subgroup_id = attr(input_tag, "data-subgroup-id")

            if not subgroup_id:
                continue

            input_program_id = attr(input_tag, "data-program-id")

            subgroups.append({
                "program_id": int(input_program_id or program_id),
                "subgroup_id": int(subgroup_id),
                "name": attr(input_tag, "data-name") or name,
                "hours": int(attr(input_tag, "data-hours") or hours),
                "limit_hours": int(
                    attr(input_tag, "data-limit-hours")
                    or attr(input_tag, "data-hours")
                    or hours
                ),
                "teacher": extract_teacher(subgroup_html),
                "schedule": parse_json_schedule(
                    attr(input_tag, "data-schedule")
                ),
                "supplies": (
                    text_class(
                        subgroup_html,
                        "supplies-inline-text",
                    )
                    or None
                ),
            })

        programs.append({
            "program_id": program_id,
            "name": name,
            "direction": direction,
            "hours": hours,
            "classes": classes,
            "start_date": start_date or None,
            "subgroups": subgroups,
        })

    return programs


def extract_teacher(html):
    block = text_class(
        html,
        "program-subgroup-teacher",
    )

    # Реальная разметка: div.program-subgroup-teacher -> b.
    teacher = text_tag(block, "b")
    return teacher or block


def parse_current_application(html):
    choices = []

    for card in re.finditer(
        r'<article\b[^>]*class\s*=\s*(["\'])'
        r'[^"\']*\bsuccess-program-card\b[^"\']*\1[^>]*>'
        r'([\s\S]*?)</article>',
        html,
        flags=re.I,
    ):
        body = card.group(2)

        name = text_class(
            body,
            "success-program-name",
            tag="strong",
        )

        if not name:
            continue

        choices.append({
            "name": name,
            "hours": number(text_class(body, "hours-badge")),
            "teacher": extract_teacher(body),
            "schedule": parse_displayed_schedule(
                text_class(body, "program-subgroup-schedule")
            ),
            "start_date": text_class(
                body,
                "start-date-badge",
            ) or None,
        })

    return choices


def schedule_key(item):
    return (
        item["day"],
        item["start"],
        item["end"],
        item["room"].strip().lower(),
    )


def same_schedule(left, right):
    return sorted(map(schedule_key, left)) == sorted(map(schedule_key, right))


def find_program(programs, name):
    wanted = name.strip().casefold()

    for program in programs:
        if program["name"].strip().casefold() == wanted:
            return program

    return None


def find_subgroup(program, choice):
    subgroups = program.get("subgroups", [])

    if not subgroups:
        return None

    teacher = choice.get("teacher", "").strip()

    if teacher:
        matches = [
            subgroup
            for subgroup in subgroups
            if subgroup.get("teacher", "").strip() == teacher
        ]

        if len(matches) == 1:
            return matches[0]

        if matches and choice.get("schedule"):
            for subgroup in matches:
                if same_schedule(
                    subgroup.get("schedule", []),
                    choice["schedule"],
                ):
                    return subgroup

        if matches:
            return matches[0]

    if choice.get("schedule"):
        matches = [
            subgroup
            for subgroup in subgroups
            if same_schedule(
                subgroup.get("schedule", []),
                choice["schedule"],
            )
        ]

        if matches:
            return matches[0]

    return subgroups[0]


def merge_current(programs, choices):
    result = []

    for choice in choices:
        program = find_program(programs, choice["name"])

        if program is None:
            result.append({
                "program_id": 0,
                "subgroup_id": 0,
                "name": choice["name"],
                "hours": choice["hours"],
                "limit_hours": choice["hours"],
                "teacher": choice["teacher"],
                "schedule": choice["schedule"],
                "supplies": None,
                "source": "current_application_only",
            })
            continue

        subgroup = find_subgroup(program, choice)

        if subgroup is None:
            continue

        item = dict(subgroup)

        # current_application.php is authoritative for the current choice.
        item["name"] = choice["name"]
        if choice["hours"]:
            item["hours"] = choice["hours"]
        if choice["teacher"]:
            item["teacher"] = choice["teacher"]
        if choice["schedule"]:
            item["schedule"] = choice["schedule"]
        if choice["start_date"]:
            item["start_date"] = choice["start_date"]

        item["direction"] = program["direction"]
        item["classes"] = program["classes"]
        item["source"] = "catalog+current_application"

        result.append(item)

    return result


def ask_student():
    print("=" * 60)
    print("«Поколение» — тест парсера ДОП")
    print("=" * 60)
    print()

    last_name = input("Фамилия: ").strip()
    first_name = input("Имя: ").strip()
    class_number = input("Класс: ").strip()
    class_letter = input("Буква: ").strip().upper()

    print()
    profile = input(
        "Профиль (для 8 класса можно Enter): "
    ).strip()

    print()
    residence = input(
        "Проживание [1=day, 2=boarding, Enter=day]: "
    ).strip()

    residence_type = (
        "boarding"
        if residence == "2"
        else "day"
    )

    if not last_name or not first_name:
        raise ValueError("ФИО не может быть пустым.")

    if not re.fullmatch(r"\d{1,2}", class_number):
        raise ValueError("Класс должен быть числом, например 8.")

    if not re.fullmatch(r"[А-ЯЁA-Z]", class_letter):
        raise ValueError("Буква класса должна быть одной буквой.")

    return {
        "last_name": last_name,
        "first_name": first_name,
        "class_number": class_number,
        "class_letter": class_letter,
        "profile": profile,
        "residence_type": residence_type,
    }


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

    student = ask_student()

    print()
    print("Создаём HTTP-сессию...")

    jar = http.cookiejar.CookieJar()

    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar)
    )

    opener.addheaders = [
        (
            "User-Agent",
            "Pokolenie-Dop-Test/1.1 "
            "(Python urllib)",
        )
    ]

    print("GET / ...")

    request = urllib.request.Request(BASE_URL)

    try:
        response = opener.open(
            request,
            timeout=20,
        )
    except Exception as exc:
        raise RuntimeError(
            "Не удалось открыть intranet: "
            + str(exc)
        ) from exc

    first_html = response.read().decode(
        "utf-8",
        errors="replace",
    )
    first_url = response.geturl()

    csrf = input_value(first_html, "csrf_token")

    if not csrf:
        raise RuntimeError(
            "CSRF-токен не найден."
        )

    print("CSRF найден.")
    print("POST данные ученика...")

    payload = {
        "csrf_token": csrf,
        **student,
    }

    request = urllib.request.Request(
        first_url,
        data=urllib.parse.urlencode(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type":
                "application/x-www-form-urlencoded; charset=UTF-8",
        },
    )

    try:
        response = opener.open(
            request,
            timeout=20,
        )
    except Exception as exc:
        raise RuntimeError(
            "POST к intranet завершился ошибкой: "
            + str(exc)
        ) from exc

    catalog_html = response.read().decode(
        "utf-8",
        errors="replace",
    )
    catalog_url = response.geturl()

    programs = parse_catalog(catalog_html)

    print(
        f"Каталог: найдено {len(programs)} программ."
    )

    if not programs:
        raise RuntimeError(
            "Каталог пуст. Проверь ФИО/класс/доступ к intranet."
        )

    current_url = urllib.parse.urljoin(
        catalog_url,
        "current_application.php",
    )

    print("GET current_application.php ...")

    try:
        response = opener.open(urllib.request.Request(current_url), timeout=20)
    except Exception as exc:
        raise RuntimeError(
            "Не удалось открыть current_application.php: "
            + str(exc)
        ) from exc

    current_html = response.read().decode(
        "utf-8",
        errors="replace",
    )

    choices = parse_current_application(
        current_html
    )

    print(
        f"Текущих выбранных программ: {len(choices)}"
    )

    result = merge_current(programs, choices)

    print()
    print("=" * 60)
    print("АКТУАЛЬНЫЕ ДОПЫ")
    print("=" * 60)

    for index, item in enumerate(result, 1):
        print()
        print(f"{index}. {item['name']}")
        print(
            f"   ID: {item['program_id']}:"
            f"{item['subgroup_id']}"
        )
        print(
            f"   Часы: {item['hours']} ч/нед."
        )
        print(
            "   Преподаватель: "
            + (item["teacher"] or "—")
        )

        if item["schedule"]:
            for slot in item["schedule"]:
                days = {
                    1: "Пн",
                    2: "Вт",
                    3: "Ср",
                    4: "Чт",
                    5: "Пт",
                    6: "Сб",
                }

                print(
                    f"   {days.get(slot['day'], '?')} "
                    f"уроки {slot['start']}–{slot['end']} "
                    f"• {slot['room'] or 'кабинет не указан'}"
                )
        else:
            print(
                "   Расписание: нет актуального слота"
            )

    output = {
        "student": student,
        "available_programs": len(programs),
        "current_programs": len(choices),
        "disciplines": result,
    }

    with open(
        "dop_test_result.json",
        "w",
        encoding="utf-8",
    ) as file:
        json.dump(
            output,
            file,
            ensure_ascii=False,
            indent=2,
        )

    print()
    print("Результат:")
    print("  dop_test_result.json")
    print()
    print(
        f"Итого: {len(result)} актуальных дисциплин."
    )


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nОстановлено пользователем.")
        sys.exit(130)
    except Exception as exc:
        print()
        print("ОШИБКА:", exc)
        sys.exit(1)
