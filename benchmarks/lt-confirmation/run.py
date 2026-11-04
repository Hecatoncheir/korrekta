"""Повторная проверка реальных ответов GigaChat через локальный LT и Dart."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "benchmarks/results/2026-11-04/lt-confirmation"
DART = r"C:\Users\vostr\code\flutter\bin\dart.bat"
PROFILES = ["giga-dart", "lt-first", "lt-dart", "joint"]


def read(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def call(command, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, capture_output=True, encoding="utf-8", text=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-2000:] + result.stdout[-1000:])
    return result.stdout


def dart(arguments):
    return call([DART, "run", *arguments], ROOT / "tools/model_benchmark")


def save(path, value):
    serialized = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if path.exists():
        assert path.read_text(encoding="utf-8") == serialized, path
    else:
        path.write_text(serialized, encoding="utf-8")


def verify_frozen():
    protocol = json.loads((HERE / "protocol-v1.json").read_text(encoding="utf-8"))
    for name, expected in protocol["sha256_lf"].items():
        assert hashlib.sha256((ROOT / name).read_text(encoding="utf-8").encode()).hexdigest() == expected, name
    return protocol


def validate(source, files, data, split):
    expected = {row["id"]: row for row in read(data) if row["split"] == split}
    for file in [source, *files]:
        rows = read(file)
        cases = [row for row in rows if row["type"] == "case"]
        assert rows[-1]["type"] == "summary" and len(cases) == len(expected), file
        assert {row["id"] for row in cases} == set(expected), file
        for row in cases:
            assert row["text"] == expected[row["id"]]["text"], file
            assert row["expected"] == expected[row["id"]]["edits"], file


def compact(comparison, files):
    results = []
    for summary, file in zip(comparison["results"], files, strict=True):
        cases = [row for row in read(file) if row["type"] == "case"]
        failures = {row["id"] for row in cases if row.get("schema_valid") is False or "error" in row or row.get("done_reason", "stop") != "stop"}
        result = {key: summary[key] for key in ["count", "gold_corrections", "matched_corrections", "controls", "changed_controls", "atomic_precision", "median_seconds", "p95_seconds"]}
        result["path"] = file.relative_to(ROOT).as_posix()
        result["clean_corrections"] = sum(row["exact"] and not row["control"] and row["id"] not in failures for row in summary["cases"])
        result["contract_failures"] = sorted(failures)
        results.append(result)
    return dict(zip(["giga-raw", *PROFILES], results, strict=True))


def evaluate(item):
    source, data = ROOT / item["source"], ROOT / item["data"]
    prefix = OUT / item["id"]
    files = [OUT / f"{item['id']}-{profile}.jsonl" for profile in PROFILES]
    if not any(file.exists() for file in files):
        print(f"Проверка LT: {item['id']}", flush=True)
        dart(["bin/confirm_results.dart", "--input", str(source), "--output-prefix", str(prefix)])
    validate(source, files, data, item["split"])
    comparison = json.loads(dart(["bin/compare_texts.dart", str(source), *map(str, files)]))
    save(OUT / f"{item['id']}-comparison.json", comparison)
    summary = compact(comparison, [source, *files])
    if all("protected" in row for row in read(data)):
        retention = OUT / f"{item['id']}-retention.json"
        if not retention.exists():
            call([sys.executable, "-X", "utf8", str(ROOT / "benchmarks/preservation/check_retention.py"),
                  "--data", str(data), "--output", str(retention), str(source), *map(str, files)])
        records = json.loads(retention.read_text(encoding="utf-8"))["results"]
        for name, record in zip(summary, records, strict=True):
            summary[name]["protected_failures"] = record["retention_failures"]
    print(item["id"], json.dumps({p: [r["clean_corrections"], r["changed_controls"]] for p, r in summary.items()}, ensure_ascii=False), flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    protocol = verify_frozen()
    OUT.mkdir(parents=True, exist_ok=True)
    overview = {}
    for item in protocol["runs"]:
        if args.check:
            files = [OUT / f"{item['id']}-{p}.jsonl" for p in PROFILES]
            validate(ROOT / item["source"], files, ROOT / item["data"], item["split"])
            comparison = json.loads((OUT / f"{item['id']}-comparison.json").read_text(encoding="utf-8"))
            summary = compact(comparison, [ROOT / item["source"], *files])
            retention = OUT / f"{item['id']}-retention.json"
            if retention.exists():
                records = json.loads(retention.read_text(encoding="utf-8"))["results"]
                for name, record in zip(summary, records, strict=True):
                    summary[name]["protected_failures"] = record["retention_failures"]
            overview[item["id"]] = summary
        else:
            overview[item["id"]] = evaluate(item)
    save(OUT / "overview.json", overview)
    print("Проверены все наборы и исходники; подтверждение не использует эталоны.")


if __name__ == "__main__":
    main()
