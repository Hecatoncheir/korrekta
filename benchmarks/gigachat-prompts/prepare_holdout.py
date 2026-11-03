"""Отложенные парные контексты для сравнения запросов к GigaChat."""

import json
import hashlib
from pathlib import Path

PAIRS = [
    ("plain", "Эта инструкция помогает разобраться с настройками.", "помогает", "помогаит", []),
    ("plain", "Участники вернулись в зал после перерыва.", "вернулись", "вернулся", []),
    ("plain", "Я заметил, что дверь осталась открытой.", "заметил, что", "заметил что", []),
    ("plain", "Мне хочется обсудить результаты завтра.", "хочется", "хочеться", []),
    ("plain", "Вдали показалась небольшая деревня.", "показалась", "показался", []),
    ("plain", "Мы обязательно сохраним копию письма.", "обязательно", "обезательно", []),
    ("plain", "Учитель попросил ребят открыть тетради.", "попросил", "попросела", []),
    ("plain", "Я уверен, что встреча пройдёт спокойно.", "уверен, что", "уверен что", []),
    ("plain", "Этот способ оказался довольно удобным.", "оказался", "оказалась", []),
    ("plain", "На лестнице послышались тихие шаги.", "послышались", "послышался", []),
    ("names_quotes", "Ривена подготовила материалы к семинару.", "подготовила", "подготовил", ["Ривена"]),
    ("names_quotes", "Селина записала адрес нового офиса.", "записала", "записал", ["Селина"]),
    ("names_quotes", "Приложение PaperMoss сохраняет заметки на устройстве.", "сохраняет", "сохроняет", ["PaperMoss"]),
    ("names_quotes", "Сервис «Лисолист» работает даже без сети.", "работает", "работают", ["«Лисолист»"]),
    ("names_quotes", "Этот рассказ «Пятый причал» понравился редактору.", "понравился", "понравилась", ["«Пятый причал»"]),
    ("names_quotes", "Она уверена, что название „Медный сад“ подходит книге.", "уверена", "уверен", ["„Медный сад“"]),
    ("names_quotes", 'Мы оставили имя папки "Записки на полях" без изменений.', "оставили", "оставеле", ['"Записки на полях"']),
    ("names_quotes", "Автор arlo_notes добавил новую запись.", "добавил", "добавела", ["arlo_notes"]),
    ("names_quotes", "Тэо проверил документы перед отправкой.", "проверил", "проверел", ["Тэо"]),
    ("names_quotes", "Коллекция «Три фонаря» появилась в каталоге.", "появилась", "появился", ["«Три фонаря»"]),
    ("emoji_layout", "Мы сохранили все фотографии 📷", "сохранили", "сохронели", ["📷"]),
    ("emoji_layout", "Она согласна с предложенным планом 🤝", "согласна", "согласен", ["🤝"]),
    ("emoji_layout", "Мне нравится этот спокойный вечер 🌙", "нравится", "нравиться", ["🌙"]),
    ("emoji_layout", "Документы уже отправлены 👍🏻", "отправлены", "отправлено", ["👍🏻"]),
    ("emoji_layout", "Я обязательно вернусь к этой задаче 🧑‍🔬", "обязательно", "обезательно", ["🧑‍🔬"]),
    ("emoji_layout", "Введение готово.\n\nДальше начинается основная часть.", "начинается", "начинаеться", ["\n\n"]),
    ("emoji_layout", "- Блокнот лежит в сумке.\n- Карандаш находится рядом.", "находится", "находиться", ["- Блокнот лежит в сумке.\n- "]),
    ("emoji_layout", "План:\n    Команда проверяет новый вариант.", "проверяет", "проверяит", ["\n    "]),
    ("emoji_layout", "**Примечание:** эта настройка сохраняется автоматически.", "сохраняется", "сохраняеться", ["**Примечание:**"]),
    ("emoji_layout", "Ответ:  версия уже доступна для установки.", "доступна", "доступен", [":  "]),
    ("technical", "Файл summary_11.md содержит описание изменений.", "содержит", "содержыт", ["summary_11.md"]),
    ("technical", "Страница https://example.net/notes?id=17 доступна без регистрации.", "доступна", "доступен", ["https://example.net/notes?id=17"]),
    ("technical", "Заявку необходимо отправить на team@example.net.", "необходимо", "необхадимо", ["team@example.net"]),
    ("technical", r"Папка E:\Archive\notes хранится на внешнем диске.", "хранится", "храниться", [r"E:\Archive\notes"]),
    ("technical", "Параметр `timeout_ms=5000` задаёт время ожидания.", "задаёт", "задаёть", ["`timeout_ms=5000`"]),
    ("technical", 'Объект {"local":true,"lang":"ru"} передаётся без изменений.', "передаётся", "передаёться", ['{"local":true,"lang":"ru"}']),
    ("technical", "Код RX-2048 указан в подтверждении заказа.", "указан", "указана", ["RX-2048"]),
    ("technical", "Версия v1.8.0-rc.3 прошла дополнительную проверку.", "прошла", "прошёл", ["v1.8.0-rc.3"]),
    ("technical", "Команда `flutter doctor -v` показывает сведения о системе.", "показывает", "показываит", ["`flutter doctor -v`"]),
    ("technical", "Метод openNote() возвращает выбранную запись.", "возвращает", "возвращаить", ["openNote()"]),
]


def main():
    root = Path(__file__).resolve().parents[1]
    previous = set()
    for path in [root / "cases-v1.jsonl", root / "preservation/cases-v1.jsonl"]:
        previous.update(json.loads(line)["text"] for line in path.read_text(encoding="utf-8").splitlines())
    rows = []
    for index, (category, correct, good, bad, protected) in enumerate(PAIRS, 1):
        if correct.count(good) != 1:
            raise ValueError(f"Неоднозначный эталон {index}")
        erroneous = correct.replace(good, bad, 1)
        if erroneous.count(bad) != 1:
            raise ValueError(f"Неоднозначная ошибка {index}")
        for suffix, text, edits in [
            ("correct", correct, []),
            ("error", erroneous, [{"original": bad, "replacement": good}]),
        ]:
            if any(not value or text.count(value) != correct.count(value) for value in protected):
                raise ValueError(f"Эталон меняет защищённый фрагмент {index}")
            rows.append({"id": f"prompt-{index:03}-{suffix}", "pair": index, "split": "test",
                         "category": category, "text": text, "edits": edits, "protected": protected})
    texts = {row["text"] for row in rows}
    if len(rows) != 80 or len(texts) != 80 or texts & previous:
        raise ValueError("Повтор или неправильный размер нового набора")
    Path(__file__).with_name("holdout-v1.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8", newline="\n")
    checksum_file = Path(__file__).with_name("checksums-v1.json")
    if checksum_file.exists():
        expected = json.loads(checksum_file.read_text(encoding="utf-8"))
        for name, checksum in expected.items():
            text = (root.parent / name).read_text(encoding="utf-8")
            if hashlib.sha256(text.encode()).hexdigest() != checksum:
                raise ValueError(f"Изменён зафиксированный вход протокола v1: {name}")
    print("Зафиксировано 80 текстов: 40 новых парных контекстов")


if __name__ == "__main__":
    main()
