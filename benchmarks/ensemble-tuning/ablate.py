"""Оценивает вклад каналов предложений только на старых данных."""

import argparse
import json
from pathlib import Path

from evaluate import OUT, ROOT, read, save, metrics


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    raw = read(OUT / 'dev-ablations.jsonl')
    assert raw[-1]['completed']
    sources = {(r['run'], r['id']): r for r in read(ROOT / 'benchmarks/results/2026-11-04/ensemble/inputs.jsonl')}
    rows = []
    for row in raw:
        if row.get('type') != 'case':
            continue
        results = {f'without_{source}': value['result'] for source, value in row['ablations'].items()}
        rows.append({**row, 'role_results': results, 'protected': sources[row['run'], row['id']].get('protected', [])})
    assert len(rows) == 448 and len({r['id'] for r in rows}) == 448
    overview = {name: metrics(rows, name, 'ablation', args.check) for name in rows[0]['role_results']}
    full = json.loads((OUT / 'selection-final.json').read_text(encoding='utf-8'))['development']
    dominating = []
    for name, value in overview.items():
        no_worse = value['clean'] >= full['clean'] and all(value[k] <= full[k] for k in ['atomic_fp', 'changed_controls', 'protected_failures'])
        better = value['clean'] > full['clean'] or any(value[k] < full[k] for k in ['atomic_fp', 'changed_controls', 'protected_failures'])
        if no_worse and better:
            dominating.append(name)
    save(OUT / 'ablation-overview.json', {'all': full, 'without': overview, 'dominates_full': dominating}, args.check)
    print(json.dumps({'without': overview, 'dominates_full': dominating}, ensure_ascii=False))


if __name__ == '__main__':
    main()
