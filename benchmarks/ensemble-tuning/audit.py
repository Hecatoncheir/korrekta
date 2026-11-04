"""Независимо восстанавливает выбор из готовых вариантов и проверяет происхождение."""

import hashlib
import json
from pathlib import Path
import re

from evaluate import OUT, HERE, ROOT, read, save


def reconstruct(text, slots, choices):
    assert len(slots) == len(choices)
    edits = []
    previous_start = -1
    previous_end = 0
    for slot, choice in zip(slots, choices, strict=True):
        assert type(choice) is int and 0 <= choice < len(slot['options'])
        start = len(text.encode('utf-16-le')[:slot['start'] * 2].decode('utf-16-le'))
        end = start + len(slot['original'])
        assert start >= previous_end and start != previous_start
        assert text[start:end] == slot['original'] == slot['options'][0]
        edits.append((start, end, slot['options'][choice]))
        previous_start, previous_end = start, end
    output = text
    for start, end, replacement in reversed(edits):
        output = output[:start] + replacement + output[end:]
    return output


def cases(path):
    rows = read(path)
    assert rows[-1]['type'] == 'summary' and rows[-1]['completed']
    return [r for r in rows if r.get('type') == 'case']


def main():
    protocol = json.loads((HERE / 'protocol-v1.json').read_text(encoding='utf-8'))
    for path, sha in protocol['sha256_lf'].items():
        assert hashlib.sha256((ROOT / path).read_text(encoding='utf-8').encode()).hexdigest() == sha, path
    dev = cases(OUT / 'dev-roles-final2.jsonl')
    compact = cases(OUT / 'compact-responses.jsonl')
    assert len(dev) == len(compact) == 448
    for row, other in zip(dev, compact, strict=True):
        assert row['text'] == other['text'] and row['id'] == other['id'] and row['slots'] == other['slots']
        for result in row['role_results'].values():
            assert reconstruct(row['text'], row['slots'], result['choices']) == result['output']
        result = other['compact_result']
        if 'error' not in result:
            assert reconstruct(row['text'], row['slots'], result['choices']) == result['output']
    fresh = cases(OUT / 'fresh-roles.jsonl')
    collected = cases(OUT / 'fresh-collected.jsonl')
    source = read(HERE / 'fresh-v1.jsonl')
    assert len(fresh) == len(collected) == len(source) == 140
    for row, original, data in zip(fresh, collected, source, strict=True):
        assert row['id'] == original['id'] == data['id']
        assert row['text'] == original['text'] == data['text']
        assert row['expected'] == original['expected'] == data['edits']
        for key in ['slots', 'giga_output', 'lt_response', 'giga_response']:
            assert row[key] == original[key]
        assert not row['cached_giga']
        if 'collection_error' not in row:
            response = json.loads(row['giga_response']['response'])
            assert set(response) == {'text'} and response['text'] == row['giga_output']
        assert set(row['role_results']) == {protocol['profile']}
        result = row['role_results'][protocol['profile']]
        assert reconstruct(row['text'], row['slots'], result['choices']) == result['output']
        assert re.findall(r'\s+', row['text']) == re.findall(r'\s+', result['output'])
    audit = {'development': 448, 'compact_requests': sum(bool(r['slots']) for r in compact),
        'compact_failures': sum('error' in r['compact_result'] for r in compact),
        'fresh': 140, 'fresh_model_proposals': sum(not r['cached_giga'] for r in fresh),
        'fresh_collection_errors': sum('collection_error' in r for r in fresh),
        'outside_candidate_changes': 0, 'whitespace_sequence_changes': 0,
        'chosen_profile': protocol['profile']}
    save(OUT / 'audit.json', audit)
    print(json.dumps(audit, ensure_ascii=False))


if __name__ == '__main__':
    main()
