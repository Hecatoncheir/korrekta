"""Собирает неизменяемый набор v1 из человекочитаемого файла."""
from collections import Counter
from pathlib import Path
import json

root = Path(__file__).parent
rows = []
counts = Counter()
for line in (root / 'cases-v1.txt').read_text(encoding='utf-8').splitlines():
    if not line or line.startswith('#'):
        continue
    category, text, original, replacement = [part.strip() for part in line.split('|')]
    split = 'dev' if counts[category] % 5 == 0 else 'test'
    counts[category] += 1
    edits = []
    if original:
        if original == replacement or text.count(original) != 1:
            raise ValueError(f'Неправильный эталон: {text}')
        edits = [{'original': original, 'replacement': replacement}]
    rows.append({
        'id': f'ru-{len(rows) + 1:03d}', 'split': split,
        'category': category, 'text': text, 'edits': edits,
    })

if len(rows) != 200 or len({row['text'] for row in rows}) != 200:
    raise ValueError('Набор v1 должен содержать 200 уникальных текстов')

content = '\n'.join(json.dumps(row, ensure_ascii=False) for row in rows) + '\n'
(root / 'cases-v1.jsonl').write_text(content, encoding='utf-8', newline='\n')
print('Набор v1 готов: 200 текстов, 40 dev и 160 test.')
