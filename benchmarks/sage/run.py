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

MODEL = "ai-forever/sage-fredt5-distilled-95m"
REVISION = "ed51b4a46603931380951a3d8456685c9215864f"
FILES = ["*.json", "*.safetensors", "*.txt", "README.md"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storage", default="E:/korrekta")
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--data")
    parser.add_argument("--output")
    parser.add_argument("--split", choices=["dev", "test"], default="dev")
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cuda")
    parser.add_argument("--limit", type=int, default=0)
    options = parser.parse_args()
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
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ["HF_HUB_OFFLINE"] = "0" if options.download else "1"

    from huggingface_hub import snapshot_download

    if options.download:
        path = snapshot_download(
            MODEL,
            revision=REVISION,
            allow_patterns=FILES,
        )
        print(json.dumps({"snapshot": path, "revision": REVISION}))
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
    path = Path(snapshot_download(MODEL, revision=REVISION, allow_patterns=FILES, local_files_only=True))
    tokenizer = AutoTokenizer.from_pretrained(path, local_files_only=True)
    model = AutoModelForSeq2SeqLM.from_pretrained(path, local_files_only=True, dtype=torch.float32)
    model.to(options.device).eval()
    if options.device == "cuda":
        torch.cuda.synchronize()
        torch.cuda.reset_peak_memory_stats()
    load_seconds = time.perf_counter() - started
    metadata = {
        "type": "metadata", "model": MODEL, "revision": REVISION,
        "time": datetime.now(timezone.utc).isoformat(),
        "python": platform.python_version(), "torch": torch.__version__,
        "transformers": transformers.__version__, "cuda": torch.version.cuda,
        "platform": platform.platform(), "device": options.device,
        "gpu": torch.cuda.get_device_name() if options.device == "cuda" else None,
        "parameters": sum(p.numel() for p in model.parameters()),
        "dtype": "float32", "threads": torch.get_num_threads(),
        "seed": 42, "do_sample": False, "num_beams": 1,
        "max_length": "max(16, ceil(input_tokens * 1.5))", "truncation": False,
        "offline": True, "split": options.split, "load_seconds": load_seconds,
        "data_sha256_lf": hashlib.sha256(Path(options.data).read_text(encoding="utf-8").encode()).hexdigest(),
        "files": [{"name": f.name, "bytes": f.stat().st_size,
                   "sha256": hashlib.file_digest(f.open("rb"), "sha256").hexdigest()}
                  for f in sorted(path.iterdir()) if f.is_file()],
    }
    process = psutil.Process()

    def run_case(item, record_type):
        if options.device == "cuda":
            torch.cuda.synchronize()
        start = time.perf_counter()
        inputs = tokenizer(item["text"], padding="longest", truncation=False, return_tensors="pt").to(options.device)
        max_length = max(16, math.ceil(inputs["input_ids"].shape[1] * 1.5))
        with torch.inference_mode():
            tokens = model.generate(**inputs, max_length=max_length, do_sample=False, num_beams=1)
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
