"""Новые парные проверки раскладки, оформления и намеренных названий."""

import json
from pathlib import Path

LATIN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
RUSSIAN = "ёйцукенгшщзхъфывапролджэячсмитьбю"
PAIRS = [
    ("доброе утро", "доброе утро", "ru", []),
    ("Спасибо!", "Спасибо", "ru", []),
    ("документ готов", "документ готов", "ru", []),
    ("Нужно проверить файл.", "проверить", "ru", []),
    ("Она открыла папку.", "папку", "ru", []),
    ("Теперь всё работает 🙂", "работает", "ru", ["🙂"]),
    ("План:\r\n\t  завтра обсудим детали.", "обсудим", "ru", ["\r\n\t  "]),
    ("**Итог:** версия готова.", "версия", "ru", ["**Итог:**"]),
    ("Файл note_84.md содержит план.", "содержит", "ru", ["note_84.md"]),
    ("Равина проверяет заметку.", "проверяет", "ru", ["Равина"]),
    ("we are ready", "we are ready", "en", []),
    ("open this file", "open this file", "en", []),
    ("The draft is saved.", "The draft is saved", "en", []),
    ("Пожалуйста, напиши hello.", "hello", "en", []),
    ("Слово world оставлено по-английски.", "world", "en", []),
    ("keep calm", "keep calm", "en", []),
    ("новая запись", "новая запись", "ru", []),
    ("report ready", "report ready", "en", []),
    ("Новая строка:\nзапись сохранена.", "сохранена", "ru", ["\n"]),
    ("Мы идём домой.", "домой", "ru", []),
]
CONTROLS = [
    ("Проект Ghbdtn готов.", ["Ghbdtn"]),
    ("Автор руддщ добавил заметку.", ["руддщ"]),
    ("Идентификатор ghbdtn_id сохранён.", ["ghbdtn_id"]),
    ("Открой файл ghbdtn.txt.", ["ghbdtn.txt"]),
    ("`руддщ` — значение в примере.", ["`руддщ`"]),
    ("Он написал «Ghbdtn» на обложке.", ["«Ghbdtn»"]),
]


def swap(text, source):
    before, after = (RUSSIAN, LATIN) if source == "ru" else (LATIN, RUSSIAN)
    table = str.maketrans(before + before.upper(), after + after.upper())
    return text.translate(table)


def main():
    rows = []
    for index, (correct, fragment, source, protected) in enumerate(PAIRS, 1):
        assert correct.count(fragment) == 1
        wrong = swap(fragment, source)
        for suffix, text, edits in [("correct", correct, []),
                ("error", correct.replace(fragment, wrong, 1), [{"original": wrong, "replacement": fragment}])]:
            rows.append({"id": f"dict-layout-{index:03}-{suffix}", "pair": index,
                         "split": "test", "category": "layout-" + source,
                         "text": text, "edits": edits, "protected": protected})
    for index, (text, protected) in enumerate(CONTROLS, 1):
        rows.append({"id": f"dict-literal-{index:03}", "split": "test",
                     "category": "literal", "text": text, "edits": [], "protected": protected})
    assert len(rows) == len({row["text"] for row in rows}) == 46
    previous = set()
    root = Path(__file__).resolve().parents[2]
    for path in [root / "benchmarks/sber-large/layout-smoke-v1.jsonl", root / "benchmarks/cases-v1.jsonl"]:
        previous.update(json.loads(line)["text"] for line in path.read_text(encoding="utf-8").splitlines())
    assert not previous.intersection(row["text"] for row in rows)
    Path(__file__).with_name("layout-holdout-v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8", newline="\n")
    print("Зафиксированы 20 новых пар раскладки и 6 буквальных названий/технических строк.")


if __name__ == "__main__":
    main()
