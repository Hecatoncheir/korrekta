"""Локальный официальный шаблон GigaChat с вариантами, без эталонов."""

import argparse
import hashlib
import json
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    os.environ["HF_HOME"] = "E:/korrekta/cache/huggingface"
    os.environ["HF_HUB_OFFLINE"] = "1"
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer
    revision = "8a6075316cd6d41269f7892caf046f7d5aa274a4"
    model = "ai-sage/GigaChat-20B-A3B-instruct-v1.5"
    path = Path(snapshot_download(model, revision=revision, local_files_only=True))
    tokenizer = AutoTokenizer.from_pretrained(path, local_files_only=True)
    special = json.loads((path / "tokenizer_config.json").read_text(encoding="utf-8"))["additional_special_tokens"]
    system = Path(__file__).with_name("prompt-v1.txt").read_text(encoding="utf-8")
    total = requested = maximum = 0
    with Path(args.output).open("x", encoding="utf-8") as sink:
        for line in Path(args.input).read_text(encoding="utf-8").splitlines():
            row = json.loads(line)
            payload = {"text": row["text"], "slots": [
                {"id": i, "start": slot["start"], "original": slot["original"],
                 "options": [{"id": j, "text": word} for j, word in enumerate(slot["options"])]}
                for i, slot in enumerate(row["slots"])]}
            rendered = tokenizer.apply_chat_template([
                {"role": "system", "content": system},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False, separators=(",", ":"))}],
                tokenize=False, add_generation_prompt=True, additional_special_tokens=special)
            tokens = len(tokenizer.encode(rendered, add_special_tokens=False))
            assert tokens <= 3712, f"Вход слишком длинный: {row['id']} {tokens}"
            maximum = max(maximum, tokens)
            row.update({"rendered_prompt": rendered,
                        "rendered_prompt_sha256": hashlib.sha256(rendered.encode()).hexdigest(),
                        "prompt_tokens": tokens,
                        "prompt_source": {"model": model, "revision": revision,
                                          "chat_template_sha256": hashlib.sha256(tokenizer.chat_template.encode()).hexdigest()}})
            sink.write(json.dumps(row, ensure_ascii=False) + "\n")
            total += 1
            requested += bool(row["slots"])
    print(json.dumps({"rows": total, "with_candidates": requested, "maximum_prompt_tokens": maximum}))


if __name__ == "__main__":
    main()
