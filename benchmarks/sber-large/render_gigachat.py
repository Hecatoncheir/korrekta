"""Подготовка запросов с официальным шаблоном GigaChat без загрузки новых весов."""

import argparse
import hashlib
import json
import os
from pathlib import Path

MODEL = "ai-sage/GigaChat3.1-10B-A1.8B-bf16"
REVISION = "189fff27a1dee68473960c3d5bca53e0e07a3191"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", required=True)
    parser.add_argument("--prompt", default="benchmarks/prompt-v1.txt")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    os.environ["HF_HOME"] = "E:/korrekta/cache/huggingface"
    os.environ["HF_HUB_DISABLE_XET"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer

    path = Path(snapshot_download(MODEL, revision=REVISION, allow_patterns=["tokenizer*.json", "special_tokens_map.json", "chat_template.jinja"]))
    tokenizer = AutoTokenizer.from_pretrained(path, local_files_only=True)
    template_hash = hashlib.sha256((path / "chat_template.jinja").read_bytes()).hexdigest()
    prompt = Path(args.prompt).read_text(encoding="utf-8")
    rows = [json.loads(line) for line in Path(args.data).read_text(encoding="utf-8").splitlines() if line.strip()]
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as sink:
        for row in rows:
            rendered = tokenizer.apply_chat_template(
                [{"role": "system", "content": prompt},
                 {"role": "user", "content": json.dumps({"text": row["text"]}, ensure_ascii=False)}],
                tokenize=False, add_generation_prompt=True,
            )
            result = {**row, "rendered_prompt": rendered,
                      "rendered_prompt_sha256": hashlib.sha256(rendered.encode()).hexdigest(),
                      "prompt_source": {"model": MODEL, "revision": REVISION, "chat_template_sha256": template_hash}}
            sink.write(json.dumps(result, ensure_ascii=False) + "\n")
    print(f"Подготовлено {len(rows)} запросов, SHA-256 шаблона {template_hash}")


if __name__ == "__main__":
    main()
