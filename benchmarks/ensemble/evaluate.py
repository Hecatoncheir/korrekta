"""Проверяет происхождение вариантов и сравнивает общий режим без запуска моделей."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/ensemble'
DART = r'C:\Users\vostr\code\flutter\bin\dart.bat'


def read(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


def save(path, value, check):
    if check or path.exists():
        assert json.loads(path.read_text(encoding='utf-8')) == value, path
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def call(args):
    return subprocess.check_output(args, cwd=ROOT / 'tools/model_benchmark', encoding='utf-8')


def reconstruct(text, slots, choices):
    assert len(slots) == len(choices)
    output = text
    last_start = -1
    end = 0
    edits = []
    for slot, choice in zip(slots, choices, strict=True):
        start = len(text.encode('utf-16-le')[:slot['start'] * 2].decode('utf-16-le'))
        assert start >= end and start != last_start
        end = start + len(slot['original'])
        last_start = start
        assert text[start:end] == slot['original']
        assert slot['options'][0] == slot['original']
        assert type(choice) is int and 0 <= choice < len(slot['options'])
        edits.append((start, end, slot['options'][choice]))
    for start, end, replacement in reversed(edits):
        output = output[:start] + replacement + output[end:]
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    protocol = json.loads((HERE / 'protocol-v1.json').read_text(encoding='utf-8'))
    for path, sha in protocol['sha256_lf'].items():
        assert hashlib.sha256((ROOT / path).read_text(encoding='utf-8').encode()).hexdigest() == sha, path
    inputs = read(OUT / 'inputs.jsonl')
    prepared_raw = read(OUT / 'collected.jsonl')
    response_raw = read(OUT / 'responses.jsonl')
    assert prepared_raw[-1]['completed'] and response_raw[-1]['completed']
    prepared = [r for r in prepared_raw if r.get('type') == 'case']
    rows = [r for r in response_raw if r.get('type') == 'case']
    assert len(inputs) == len(prepared) == len(rows) == protocol['rows']
    assert len({(r['run'], r['id']) for r in rows}) == len(rows)
    selections = requested = 0
    for source, ready, row in zip(inputs, prepared, rows, strict=True):
        for key in ['run', 'id', 'text', 'category']:
            assert source[key] == ready[key] == row[key]
        assert source['edits'] == ready['expected'] == row['expected']
        for key in ['slots', 'hunspell_slots', 'symspell_slots', 'lt_response', 'giga_response', 'giga_output']:
            assert ready[key] == row[key], key
        assert reconstruct(row['text'], row['slots'], [1] * len(row['slots'])) == row['priority_output']
        requested += bool(row['slots'])
        if 'selection_error' in row:
            assert row['output'] == row['text']
        else:
            assert reconstruct(row['text'], row['slots'], row['choices']) == row['output']
            if row['slots']:
                raw = json.loads(row['selection_response']['response'])
                assert set(raw) == {f'c{i}' for i in range(len(row['slots']))}
                assert [raw[f'c{i}'] for i in range(len(row['slots']))] == row['choices']
                selections += 1
    overview = {}
    for run in dict.fromkeys(r['run'] for r in rows):
        selected = [r for r in rows if r['run'] == run]
        files = []
        for profile, field in [('lt_guarded', 'lt_output'), ('priority_union', 'priority_output'), ('giga_selection', 'output')]:
            path = OUT / f'{run}-{profile}.jsonl'
            files.append(path)
            values = [{'type': 'metadata', 'profile': profile, 'run': run}]
            for row in selected:
                value = {key: row[key] for key in ['id', 'category', 'text', 'expected', 'seconds']}
                value.update({'type': 'case', 'output': row[field]})
                if profile != 'lt_guarded' and ('collection_error' in row or (profile == 'giga_selection' and 'selection_error' in row)):
                    value['error'] = row.get('collection_error', row.get('selection_error'))
                values.append(value)
            values.append({'type': 'summary', 'count': len(selected), 'completed': True})
            if args.check or path.exists():
                assert read(path) == values, path
            else:
                path.write_text(''.join(json.dumps(v, ensure_ascii=False) + '\n' for v in values), encoding='utf-8')
        comparison = OUT / f'{run}-comparison.json'
        if not args.check and not comparison.exists():
            save(comparison, json.loads(call([DART, 'run', 'bin/compare_texts.dart', *map(str, files)])), False)
        compared = json.loads(comparison.read_text(encoding='utf-8'))['results']
        summaries = {}
        for profile, path, result in zip(protocol['profiles'], files, compared, strict=True):
            errors = {r['id'] for r in read(path) if 'error' in r}
            summaries[profile] = {key: result[key] for key in ['count', 'gold_corrections', 'matched_corrections', 'controls', 'changed_controls', 'atomic_precision']}
            summaries[profile]['clean_corrections'] = sum(c['exact'] and not c['control'] and c['id'] not in errors for c in result['cases'])
            summaries[profile]['errors'] = sorted(errors)
        if all('protected' in source for source in inputs if source['run'] == run):
            data = OUT / f'{run}-data.jsonl'
            source_rows = [source for source in inputs if source['run'] == run]
            if not data.exists():
                assert not args.check
                data.write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in source_rows), encoding='utf-8')
            retention = OUT / f'{run}-retention.json'
            if not args.check and not retention.exists():
                subprocess.run(['python', '-X', 'utf8', str(ROOT / 'benchmarks/preservation/check_retention.py'), '--data', str(data), '--output', str(retention), *map(str, files)], check=True, stdout=subprocess.DEVNULL)
            kept = json.loads(retention.read_text(encoding='utf-8'))['results']
            for profile, result in zip(protocol['profiles'], kept, strict=True):
                summaries[profile]['protected_failures'] = result['retention_failures']
        overview[run] = summaries
    save(OUT / 'overview.json', overview, args.check)
    audit = {'rows': len(rows), 'requested_selections': requested, 'valid_selections': selections,
        'collection_errors': sum('collection_error' in r for r in rows),
        'selection_errors': sum('selection_error' in r for r in rows),
        'outside_candidate_changes': 0,
        'fresh_model_proposals': sum(not r['cached_giga'] for r in rows),
        'sources_in_options': dict(Counter(s for r in rows for slot in r['slots'] for sources in slot['sources'] for s in sources))}
    save(OUT / 'audit.json', audit, args.check)
    print(json.dumps(overview, ensure_ascii=False))
    print(json.dumps(audit, ensure_ascii=False))


if __name__ == '__main__':
    main()
