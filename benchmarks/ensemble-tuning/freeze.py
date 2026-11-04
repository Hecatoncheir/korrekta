"""Фиксирует выбранный алгоритм и свежий вход до первого запроса holdout."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/ensemble-tuning'


def digest(path):
    return hashlib.sha256(path.read_text(encoding='utf-8').encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = HERE / 'protocol-v1.json'
    if args.check:
        protocol = json.loads(target.read_text(encoding='utf-8'))
        for path, sha in protocol['sha256_lf'].items():
            assert digest(ROOT / path) == sha, path
        print('Проверены зафиксированные исходники, решение и новый набор.')
        return
    assert not target.exists() and not (OUT / 'fresh-collected.jsonl').exists()
    installed = json.loads(Path('E:/korrekta/dictionaries-v1/manifest.json').read_text(encoding='utf-8'))
    assert installed == json.loads((ROOT / 'benchmarks/dictionaries/data-manifest.json').read_text(encoding='utf-8'))
    selection = json.loads((OUT / 'selection-final.json').read_text(encoding='utf-8'))
    ablation = json.loads((OUT / 'ablation-overview.json').read_text(encoding='utf-8'))
    assert selection['strict_threshold_met'] and not ablation['dominates_full']
    data = [json.loads(s) for s in (HERE / 'fresh-v1.jsonl').read_text(encoding='utf-8').splitlines()]
    text = ''.join(json.dumps({**row, 'run': 'holdout140'}, ensure_ascii=False) + '\n' for row in data)
    (OUT / 'fresh-input.jsonl').write_text(text, encoding='utf-8')
    paths = list((ROOT / 'tools/model_benchmark/lib').rglob('*.dart'))
    paths += [ROOT / 'tools/model_benchmark/bin' / name for name in ['ensemble_check.dart', 'ensemble_roles.dart', 'ensemble_review.dart', 'ensemble_compact.dart']]
    paths += [HERE / name for name in ['fresh-v1.jsonl', 'selection-rule.json', 'ablation-rule.json', 'compact.txt', 'prepare_fresh.py', 'freeze.py']]
    paths += [OUT / name for name in ['fresh-input.jsonl', 'selection-final.json', 'ablation-overview.json']]
    paths += [ROOT / 'benchmarks/gigachat-prompts/text-json.txt', ROOT / 'benchmarks/dictionaries/data-manifest.json']
    value = {'version': 'ensemble-roles-v1', 'created_utc': datetime.now(timezone.utc).isoformat(),
        'profile': selection['profile'], 'channels': ['OpenCorpora/shared-lexicon', 'SymSpell', 'Hunspell', 'LanguageTool6.8', 'GigaChat20B-Q4_K_M'],
        'development': 448, 'holdout': {'count': len(data), 'errors': sum(bool(r['edits']) for r in data)},
        'policy': 'Один свежий сбор всех источников, без кеша свободных ответов GigaChat. Предыдущие448 теперь только dev. Свежая основная оценка: выбранный inflections + LT + прежний priority. Остальные роли не выбирать по свежим данным. Пропущенные кандидаты сохранять на просмотр, не считать текст правильным. Все источники локально; без новых установок и весов. Параметры8k/temp0/seed42, один проход. Личный словарь пуст. Автораспознавание имён не гарантируется.',
        'sha256_lf': {str(p.relative_to(ROOT)).replace('\\', '/'): digest(p) for p in sorted(paths)}}
    target.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Зафиксированы решение, исходники и 140 новых текстов до первого запроса.')


if __name__ == '__main__':
    main()
