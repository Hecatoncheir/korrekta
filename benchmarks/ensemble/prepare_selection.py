"""Готовит вход выбора и сверяет Dart-форму с локальным официальным шаблоном."""

import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/ensemble'


def main():
    os.environ['HF_HOME'] = 'E:/korrekta/cache/huggingface'
    os.environ['HF_HUB_OFFLINE'] = '1'
    from transformers import AutoTokenizer
    from huggingface_hub import snapshot_download
    path = Path(snapshot_download('ai-sage/GigaChat-20B-A3B-instruct-v1.5',
        revision='8a6075316cd6d41269f7892caf046f7d5aa274a4', local_files_only=True,
        allow_patterns=['tokenizer*.json', 'special_tokens_map.json']))
    tokenizer = AutoTokenizer.from_pretrained(path, local_files_only=True)
    special = json.loads((path / 'tokenizer_config.json').read_text(encoding='utf-8'))['additional_special_tokens']
    raw = [json.loads(s) for s in (OUT / 'collected.jsonl').read_text(encoding='utf-8').splitlines()]
    assert raw[-1]['completed']
    rows = [row for row in raw if row.get('type') == 'case']
    system = (HERE / 'selection.txt').read_text(encoding='utf-8')
    maximum = 0
    for row in rows:
        payload = json.dumps({'text': row['text'], 'slots': row['slots']}, ensure_ascii=False, separators=(',', ':'))
        rendered = tokenizer.apply_chat_template([{'role': 'system', 'content': system},
            {'role': 'user', 'content': payload}], tokenize=False, add_generation_prompt=True,
            additional_special_tokens=special)
        dart_form = f'<s>{system}<|message_sep|>user<|role_sep|>{payload}<|message_sep|>available functions<|role_sep|>[]<|message_sep|>assistant<|role_sep|>'
        assert rendered == dart_form
        tokens = len(tokenizer.encode(rendered, add_special_tokens=False))
        assert tokens + 512 < 8192
        assert len(rendered.encode()) + 512 + 32 <= 8192
        maximum = max(maximum, tokens)
    text = ''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in rows)
    target = OUT / 'selection-input.jsonl'
    if target.exists():
        assert target.read_text(encoding='utf-8') == text
    else:
        target.write_text(text, encoding='utf-8')
    audit = {'rows': len(rows), 'maximum_selection_tokens': maximum,
        'official_template_matches_dart_form': True,
        'sha256_lf': hashlib.sha256(text.encode()).hexdigest()}
    report = OUT / 'selection-preparation.json'
    if report.exists():
        assert json.loads(report.read_text(encoding='utf-8')) == audit
    else:
        report.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(audit))


if __name__ == '__main__':
    main()
