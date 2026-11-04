"""Фиксирует новые пары и источники общего режима до обращения к движкам."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/ensemble'


def read(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


def write(path, rows):
    text = ''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in rows)
    if path.exists():
        assert path.read_text(encoding='utf-8') == text, path
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')


def main():
    pairs = [
        ('spelling', 'После обеда редактор проверяет заметку.', 'проверяет', 'проверяит', []),
        ('grammar', 'Она хочет закончить отчёт сегодня.', 'хочет', 'хочеть', []),
        ('agreement', 'Эти ребята придут чуть позже.', 'придут', 'придёт', []),
        ('agreement', 'Мы долго искали запасной ключ.', 'искали', 'искала', []),
        ('case', 'Благодаря помощи соседей ремонт завершён.', 'помощи', 'помощь', []),
        ('case', 'Он скучает по своим друзьям.', 'друзьям', 'друзьях', []),
        ('comma', 'Когда стемнело, путешественники вернулись домой.', 'стемнело,', 'стемнело', []),
        ('comma', 'Я заметил, что дверь открыта.', 'заметил,', 'заметил', []),
        ('comma', 'Пожалуйста, закрой окно перед уходом.', 'Пожалуйста,', 'Пожалуйста', []),
        ('agreement', 'В альбоме лежат красные фотографии.', 'красные', 'красный', []),
        ('case', 'В шкафу нет чистых полотенец.', 'полотенец', 'полотенцев', []),
        ('spelling', 'Нужно подъехать к соседнему зданию.', 'подъехать', 'подьехать', []),
        ('name', 'Ливея аккуратно складывает письма.', 'аккуратно', 'акуратно', ['Ливея']),
        ('unknown_name', 'норвета сегодня готовит ужин.', 'готовит', 'готоветь', ['норвета']),
        ('agreement', 'На полке стоят две чашки.', 'чашки', 'чашка', []),
        ('url', 'Запиши адрес: https://example.org/a?q=1 и проверь вложение.', 'вложение', 'вложенние', ['https://example.org/a?q=1']),
        ('crlf', '- Отправь документ.\r\n- Проверь расписание.', 'расписание', 'расписанне', ['\r\n', '- ']),
        ('emoji', '🙂 Эта история кажется невероятной!', 'невероятной', 'невероятнои', ['🙂']),
        ('quoted', 'Термин «кварзит» здесь используется намеренно.', 'используется', 'используетса', ['«кварзит»']),
        ('code', 'Команда `git sttaus` записана в инструкции.', 'инструкции', 'инструкцыи', ['`git sttaus`']),
        ('spacing', 'Сегодня  будет очень тихо.\nЗавтра тоже.', 'очень', 'очинь', ['  ', '\n']),
        ('literal', 'Никнейм Ghbdtn появился в списке гостей.', 'появился', 'появилса', ['Ghbdtn']),
        ('unknown_name', 'пользователь руддщ оставил комментарий.', 'комментарий', 'коментарий', ['руддщ']),
        ('style_control', 'Обычно он пишет попроще и без канцеляризмов.', 'Обычно', 'Обычьно', []),
    ]
    fresh = []
    for i, (category, correct, good, bad, protected) in enumerate(pairs, 1):
        assert correct.count(good) == 1
        error = correct.replace(good, bad)
        for suffix, text, edits in [('correct', correct, []), ('error', error, [{'original': bad, 'replacement': good}])]:
            fresh.append({'id': f'ensemble-{i:03}-{suffix}', 'pair': i, 'split': 'test',
                          'category': category, 'text': text, 'edits': edits, 'protected': protected})
    write(HERE / 'fresh-v1.jsonl', fresh)
    runs = [
        ('ordinary', 'benchmarks/cases-v1.jsonl', 'benchmarks/results/2026-11-03/giga20-gfusion/gigachat20-test.jsonl'),
        ('preservation', 'benchmarks/preservation/cases-v1.jsonl', 'benchmarks/results/2026-11-03/giga20-gfusion/gigachat20-preservation.jsonl'),
        ('precision120', 'benchmarks/prompt-precision/holdout-v1.jsonl', 'benchmarks/results/2026-11-04/prompt-precision/baseline-holdout-raw.jsonl'),
    ]
    rows = []
    for name, data, source in runs:
        cached = {r['id']: r for r in read(ROOT / source) if r.get('type') == 'case'}
        for row in read(ROOT / data):
            if row['split'] != 'test':
                continue
            assert row['text'] == cached[row['id']]['text']
            rows.append({**row, 'run': name, 'cached_giga_row': cached[row['id']]})
    assert not ({r['text'] for r in rows} & {r['text'] for r in fresh})
    rows += [{**row, 'run': 'fresh48'} for row in fresh]
    write(OUT / 'inputs.jsonl', rows)
    paths = [HERE / 'prepare.py', HERE / 'selection.txt', HERE / 'fresh-v1.jsonl',
             ROOT / 'benchmarks/gigachat-prompts/text-json.txt', OUT / 'inputs.jsonl']
    paths += [ROOT / 'tools/model_benchmark' / path for path in [
        'bin/ensemble_check.dart', 'lib/src/ensemble.dart', 'lib/src/ensemble_runtime.dart',
        'lib/src/text_guard.dart', 'lib/src/protected_spans.dart', 'lib/src/hunspell_choices.dart',
        'lib/src/dictionary_checker.dart', 'lib/src/dictionary_engines.dart', 'lib/src/symspell.dart']]
    protocol = {'version': 'ensemble-v1', 'rows': len(rows), 'fresh': len(fresh),
        'profiles': ['lt_guarded', 'priority_union', 'giga_selection'],
        'policy': 'Общий known=OpenCorpora OR Hunspell; независимые предложения SymSpell/Hunspell, все первые 8 вариантов LT, допустимые предложения GigaChat. Только spelling, раскладка отдельной командой. До 32 групп, до 32 замен в группе; превышение прерывает обработку. Нет молчаливого обрезания групп. Приоритет LT/Hunspell-frequency/SymSpell/GigaChat. Альтернативный профиль — закрытый выбор GigaChat, отказ0. Составной вариант LT целиком проходит защиту. Защита и снимок обязательны. Личный словарь пуст. Параметры temperature0 seed42 ctx8192, предложение1024/выбор512 токенов. Число байтов входа не превышает контекст минус ответ и32. Один проход, без итераций и подбора по оценкам.',
        'timing': 'Старые свободные ответы GigaChat повторно используются для изоляции объединения; свежие48 запрашиваются заново. LT и оба словарных механизма запускаются заново для всех448. Последующий выбор GigaChat реальный для каждого непустого списка. Текст без вариантов не считается проверенным без ошибок.',
        'sha256_lf': {str(path.relative_to(ROOT)).replace('\\', '/'): hashlib.sha256(path.read_text(encoding='utf-8').encode()).hexdigest() for path in paths}}
    target = HERE / 'protocol-v1.json'
    content = json.dumps(protocol, ensure_ascii=False, indent=2) + '\n'
    if target.exists():
        assert target.read_text(encoding='utf-8') == content
    else:
        target.write_text(content, encoding='utf-8')
    print(f'Зафиксированы {len(rows)} текстов, в том числе {len(fresh)} новых; ответы ещё не запрашивались.')


if __name__ == '__main__':
    main()
