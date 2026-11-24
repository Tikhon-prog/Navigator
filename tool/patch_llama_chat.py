"""Патч llama.cpp: llm_chat_detect_template не бросает исключение для Jinja-шаблона.

Пакет llm_llamacpp всегда передаёт в llama_chat_apply_template шаблон модели.
llama.cpp ищет его в таблице через map::at (исключение out_of_range, которое сам
же ловит). В процессе Flutter любое C++-исключение заканчивается terminate,
поэтому заменяем на поиск без исключения.

Запуск: python3 tool/patch_llama_chat.py <путь к src/llama-chat.cpp>
"""
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pattern = re.compile(
    r"try\s*\{\s*return llm_chat_template_from_str\(tmpl\);\s*\}\s*"
    r"catch\s*\(const std::out_of_range\s*&\)\s*\{[^}]*\}"
)
replacement = (
    "{ auto it = LLM_CHAT_TEMPLATES.find(tmpl);"
    " if (it != LLM_CHAT_TEMPLATES.end()) { return it->second; } }"
)
new_text, count = pattern.subn(replacement, text, count=1)
if count:
    open(path, "w", encoding="utf-8").write(new_text)
    print("Патч llama-chat.cpp применён")
elif "LLM_CHAT_TEMPLATES.find(tmpl)" in text:
    print("Патч llama-chat.cpp уже применён")
else:
    print("ВНИМАНИЕ: место для патча не найдено", file=sys.stderr)
    sys.exit(1)
