"""Оценка разработки и независимой проверки; решение выбирается только по dev."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/ensemble-tuning'
DART = r'C:\Users\vostr\code\flutter\bin\dart.bat'


def read(path):
    return [json.loads(s) for s in path.read_text(encoding='utf-8').splitlines() if s.strip()]


def save(path, value, check=False):
    if check or path.exists():
        assert json.loads(path.read_text(encoding='utf-8')) == value, path
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def metrics(rows, profile, run, check):
    path = OUT / f'{run}-{profile}.jsonl'
    records = [{'type': 'metadata', 'profile': profile, 'run': run}]
    for row in rows:
        if profile in ['lt', 'priority']:
            result = {'output': row['lt_output' if profile == 'lt' else 'priority_output']}
        elif profile == 'compact':
            result = row['compact_result']
        else:
            result = row['role_results'][profile]
        item = {key: row[key] for key in ['id', 'category', 'text', 'expected']}
        item.update({'type': 'case', 'output': result['output'], 'seconds': 0.0})
        if 'error' in result:
            item['error'] = result['error']
        records.append(item)
    records.append({'type': 'summary', 'count': len(rows), 'completed': True})
    if check or path.exists():
        assert read(path) == records, path
    else:
        path.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in records), encoding='utf-8')
    comparison = OUT / f'{run}-{profile}-comparison.json'
    if not check and not comparison.exists():
        raw = subprocess.check_output([DART, 'run', 'bin/compare_texts.dart', str(path)], cwd=ROOT / 'tools/model_benchmark', encoding='utf-8')
        save(comparison, json.loads(raw))
    value = json.loads(comparison.read_text(encoding='utf-8'))['results'][0]
    cases = value['cases']
    tp = sum(c['atomic_tp'] for c in cases)
    fp = sum(c['atomic_fp'] for c in cases)
    fn = sum(c['atomic_fn'] for c in cases)
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f05 = 1.25 * precision * recall / (.25 * precision + recall) if precision + recall else 0.0
    outputs = {r['id']: r['output'] for r in records if r['type'] == 'case'}
    protection = sum(any(row['text'].count(fragment) != outputs[row['id']].count(fragment) for fragment in row.get('protected', [])) for row in rows)
    errors = sum('error' in r for r in records)
    return {'clean': sum(c['exact'] and not c['control'] for c in cases),
        'errors': errors, 'controls': value['controls'], 'changed_controls': value['changed_controls'],
        'gold': value['gold_corrections'], 'atomic_tp': tp, 'atomic_fp': fp, 'atomic_fn': fn,
        'precision': precision, 'recall': recall, 'f05': f05, 'protected_failures': protection}


def combine(values):
    keys = ['clean', 'errors', 'controls', 'changed_controls', 'gold', 'atomic_tp', 'atomic_fp', 'atomic_fn', 'protected_failures']
    result = {key: sum(v[key] for v in values) for key in keys}
    tp, fp, fn = (result[k] for k in ['atomic_tp', 'atomic_fp', 'atomic_fn'])
    p = tp / (tp + fp) if tp + fp else 1.0
    r = tp / (tp + fn) if tp + fn else 1.0
    result.update({'precision': p, 'recall': r, 'f05': 1.25 * p * r / (.25 * p + r) if p + r else 0.0})
    return result


def choose(aggregate):
    order = ['agreement', 'clauses', 'inflections', 'context', 'compact']
    candidates = [(name, aggregate[name]) for name in order]
    safe = [(name, m) for name, m in candidates if m['changed_controls'] == m['protected_failures'] == m['errors'] == 0]
    qualified = [(name, m) for name, m in safe if m['precision'] >= .95]
    if qualified:
        selected = max(qualified, key=lambda pair: (pair[1]['clean'], pair[1]['f05'], -order.index(pair[0])))
    elif safe:
        selected = max(safe, key=lambda pair: (pair[1]['f05'], pair[1]['clean'], -order.index(pair[0])))
    else:
        selected = max(candidates, key=lambda pair: pair[1]['f05'] - pair[1]['changed_controls'] / pair[1]['controls'] - pair[1]['protected_failures'] / 448)
    return {'profile': selected[0], 'strict_threshold_met': bool(qualified), 'development': selected[1],
        'rule_sha256_lf': hashlib.sha256((HERE / 'selection-rule.json').read_text(encoding='utf-8').encode()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=['dev', 'fresh'], required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rule = json.loads((HERE / 'selection-rule.json').read_text(encoding='utf-8'))
    if args.phase == 'dev':
        roles = [r for r in read(OUT / 'dev-roles-final2.jsonl') if r.get('type') == 'case']
        compact_raw = read(OUT / 'compact-responses.jsonl')
        assert compact_raw[-1]['completed']
        compact = {(r['run'], r['id']): r for r in compact_raw if r.get('type') == 'case'}
        source = {(r['run'], r['id']): r for r in read(ROOT / 'benchmarks/results/2026-11-04/ensemble/inputs.jsonl')}
        rows = [{**r, 'compact_result': compact[r['run'], r['id']]['compact_result'], 'protected': source[r['run'], r['id']].get('protected', [])} for r in roles]
        assert len(rows) == len(compact) == 448
        profiles = rule['profiles']
    else:
        decision = json.loads((OUT / 'selection-final.json').read_text(encoding='utf-8'))
        assert decision['profile'] != 'compact', 'Для выбранного compact нужен его свежий реальный прогон'
        raw = read(OUT / 'fresh-roles.jsonl')
        assert raw[-1]['completed']
        data = {r['id']: r for r in read(HERE / 'fresh-v1.jsonl')}
        rows = [{**r, 'protected': data[r['id']]['protected']} for r in raw if r.get('type') == 'case']
        assert len(rows) == len(data) == 140
        assert all(r['text'] == data[r['id']]['text'] and r['expected'] == data[r['id']]['edits'] for r in rows)
        profiles = ['lt', 'priority', decision['profile']]
    overview = {}
    for run in dict.fromkeys(r['run'] for r in rows):
        selected = [r for r in rows if r['run'] == run]
        prefix = 'dev-final' if args.phase == 'dev' else 'fresh'
        overview[run] = {p: metrics(selected, p, f'{prefix}-{run}', args.check) for p in profiles}
        print(f'Оценён {args.phase}/{run}', flush=True)
    aggregate = {p: combine([m[p] for m in overview.values()]) for p in profiles}
    name = 'dev-final' if args.phase == 'dev' else 'fresh'
    save(OUT / f'{name}-overview.json', {'runs': overview, 'aggregate': aggregate}, args.check)
    if args.phase == 'dev':
        save(OUT / 'selection-final.json', choose(aggregate), args.check)
    print(json.dumps(aggregate, ensure_ascii=False))


if __name__ == '__main__':
    main()
