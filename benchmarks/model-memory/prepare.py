"""Офлайн подготовка одинакового текста и официальных шаблонов двух моделей."""

import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/model-memory'


def main():
    os.environ['HF_HOME'] = 'E:/korrekta/cache/huggingface'
    os.environ['HF_HUB_OFFLINE'] = '1'
    from transformers import AutoTokenizer
    from huggingface_hub import snapshot_download
    models = {
        '20b': ('ai-sage/GigaChat-20B-A3B-instruct-v1.5', '8a6075316cd6d41269f7892caf046f7d5aa274a4'),
        '10b': ('ai-sage/GigaChat3.1-10B-A1.8B-bf16', '189fff27a1dee68473960c3d5bca53e0e07a3191'),
    }
    source = [json.loads(s) for s in (ROOT / 'benchmarks/ensemble-tuning/fresh-v1.jsonl').read_text(encoding='utf-8').splitlines()]
    source = [{**r, 'run': 'fixed140'} for r in source]
    paragraphs = [json.loads(s) for s in (ROOT / 'benchmarks/paragraphs-v1.jsonl').read_text(encoding='utf-8').splitlines()]
    source += [{**r, 'run': 'paragraphs', 'protected': r.get('protected', [])} for r in paragraphs]
    prompt = (ROOT / 'benchmarks/gigachat-prompts/text-json.txt').read_text(encoding='utf-8')
    OUT.mkdir(parents=True, exist_ok=True)
    summary = {}
    for key, (repo, revision) in models.items():
        path = Path(snapshot_download(repo, revision=revision, local_files_only=True,
            allow_patterns=['tokenizer*.json', 'special_tokens_map.json', 'chat_template.jinja']))
        tokenizer = AutoTokenizer.from_pretrained(path, local_files_only=True)
        special = json.loads((path / 'tokenizer_config.json').read_text(encoding='utf-8')).get('additional_special_tokens')
        kwargs = {'additional_special_tokens': special} if special else {}
        values = []
        for row in source:
            rendered = tokenizer.apply_chat_template([{'role': 'system', 'content': prompt},
                {'role': 'user', 'content': json.dumps({'text': row['text']}, ensure_ascii=False, separators=(',', ':'))}],
                tokenize=False, add_generation_prompt=True, **kwargs)
            tokens = len(tokenizer.encode(rendered, add_special_tokens=False))
            assert tokens + 1024 < 4096, (key, row['id'], tokens)
            values.append({**row, 'rendered_prompt': rendered, 'prompt_tokens': tokens,
                'prompt_sha256': hashlib.sha256(rendered.encode()).hexdigest()})
        content = ''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in values)
        target = OUT / f'{key}-input.jsonl'
        if target.exists():
            assert target.read_text(encoding='utf-8') == content
        else:
            target.write_text(content, encoding='utf-8')
        summary[key] = {'repo': repo, 'revision': revision, 'rows': len(values), 'max_prompt_tokens': max(r['prompt_tokens'] for r in values),
            'template_sha256': hashlib.sha256(tokenizer.chat_template.encode()).hexdigest(),
            'input_sha256_lf': hashlib.sha256(content.encode()).hexdigest()}
    report = OUT / 'preparation.json'
    if report.exists():
        assert json.loads(report.read_text(encoding='utf-8')) == summary
    else:
        report.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
