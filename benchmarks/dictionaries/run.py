"""Запуск и общая оценка словарных проверок без моделей и сети."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "benchmarks/results/2026-11-04/dictionaries"
DART = r"C:\Users\vostr\code\flutter\bin\dart.bat"


def read(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def call(command, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, text=True, encoding="utf-8", capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-2500:] + result.stdout[-1000:])
    return result.stdout


def save(path, data):
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if path.exists():
        assert path.read_text(encoding="utf-8") == text, path
    else:
        path.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    protocol = json.loads((HERE / "protocol-v1.json").read_text(encoding="utf-8"))
    for name, expected in protocol["sha256_lf"].items():
        assert hashlib.sha256((ROOT / name).read_text(encoding="utf-8").encode()).hexdigest() == expected, name
    OUT.mkdir(parents=True, exist_ok=True)
    if not args.check:
        manifest = json.loads(Path("E:/korrekta/dictionaries-v1/manifest.json").read_text(encoding="utf-8"))
        assert manifest == json.loads((HERE / "data-manifest.json").read_text(encoding="utf-8"))
        call([DART, "run", "bin/dictionary_benchmark.dart", "--protocol",
              str(HERE / "protocol-v1.json"), "--output", str(OUT)], ROOT / "tools/model_benchmark")
    overview = {}
    for run in protocol["runs"]:
        expected = {row["id"]: row for row in read(ROOT / run["data"]) if row["split"] == run["split"]}
        files = [OUT / f"{run['id']}-{profile['id']}.jsonl" for profile in protocol["profiles"]]
        for file in files:
            rows = read(file)
            cases = [row for row in rows if row["type"] == "case"]
            assert rows[-1]["type"] == "summary" and len(cases) == run["count"] == len(expected), file
            assert {row["id"] for row in cases} == set(expected), file
            for row in cases:
                assert row["text"] == expected[row["id"]]["text"] and row["expected"] == expected[row["id"]]["edits"], file
        compared = OUT / f"{run['id']}-comparison.json"
        if not args.check:
            result = json.loads(call([DART, "run", "bin/compare_texts.dart", *map(str, files)], ROOT / "tools/model_benchmark"))
            save(compared, result)
        result = json.loads(compared.read_text(encoding="utf-8"))
        summaries = {}
        for profile, item in zip(protocol["profiles"], result["results"], strict=True):
            entry = {key: item[key] for key in ["count", "gold_corrections", "matched_corrections", "controls", "changed_controls", "atomic_precision", "median_seconds", "p95_seconds"]}
            entry["clean_corrections"] = sum(row["exact"] and not row["control"] for row in item["cases"])
            summaries[profile["id"]] = entry
        if all("protected" in row for row in expected.values()):
            retention = OUT / f"{run['id']}-retention.json"
            if not args.check and not retention.exists():
                call([sys.executable, "-X", "utf8", str(ROOT / "benchmarks/preservation/check_retention.py"),
                      "--data", str(ROOT / run["data"]), "--output", str(retention), *map(str, files)])
            retained = json.loads(retention.read_text(encoding="utf-8"))["results"]
            for profile, item in zip(protocol["profiles"], retained, strict=True):
                summaries[profile["id"]]["protected_failures"] = item["retention_failures"]
        overview[run["id"]] = summaries
        print(run["id"], json.dumps({p: [v["clean_corrections"], v["changed_controls"]] for p, v in summaries.items()}, ensure_ascii=False), flush=True)
    save(OUT / "overview.json", overview)


if __name__ == "__main__":
    main()
