"""Проверка зафиксированных входов и сводка сохранённых оценок без модели."""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "benchmarks/results/2026-11-04/text-guard"
NAMES = ["text-json-dev", "test", "preservation", "holdout", "layout", "paragraphs", "fresh"]
COUNTS = [40, 160, 120, 80, 12, 3, 40]


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def read_rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def verify_inputs():
    protocol = read_json(ROOT / "benchmarks/text-guard/protocol-v1.json")
    for section in ["hashes_sha256_lf", "replay_sources_sha256_lf"]:
        for name, expected in protocol[section].items():
            value = (ROOT / name).read_text(encoding="utf-8").encode("utf-8")
            if hashlib.sha256(value).hexdigest() != expected:
                raise ValueError(f"Изменён зафиксированный вход: {name}")
    rows = read_rows(ROOT / "benchmarks/text-guard/holdout-v1.jsonl")
    assert len(rows) == len({row["id"] for row in rows}) == 40
    pairs = Counter(row["pair"] for row in rows)
    assert len(pairs) == 20 and set(pairs.values()) == {2}
    assert sum(not row["edits"] for row in rows) == 20
    for row in rows:
        assert row["split"] == "test"
        expected = row["text"]
        for edit in row["edits"]:
            assert expected.count(edit["original"]) == 1
            expected = expected.replace(edit["original"], edit["replacement"], 1)
        for fragment in row["protected"]:
            assert row["text"].count(fragment) == expected.count(fragment) > 0
    previous = set()
    for name in protocol["hashes_sha256_lf"]:
        if name.startswith("benchmarks/") and name.endswith(".jsonl") and "text-guard/" not in name:
            previous.update(row["text"] for row in read_rows(ROOT / name))
    assert not previous.intersection(row["text"] for row in rows)


def result_path(name):
    return ROOT / name.removeprefix("../../")


def compact_result(result, count):
    assert result["count"] == len(result["cases"]) == count
    cases = [row for row in read_rows(result_path(result["path"])) if row["type"] == "case"]
    assert len(cases) == count
    entry = {key: result[key] for key in [
        "count", "gold_corrections", "matched_corrections", "controls", "changed_controls", "atomic_precision",
    ]}
    entry["clean_error_texts"] = sum(case["exact"] and not case["control"] for case in result["cases"])
    entry["path"] = result_path(result["path"]).relative_to(ROOT).as_posix()
    if "guard" in cases[0]:
        times = sorted(row["guard_seconds"] * 1000 for row in cases)
        entry["guard_median_ms"] = statistics.median(times)
        entry["guard_p95_ms"] = times[math.ceil(len(times) * 0.95) - 1]
        entry["statuses"] = dict(Counter(row["guard"]["status"] for row in cases))
        entry["rejection_reasons"] = dict(Counter(
            edit["reason"] for row in cases for edit in row["guard"]["rejected"]
        ))
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    verify_inputs()
    overview = {"guard_version": "text-guard-v1", "metric": "text-effects-v1", "datasets": {}}
    for name, count in zip(NAMES, COUNTS):
        comparison = read_json(OUTPUT / f"comparison-{name}.json")
        assert comparison["metric"] == "text-effects-v1"
        entries = [compact_result(result, count) for result in comparison["results"]]
        if name in ["preservation", "holdout", "fresh"]:
            retention = read_json(OUTPUT / f"retention-{name}.json")["results"]
            for entry, preserved in zip(entries, retention, strict=True):
                assert preserved["count"] == count
                entry["protected_failures"] = preserved["retention_failures"]
        overview["datasets"][name] = entries
    path = OUTPUT / "overview.json"
    if args.check:
        assert read_json(path) == overview, "Сводка не соответствует сохранённым оценкам"
    else:
        path.write_text(json.dumps(overview, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Проверены контрольные суммы, 20 новых пар и семь сравнений; модель не запускалась.")


if __name__ == "__main__":
    main()
