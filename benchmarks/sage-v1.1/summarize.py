"""Проверка полноты прогонов и компактная сводка готовых оценок."""

import hashlib
import json
from pathlib import Path


ROOT = Path("benchmarks/results/2026-11-03/sage-v1.1")
DATASETS = {
    "dev": ("benchmarks/cases-v1.jsonl", "dev"),
    "test": ("benchmarks/cases-v1.jsonl", "test"),
    "preservation": ("benchmarks/preservation/cases-v1.jsonl", "test"),
    "holdout": ("benchmarks/gigachat-prompts/holdout-v1.jsonl", "test"),
    "layout": ("benchmarks/sber-large/layout-smoke-v1.jsonl", "dev"),
    "paragraphs": ("benchmarks/paragraphs-v1.jsonl", "dev"),
}


def read(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def compact_comparison(path):
    rows = json.loads(path.read_text(encoding="utf-8-sig"))["results"]
    return [{**{key: value for key, value in row.items() if key not in ["cases", "categories"]},
             "clean_corrections": sum(case["exact"] and not case["control"] for case in row["cases"]),
             "categories": row["categories"]} for row in rows]


def main():
    protocol = json.loads(Path("benchmarks/sage-v1.1/protocol-v1.json").read_text(encoding="utf-8"))
    for dataset in protocol["datasets"]:
        actual = hashlib.sha256(Path(dataset["path"]).read_text(encoding="utf-8").encode()).hexdigest()
        if actual != dataset["sha256_lf"]:
            raise ValueError(f"Набор изменён: {dataset['path']}")
    runs = {}
    for name, (data, split) in DATASETS.items():
        expected = {row["id"]: row for row in read(data) if row["split"] == split}
        rows = read(ROOT / f"sage11-{name}.jsonl")
        cases = [row for row in rows if row["type"] == "case"]
        if len(cases) != len(expected) or {row["id"] for row in cases} != set(expected):
            raise ValueError(f"Неполный или другой набор: {name}")
        metadata = [row for row in rows if row["type"] == "metadata"]
        cold = [row for row in rows if row["type"] == "cold_start"]
        if len(metadata) != 1 or len(cold) != 1:
            raise ValueError(f"Неверная структура результата: {name}")
        meta = metadata[0]
        if meta["revision"] != protocol["revision"] or meta["input_prefix"] != protocol["prefix"]:
            raise ValueError(f"Другой режим модели: {name}")
        for row in cases:
            case = expected[row["id"]]
            if row["text"] != case["text"] or row["expected"] != case["edits"]:
                raise ValueError(f"Другой вход или эталон: {row['id']}")
        runs[name] = {
            "count": len(cases), "parameters": meta["parameters"],
            "load_seconds": meta["load_seconds"], "cold_seconds": cold[0]["seconds"],
            "without_eos": [row["id"] for row in cases if not row["ended_with_eos"]],
            "max_rss_bytes": max(row["rss_bytes"] for row in cases),
            "peak_wset_bytes": max(row["peak_wset_bytes"] for row in cases),
            "cuda_peak_allocated_bytes": max(row["cuda_peak_allocated_bytes"] for row in cases),
            "cuda_peak_reserved_bytes": max(row["cuda_peak_reserved_bytes"] for row in cases),
        }
    result = {"runs": runs, "comparisons": {name: compact_comparison(ROOT / f"comparison-{name}.json") for name in DATASETS}}
    for name in ["preservation", "holdout"]:
        retention = json.loads((ROOT / f"retention-{name}.json").read_text(encoding="utf-8"))
        result[f"retention_{name}"] = [{key: value for key, value in row.items() if key != "details"} for row in retention["results"]]
    layout = [row for row in read(ROOT / "sage11-layout.jsonl") if row["type"] == "case"]
    normalize = lambda text: text.strip().rstrip(".!?").casefold()
    result["layout"] = {
        "errors": sum(bool(row["expected"]) for row in layout),
        "recovered_ignoring_case_and_end_punctuation": sum(bool(row["expected"]) and normalize(row["output"]) == normalize(row["expected"][0]["replacement"]) for row in layout),
    }
    (ROOT / "overview.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"counts": {name: row["count"] for name, row in runs.items()}, "without_eos": {name: row["without_eos"] for name, row in runs.items()}}, ensure_ascii=False))


if __name__ == "__main__":
    main()
