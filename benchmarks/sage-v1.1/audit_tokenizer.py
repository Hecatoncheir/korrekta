"""Проверка дословного восстановления входа без генерации моделью."""

import argparse
import json
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        parser.error("Файл результата уже существует")
    os.environ["HF_HOME"] = "E:/korrekta/cache/huggingface"
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer

    protocol = json.loads(Path("benchmarks/sage-v1.1/protocol-v1.json").read_text(encoding="utf-8"))
    tokenizer_path = snapshot_download(
        protocol["tokenizer_model"], revision=protocol["tokenizer_revision"],
        allow_patterns=["config.json", "added_tokens.json", "merges.txt", "special_tokens_map.json", "tokenizer_config.json", "vocab.json"],
        local_files_only=True,
    )
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_path, local_files_only=True)
    datasets = []
    for dataset in protocol["datasets"]:
        rows = [json.loads(line) for line in Path(dataset["path"]).read_text(encoding="utf-8").splitlines() if line.strip()]
        changes = []
        for row in rows:
            encoded_text = protocol["prefix"] + row["text"]
            tokens = tokenizer(encoded_text)["input_ids"]
            decoded = tokenizer.batch_decode([tokens], skip_special_tokens=True)[0]
            if decoded != encoded_text:
                changes.append({"id": row["id"], "text": encoded_text, "decoded": decoded})
        datasets.append({"path": dataset["path"], "count": len(rows), "changed": len(changes), "details": changes})
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as sink:
        json.dump({"method": "encode <LM> + text; batch_decode(skip_special_tokens=True), без модели и нормализации", "datasets": datasets}, sink, ensure_ascii=False, indent=2)
        sink.write("\n")
    print(json.dumps([{key: value for key, value in row.items() if key != "details"} for row in datasets], ensure_ascii=False))


if __name__ == "__main__":
    main()
