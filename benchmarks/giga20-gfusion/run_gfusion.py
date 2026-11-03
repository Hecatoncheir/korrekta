"""Исследовательская проверка GFusion NF4; не компонент приложения."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import time

ROOT = Path("benchmarks/results/2026-11-03/giga20-gfusion")
MODEL_PATH = Path("E:/korrekta/gfusion/bf16-96199b4")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["smoke", "dev", "test"], required=True)
    args = parser.parse_args()
    for name, value in {"HF_HOME": "E:/korrekta/cache/huggingface", "HF_HUB_OFFLINE": "1", "TOKENIZERS_PARALLELISM": "false", "TEMP": "E:/korrekta/tmp", "TMP": "E:/korrekta/tmp"}.items():
        os.environ[name] = value
    import psutil
    import torch
    import transformers
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

    torch.set_num_threads(12)
    torch.manual_seed(42)
    protocol = json.loads(Path("benchmarks/giga20-gfusion/protocol-v1.json").read_text(encoding="utf-8"))
    candidates = protocol["prompt_selection"]["candidates"]
    if args.phase == "test":
        chosen = json.loads((ROOT / "gfusion-selection.json").read_text(encoding="utf-8"))["selected"]
        candidates = [item for item in candidates if item["id"] == chosen["id"]]
    if args.phase == "smoke":
        candidates = [candidates[1]]
    jobs = []
    for candidate in candidates:
        datasets = [("dev", "benchmarks/cases-v1.jsonl", "dev")]
        if args.phase == "test":
            datasets = [("test", "benchmarks/cases-v1.jsonl", "test"), ("preservation", "benchmarks/preservation/cases-v1.jsonl", "test"), ("holdout", "benchmarks/gigachat-prompts/holdout-v1.jsonl", "test"), ("layout", "benchmarks/sber-large/layout-smoke-v1.jsonl", "dev"), ("paragraphs", "benchmarks/paragraphs-v1.jsonl", "dev")]
        for name, data, split in datasets:
            rows = [json.loads(line) for line in Path(data).read_text(encoding="utf-8").splitlines() if line.strip()]
            rows = [row for row in rows if row["split"] == split]
            if args.phase == "smoke":
                rows = rows[:2]
            suffix = f"{candidate['id']}-dev" if args.phase == "dev" else "smoke" if args.phase == "smoke" else name
            path = ROOT / f"gfusion-{suffix}.jsonl"
            if path.exists():
                parser.error(f"Файл результата уже существует: {path}")
            jobs.append((candidate, data, split, rows, path))
    started = time.perf_counter()
    quantization = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=torch.bfloat16)
    model, loading = AutoModelForCausalLM.from_pretrained(MODEL_PATH, trust_remote_code=True, local_files_only=True, dtype=torch.bfloat16, quantization_config=quantization, device_map={"": 0}, output_loading_info=True)
    if any(loading.get(key) for key in ["missing_keys", "unexpected_keys", "mismatched_keys", "error_msgs"]):
        raise ValueError(f"Весам не соответствует архитектура: {loading}")
    model.eval()
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, local_files_only=True)
    torch.cuda.synchronize()
    torch.cuda.reset_peak_memory_stats()
    load_seconds = time.perf_counter() - started
    process = psutil.Process()
    ROOT.mkdir(parents=True, exist_ok=True)
    from prefix_cache import prepare_prefix_cache

    original_forward = model.forward
    prepared = []
    for candidate, data, split, rows, path in jobs:
        prompt = Path(candidate["path"]).read_text(encoding="utf-8")
        for row in rows:
            messages = [{"role": "system", "content": prompt}, {"role": "user", "content": json.dumps({"text": row["text"]}, ensure_ascii=False, separators=(",", ":"))}]
            rendered = tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
            prepared.append(tokenizer(rendered, add_special_tokens=False, return_tensors="pt")["input_ids"][0])
    cache_started = time.perf_counter()
    cached_forward, prefix_info = prepare_prefix_cache(model, prepared)
    prefix_info["prepare_seconds"] = time.perf_counter() - cache_started
    checks = []
    for candidate, data, split, rows, path in jobs[:len(candidates)]:
        prompt = Path(candidate["path"]).read_text(encoding="utf-8")
        messages = [{"role": "system", "content": prompt}, {"role": "user", "content": json.dumps({"text": rows[0]["text"]}, ensure_ascii=False, separators=(",", ":"))}]
        ids = tokenizer.apply_chat_template(messages, add_generation_prompt=True, return_tensors="pt").to("cuda")
        outputs = []
        timings = []
        for forward in [original_forward, cached_forward]:
            model.forward = forward
            torch.cuda.synchronize()
            before = time.perf_counter()
            with torch.inference_mode():
                tokens = model.generate(ids, max_new_tokens=768, block_size=32, denoise_steps=32, gamma=0.70, do_sample=False, temperature=0.0)
            torch.cuda.synchronize()
            timings.append(time.perf_counter() - before)
            outputs.append(tokens.cpu().tolist())
            del tokens
        identical = outputs[0] == outputs[1]
        checks.append({"prompt": candidate["id"], "case": rows[0]["id"], "identical_token_ids": identical, "uncached_seconds": timings[0], "cached_seconds": timings[1], "output_tokens": outputs[0]})
        if not identical:
            raise ValueError("Кеш префикса изменил ответ")
    model.forward = cached_forward
    with (ROOT / f"gfusion-{args.phase}-cache-check.json").open("x", encoding="utf-8") as sink:
        json.dump({"prefix": prefix_info, "checks": checks}, sink, ensure_ascii=False, indent=2)
        sink.write("\n")
    for candidate, data, split, rows, path in jobs:
        prompt = Path(candidate["path"]).read_text(encoding="utf-8")
        metadata = {"type": "metadata", "model": "ai-sage/GFusion-10B-A1.8B", "revision": protocol["models"][1]["revision"], "split": split, "time": datetime.now(timezone.utc).isoformat(), "python": platform.python_version(), "torch": torch.__version__, "transformers": transformers.__version__, "prompt": prompt, "response_mode": candidate["response_mode"], "quantization": quantization.to_dict(), "load_seconds": load_seconds, "prefix_cache": prefix_info, "memory_footprint_bytes": model.get_memory_footprint(), "chat_template_sha256": hashlib.sha256(tokenizer.chat_template.encode()).hexdigest(), "data_sha256_lf": hashlib.sha256(Path(data).read_text(encoding="utf-8").encode()).hexdigest(), "generation": {"max_new_tokens": 768, "block_size": 32, "denoise_steps": 32, "gamma": 0.70, "do_sample": False, "temperature": 0.0, "seed": 42}, "offline": True, "normalization": False, "loading": loading}
        with path.open("x", encoding="utf-8") as sink:
            def write(record):
                sink.write(json.dumps(record, ensure_ascii=False) + "\n")
                sink.flush()

            def run(row, record_type):
                torch.cuda.synchronize()
                before = time.perf_counter()
                messages = [{"role": "system", "content": prompt}, {"role": "user", "content": json.dumps({"text": row["text"]}, ensure_ascii=False, separators=(",", ":"))}]
                rendered = tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
                inputs = tokenizer(rendered, add_special_tokens=False, return_tensors="pt")["input_ids"].to("cuda")
                with torch.inference_mode():
                    tokens = model.generate(inputs, max_new_tokens=768, block_size=32, denoise_steps=32, gamma=0.70, do_sample=False, temperature=0.0)
                content = tokenizer.decode(tokens[0], skip_special_tokens=True, clean_up_tokenization_spaces=False)
                torch.cuda.synchronize()
                elapsed = time.perf_counter() - before
                valid = bool(content)
                output = content if valid else row["text"]
                if candidate["response_mode"] == "text-json":
                    try:
                        decoded = json.loads(content)
                        valid = isinstance(decoded, dict) and set(decoded) == {"text"} and isinstance(decoded["text"], str)
                        output = decoded["text"] if valid else row["text"]
                    except (ValueError, TypeError):
                        valid, output = False, row["text"]
                memory = process.memory_info()
                return {"type": record_type, "id": row["id"], "category": row["category"], "text": row["text"], "expected": row["edits"], "content": content, "output": output, "schema_valid": valid, "done_reason": "stop" if tokens.numel() and tokens[0, -1].item() == 2 else "length", "seconds": elapsed, "input_tokens": inputs.shape[1], "output_tokens": tokens.shape[1], "rendered_prompt_sha256": hashlib.sha256(rendered.encode()).hexdigest(), "rss_bytes": memory.rss, "peak_wset_bytes": getattr(memory, "peak_wset", None), "cuda_peak_allocated_bytes": torch.cuda.max_memory_allocated(), "cuda_peak_reserved_bytes": torch.cuda.max_memory_reserved()}

            write(metadata)
            write(run(rows[0], "cold_start"))
            for index, row in enumerate(rows, 1):
                record = run(row, "case")
                write(record)
                print(f"{path.stem}: {index}/{len(rows)} {row['id']} {record['seconds']:.3f} с", file=sys.stderr, flush=True)
            write({"type": "summary", "count": len(rows)})


if __name__ == "__main__":
    main()
