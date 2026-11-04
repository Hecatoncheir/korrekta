"""Качество, время и память при неизменном выборе inflections."""

import argparse
import json
from pathlib import Path
import statistics
import subprocess

from run import OUT, ROOT, HERE, DART, read, save, verify


def reconstruct(text, slots, choices):
    assert len(slots) == len(choices)
    edits = []
    end = 0
    previous_start = -1
    for slot, choice in zip(slots, choices, strict=True):
        assert type(choice) is int and 0 <= choice < len(slot['options'])
        start = len(text.encode('utf-16-le')[:slot['start'] * 2].decode('utf-16-le'))
        assert start >= end and start != previous_start
        end = start + len(slot['original'])
        assert text[start:end] == slot['original'] == slot['options'][0]
        edits.append((start, end, slot['options'][choice]))
        previous_start = start
    for start, end, value in reversed(edits):
        text = text[:start] + value + text[end:]
    return text


def quantile(values, percent):
    values = sorted(values)
    return values[(len(values) * percent + 99) // 100 - 1]


def score(rows, profile, run, check):
    path = OUT / f'{profile}-{run}-texts.jsonl'
    values = [{'type': 'metadata', 'profile': profile, 'run': run}]
    for row in rows:
        item = {key: row[key] for key in ['id', 'category', 'text', 'expected', 'output', 'seconds']}
        item['type'] = 'case'
        if 'error' in row or 'collection_error' in row:
            item['error'] = row.get('error', row.get('collection_error'))
        values.append(item)
    values.append({'type': 'summary', 'completed': True, 'count': len(rows)})
    if path.exists() or check:
        assert read(path) == values, path
    else:
        path.write_text(''.join(json.dumps(v, ensure_ascii=False) + '\n' for v in values), encoding='utf-8')
    comparison = OUT / f'{profile}-{run}-comparison.json'
    if not comparison.exists() and not check:
        result = subprocess.check_output([DART, 'run', 'bin/compare_texts.dart', str(path)],
            cwd=ROOT / 'tools/model_benchmark', encoding='utf-8')
        save(comparison, json.loads(result))
    result = json.loads(comparison.read_text(encoding='utf-8'))['results'][0]
    errors = {r['id'] for r in values if 'error' in r}
    outputs = {r['id']: r['output'] for r in values if r['type'] == 'case'}
    times = [r['seconds'] for r in rows]
    return {'clean': sum(c['exact'] and not c['control'] and c['id'] not in errors for c in result['cases']),
        'error_texts': sum(bool(r['expected']) for r in rows), 'controls': result['controls'], 'changed_controls': result['changed_controls'],
        'atomic_fp': sum(c['atomic_fp'] for c in result['cases']), 'precision': result['atomic_precision'],
        'protected_failures': sum(any(r['text'].count(p) != outputs[r['id']].count(p) for p in r.get('protected', [])) for r in rows),
        'failures': sorted(errors), 'median_seconds': statistics.median(times), 'p95_seconds': quantile(times, 95),
        'model_median_seconds': statistics.median(r['model_seconds'] for r in rows if 'model_seconds' in r)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    protocol = verify()
    overview = {}
    sampling_summary = {}
    for profile in protocol['profiles']:
        name = profile['id']
        raw = read(OUT / f'{name}.jsonl')
        assert raw[-1]['type'] == 'summary' and raw[-1]['completed']
        rows = [r for r in raw if r.get('type') == 'case']
        inputs = read(OUT / f"{profile['key']}-input.jsonl")
        assert len(rows) == len(inputs) == 143
        for row, source in zip(rows, inputs, strict=True):
            assert all(row[k] == source[k] for k in ['id', 'run', 'text', 'edits', 'rendered_prompt', 'prompt_sha256'])
            assert row['expected'] == source['edits']
            if 'error' not in row:
                response = row['giga_response']['response']
                assert response['model'] == profile['model'] and response['done_reason'] == 'stop'
                assert json.loads(response['response'])['text'] == row['giga_output']
                assert reconstruct(row['text'], row['slots'], row['selection']['choices']) == row['output']
        scores = {run: score([r for r in rows if r['run'] == run], name, run, args.check) for run in ['fixed140', 'paragraphs']}
        resources = json.loads((OUT / f'{name}-resources.json').read_text(encoding='utf-8'))
        samples = read(OUT / f'{name}-samples.jsonl')
        assert resources['samples'] == len(samples) and resources['gpu_observed_peak_mib'] == max(s['gpu_mib'] for s in samples)
        for key, field in [('ollama_rss_observed_peak', 'ollama'), ('dart_rss_observed_peak', 'dart'), ('lt_rss_observed_peak', 'languagetool')]:
            assert resources[key] == max(s[field]['rss'] for s in samples)
        assert resources['ollama_private_observed_peak'] == max(s['ollama']['private'] for s in samples)
        sampling_summary[name] = {'backend_rss_observed_peak': max(sum(s[k]['rss'] for k in ['ollama', 'dart', 'languagetool']) for s in samples),
            'gpu_growth_over_idle_mib': resources['gpu_observed_peak_mib'] - resources['gpu_idle_mib']}
        cold = next(r for r in raw if r['type'] == 'cold_start')
        scores.update({'resources': resources, 'cold_model_seconds': cold['model_seconds'],
            'initialization_seconds': raw[0]['initialization_seconds'], 'model': profile['model'], 'context': profile['context']})
        overview[name] = scores
    baseline = overview['20b-8k']
    accepted = []
    for name, result in overview.items():
        if name == '20b-8k':
            continue
        a, b = result['fixed140'], baseline['fixed140']
        p, q = result['paragraphs'], baseline['paragraphs']
        meets = not a['failures'] and not p['failures'] and a['clean'] >= b['clean'] - 3 and all(a[k] <= b[k] for k in ['changed_controls', 'protected_failures', 'atomic_fp'])
        meets = meets and p['clean'] >= q['clean'] and p['atomic_fp'] <= q['atomic_fp']
        if meets:
            accepted.append(name)
    preferred = min(accepted, key=lambda name: (overview[name]['resources']['resident']['size'], overview[name]['resources']['resident']['size_vram'])) if accepted else '20b-8k'
    decision = {'accepted_economy_profiles': accepted, 'preferred_economy_profile': preferred,
        'quality_reference_preserved': 'benchmarks/best-known.json', 'note': 'Сравнение на знакомом фиксированном наборе, не новая независимая приёмка.'}
    save(OUT / 'overview.json', overview)
    save(OUT / 'decision.json', decision)
    save(OUT / 'resource-summary.json', sampling_summary)
    print(json.dumps({k: {'main': v['fixed140'], 'paragraphs': v['paragraphs'], 'gpu_peak_mib': v['resources']['gpu_observed_peak_mib'],
        'model_vram_bytes': v['resources']['resident']['size_vram'], 'ollama_rss_peak': v['resources']['ollama_rss_observed_peak']} for k, v in overview.items()}, ensure_ascii=False))
    print(json.dumps(decision, ensure_ascii=False))


if __name__ == '__main__':
    main()
