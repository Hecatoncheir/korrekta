"""Локальный исследовательский запуск SAGE; не компонент приложения."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import sys
import time

MODELS = {
    "ai-forever/sage-v1.1.0": (
        "0677d3c457c4088a7146118554fe82c2e8eb86bd",
        "fd500038a683bd85df36c46581e85a5d595cf46a1a69660567b7023f50886421",
    ),
    "ai-forever/sage-fredt5-distilled-95m": (
        "ed51b4a46603931380951a3d8456685c9215864f",
        "e005b48ae460cbf5f82f0f3da8b13d5df7c2c98eb1e02ed8a7d525d3de7a9bfe",
    ),
    "ai-forever/sage-fredt5-large": (
        "5a7a9960c8f0743eec57fa2fc8c034cc1dc8326a",
        "1e394dc23403b62b333bd8635207a558d73ac87398ffa671375b012c48180c2c",
    ),
    "ai-forever/sage-mt5-large": (
        "ab7807052d9728547c97270408cccd9c605af897",
        "a5d1ab037fb4500851275bfcab177442afb63d8a6b348136946c84f8a9844899",
    ),
    "ai-forever/sage-m2m100-1.2B": (
        "1773f13bcbf21d7d945a3ba58473acac3aea6690",
        "9a2730b2f0a303d5883847fb63c427906e53cd0713fc10d642b01a73a18e99d3",
    ),
}
FILES = ["*.json", "*.safetensors", "*.txt", "*.model", "README.md"]
TOKENIZER_MODEL = "ai-forever/FRED-T5-1.7B"
TOKENIZER_REVISION = "fbff67a8b062bb34656fe27794b7874b63f54db8"
TOKENIZER_FILES = ["config.json", "added_tokens.json", "merges.txt", "special_tokens_map.json", "tokenizer_config.json", "vocab.json"]


def file_digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storage", default="E:/korrekta")
    parser.add_argument("--model", choices=MODELS, default="ai-forever/sage-fredt5-distilled-95m")
    parser.add_argument("--beams", type=int, default=1)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--data")
    parser.add_argument("--output")
    parser.add_argument("--split", choices=["dev", "test"], default="dev")
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cuda")
    parser.add_argument("--limit", type=int, default=0)
    options = parser.parse_args()
    model_id = options.model
    revision, expected_weights = MODELS[model_id]
    if options.beams < 1:
        parser.error("--beams должен быть положительным")
    storage = Path(options.storage).resolve()
    for name, folder in {
        "HF_HOME": "cache/huggingface",
        "TORCH_HOME": "cache/torch",
        "TEMP": "tmp",
        "TMP": "tmp",
    }.items():
        path = storage / folder
        path.mkdir(parents=True, exist_ok=True)
        os.environ[name] = str(path)
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["HF_HUB_DISABLE_XET"] = "1"
    os.environ["HF_HUB_DOWNLOAD_TIMEOUT"] = "60"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ["HF_HUB_OFFLINE"] = "0" if options.download else "1"

    from huggingface_hub import snapshot_download

    if options.download:
        path = snapshot_download(
            model_id,
            revision=revision,
            allow_patterns=FILES,
        )
        if file_digest(Path(path) / "model.safetensors") != expected_weights:
            raise ValueError("Не совпала контрольная сумма весов")
        if model_id == "ai-forever/sage-v1.1.0":
            snapshot_download(TOKENIZER_MODEL, revision=TOKENIZER_REVISION, allow_patterns=TOKENIZER_FILES)
        print(json.dumps({"snapshot": path, "revision": revision, "sha256_verified": True}))
        return
    if not options.data or not options.output or options.limit < 0:
        parser.error("Нужны --data, --output и неотрицательный --limit")
    cases = [json.loads(line) for line in Path(options.data).read_text(encoding="utf-8").splitlines() if line.strip()]
    cases = [item for item in cases if item["split"] == options.split]
    if options.limit:
        cases = cases[:options.limit]
    if not cases:
        parser.error("Нет примеров")
    output = Path(options.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        parser.error("Файл результата уже существует")

    import psutil
    import torch
    import transformers
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    torch.set_num_threads(12)
    torch.manual_seed(42)
    if options.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA недоступна")
    started = time.perf_counter()
    path = Path(snapshot_download(model_id, revision=revision, allow_patterns=FILES, local_files_only=True))
    if file_digest(path / "model.safetensors") != expected_weights:
        raise ValueError("Не совпала контрольная сумма весов")
    tokenizer_options = {"src_lang": "ru", "tgt_lang": "ru"} if "m2m100" in model_id else {}
    tokenizer_path = path
    prefix = ""
    if model_id == "ai-forever/sage-v1.1.0":
        tokenizer_path = Path(snapshot_download(
            TOKENIZER_MODEL, revision=TOKENIZER_REVISION,
            allow_patterns=TOKENIZER_FILES, local_files_only=True,
        ))
        prefix = "<LM>"
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_path, local_files_only=True, **tokenizer_options)
    model = AutoModelForSeq2SeqLM.from_pretrained(path, local_files_only=True, dtype=torch.float32)
    model.to(options.device).eval()
    if options.device == "cuda":
        torch.cuda.synchronize()
        torch.cuda.reset_peak_memory_stats()
    load_seconds = time.perf_counter() - started
    metadata = {
        "type": "metadata", "model": model_id, "revision": revision,
        "time": datetime.now(timezone.utc).isoformat(),
        "python": platform.python_version(), "torch": torch.__version__,
        "transformers": transformers.__version__, "cuda": torch.version.cuda,
        "platform": platform.platform(), "device": options.device,
        "gpu": torch.cuda.get_device_name() if options.device == "cuda" else None,
        "parameters": sum(p.numel() for p in model.parameters()),
        "dtype": "float32", "threads": torch.get_num_threads(),
        "seed": 42, "do_sample": False, "num_beams": options.beams,
        "input_prefix": prefix, "input_normalization": False,
        "tokenizer_model": TOKENIZER_MODEL if prefix else model_id,
        "tokenizer_revision": TOKENIZER_REVISION if prefix else revision,
        "tokenizer_files": [{"name": f.name, "bytes": f.stat().st_size,
                             "sha256": file_digest(f)}
                            for f in sorted(tokenizer_path.iterdir()) if f.is_file() and f.name in TOKENIZER_FILES],
        "forced_bos_token_id": tokenizer.get_lang_id("ru") if "m2m100" in model_id else None,
        "max_length": "max(16, ceil(input_tokens * 1.5))", "truncation": False,
        "offline": True, "split": options.split, "load_seconds": load_seconds,
        "data_sha256_lf": hashlib.sha256(Path(options.data).read_text(encoding="utf-8").encode()).hexdigest(),
        "files": [{"name": f.name, "bytes": f.stat().st_size,
                   "sha256": file_digest(f)}
                  for f in sorted(path.iterdir()) if f.is_file()],
    }
    process = psutil.Process()

    def run_case(item, record_type):
        if options.device == "cuda":
            torch.cuda.synchronize()
        start = time.perf_counter()
        inputs = tokenizer(prefix + item["text"], padding="longest", truncation=False, return_tensors="pt").to(options.device)
        max_length = max(16, math.ceil(inputs["input_ids"].shape[1] * 1.5))
        generation = {"forced_bos_token_id": tokenizer.get_lang_id("ru")} if "m2m100" in model_id else {}
        with torch.inference_mode():
            tokens = model.generate(**inputs, max_length=max_length, do_sample=False, num_beams=options.beams, **generation)
        corrected = tokenizer.batch_decode(tokens, skip_special_tokens=True)[0]
        if options.device == "cuda":
            torch.cuda.synchronize()
        seconds = time.perf_counter() - start
        memory = process.memory_info()
        return {
            "type": record_type, "id": item["id"], "category": item["category"],
            "text": item["text"], "expected": item["edits"], "output": corrected,
            "seconds": seconds, "input_tokens": inputs["input_ids"].shape[1],
            "output_tokens": tokens.shape[1], "max_length": max_length,
            "ended_with_eos": tokens[0, -1].item() == model.config.eos_token_id,
            "rss_bytes": memory.rss, "peak_wset_bytes": getattr(memory, "peak_wset", None),
            "cuda_peak_allocated_bytes": torch.cuda.max_memory_allocated() if options.device == "cuda" else 0,
            "cuda_peak_reserved_bytes": torch.cuda.max_memory_reserved() if options.device == "cuda" else 0,
        }

    with output.open("x", encoding="utf-8") as sink:
        def write(record):
            sink.write(json.dumps(record, ensure_ascii=False) + "\n")
            sink.flush()

        write(metadata)
        write(run_case(cases[0], "cold_start"))
        for index, item in enumerate(cases, 1):
            record = run_case(item, "case")
            write(record)
            print(f"{index}/{len(cases)} {item['id']} {record['seconds']:.3f} с", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
