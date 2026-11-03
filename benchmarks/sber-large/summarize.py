"""Сводка общих метрик Dart и дополнительных проб раскладки."""

import argparse
import json
from pathlib import Path


def read(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def summarize_comparison(path):
    result = []
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    for row in data["results"]:
        result.append({**{key: value for key, value in row.items() if key not in ["cases", "categories"]},
                       "clean_corrections": sum(case["exact"] and not case["control"] for case in row["cases"])})
    return result


def normalize_layout(text):
    return text.strip().rstrip(".!?").casefold()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", default="benchmarks/results/2026-11-03/sber-large")
    args = parser.parse_args()
    root = Path(args.directory)
    layout = []
    for path in sorted(root.glob("*-layout.jsonl")):
        records = read(path)
        cases = [row for row in records if row["type"] == "case"]
        if len(cases) != 12 or len({row["id"] for row in cases}) != 12:
            raise ValueError(f"Неполная проба раскладки: {path}")
        recovered = 0
        exact = 0
        changed_controls = 0
        for row in cases:
            if not row["expected"]:
                changed_controls += row["text"] != row["output"]
                continue
            if len(row["expected"]) != 1 or row["expected"][0]["original"] != row["text"]:
                raise ValueError("Проба раскладки должна содержать один полный эталон")
            target = row["expected"][0]["replacement"]
            recovered += normalize_layout(row["output"]) == normalize_layout(target)
            exact += row["output"] == target
        layout.append({"path": str(path), "layout_cases": 8, "recovered": recovered,
                       "exact": exact, "controls": 4, "changed_controls": changed_controls})
    retention = json.loads((root / "retention.json").read_text(encoding="utf-8-sig"))
    output = {
        "test": summarize_comparison(root / "comparison-test.json"),
        "preservation": summarize_comparison(root / "comparison-preservation.json"),
        "retention": [{key: value for key, value in row.items() if key != "details"}
                      for row in retention["results"]],
        "layout": layout,
    }
    (root / "overview.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
