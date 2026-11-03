"""Общая оценка полных прогонов и проверка сохранения авторских данных."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path("benchmarks/results/2026-11-03/giga20-gfusion")
DATASETS = {
    "test": ("benchmarks/cases-v1.jsonl", "test"),
    "preservation": ("benchmarks/preservation/cases-v1.jsonl", "test"),
    "holdout": ("benchmarks/gigachat-prompts/holdout-v1.jsonl", "test"),
    "layout": ("benchmarks/sber-large/layout-smoke-v1.jsonl", "dev"),
    "paragraphs": ("benchmarks/paragraphs-v1.jsonl", "dev"),
}
BASELINES = {
    "test": ["gigachat-prompts/text-only-test.jsonl", "sage-v1.1/sage11-test.jsonl", "languagetool/lt68-test.jsonl"],
    "preservation": ["gigachat-prompts/text-only-preservation.jsonl", "sber-large/gigachat-api-preservation.jsonl", "sage-v1.1/sage11-preservation.jsonl", "preservation/lt68-test.jsonl"],
    "holdout": ["gigachat-prompts/text-only-holdout.jsonl", "gigachat-prompts/baseline-holdout.jsonl"],
    "layout": [], "paragraphs": [],
}


def read(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=["gigachat20", "gfusion"], required=True)
    parser.add_argument("--dart", required=True)
    args = parser.parse_args()
    protocol = json.loads(Path("benchmarks/giga20-gfusion/protocol-v1.json").read_text(encoding="utf-8"))
    for path, expected in protocol["datasets_and_prompt"].items():
        actual = hashlib.sha256(Path(path).read_text(encoding="utf-8").encode()).hexdigest()
        if actual != expected:
            raise ValueError(f"Изменён замороженный файл: {path}")
    summary = {}
    for name, (data, split) in DATASETS.items():
        path = ROOT / f"{args.model}-{name}.jsonl"
        records = read(path)
        cases = [row for row in records if row["type"] == "case"]
        expected = {row["id"]: row for row in read(data) if row["split"] == split}
        if records[-1]["type"] != "summary" or len(cases) != len(expected) or {row["id"] for row in cases} != set(expected):
            raise ValueError(f"Неполный или другой прогон: {path}")
        for row in cases:
            if row["text"] != expected[row["id"]]["text"] or row["expected"] != expected[row["id"]]["edits"]:
                raise ValueError(f"Изменены исходник или эталон: {row['id']}")
        sources = [path, *[ROOT.parent / source for source in BASELINES[name]]]
        source_args = ["../../" + source.as_posix() for source in sources]
        comparison = subprocess.run([args.dart, "run", "bin/compare_texts.dart", *source_args], cwd="tools/model_benchmark", capture_output=True, text=True, encoding="utf-8", check=True)
        compared = json.loads(comparison.stdout)
        (ROOT / f"{args.model}-{name}-comparison.json").write_text(json.dumps(compared, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        own = compared["results"][0]
        failures = {row["id"] for row in cases if not row.get("schema_valid") or "error" in row or row.get("done_reason") != "stop"}
        compact = {key: value for key, value in own.items() if key not in ["cases", "categories"]}
        compact["clean_corrections"] = sum(row["exact"] and not row["control"] and row["id"] not in failures for row in own["cases"])
        compact["contract_failures"] = sorted(failures)
        compact["categories"] = own["categories"]
        compact["category_clean_corrections"] = {category: sum(row["exact"] and not row["control"] and row["id"] not in failures for row in own["cases"] if row["category"] == category) for category in own["categories"]}
        if name in ["preservation", "holdout"]:
            retention = ROOT / f"{args.model}-{name}-retention.json"
            if not retention.exists():
                subprocess.run([sys.executable, "-X", "utf8", "benchmarks/preservation/check_retention.py", "--data", data, "--output", str(retention), str(path)], check=True)
            protection = json.loads(retention.read_text(encoding="utf-8"))["results"][0]
            compact["protection"] = {key: value for key, value in protection.items() if key not in ["details", "path"]}
        compact["cold_seconds"] = next(row["seconds"] for row in records if row["type"] == "cold_start")
        if args.model == "gfusion":
            compact["load_seconds"] = records[0]["load_seconds"]
            for key in ["peak_wset_bytes", "cuda_peak_allocated_bytes", "cuda_peak_reserved_bytes"]:
                compact[key] = max(row[key] for row in cases)
        else:
            compact["resident_memory"] = next(row["data"] for row in records if row["type"] == "resident_memory")
        if name == "layout":
            normalize = lambda text: text.strip().rstrip(".!?").casefold()
            compact["recovered_ignoring_case_and_end_punctuation"] = sum(bool(row["expected"]) and normalize(row["output"]) == normalize(row["expected"][0]["replacement"]) for row in cases)
        summary[name] = compact
    (ROOT / f"{args.model}-overview.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({name: {key: row[key] for key in ["count", "matched_corrections", "clean_corrections", "changed_controls", "contract_failures"]} for name, row in summary.items()}, ensure_ascii=False))


if __name__ == "__main__":
    main()
