"""Поэтапное локальное сравнение промптов с неизменённой Dart-защитой."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "benchmarks/results/2026-11-04/prompt-precision"
DART = r"C:\Users\vostr\code\flutter\bin\dart.bat"
PYTHON = r"E:\korrekta\sage-venv\Scripts\python.exe"
MODEL = "hf.co/ai-sage/GigaChat-20B-A3B-instruct-v1.5-GGUF:Q4_K_M"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def read_rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def save(path, value):
    if path.exists():
        assert read_json(path) == value, f"Результат уже существует и отличается: {path}"
        return
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run(command, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Ошибка команды {command[0]}: {result.stderr[-3000:]} {result.stdout[-1000:]}")
    return result.stdout


def dart(arguments):
    return run([DART, "run", *arguments], ROOT / "tools/model_benchmark")


def verify_frozen():
    protocol = read_json(HERE / "protocol-v1.json")
    for name, expected in protocol["sha256_lf"].items():
        actual = hashlib.sha256((ROOT / name).read_text(encoding="utf-8").encode()).hexdigest()
        assert actual == expected, f"Изменён замороженный вход: {name}"
    return protocol


def completed(path):
    if not path.exists():
        return False
    rows = read_rows(path)
    assert rows[-1]["type"] == "summary", f"Незавершённый файл: {path}; не перезаписывается"
    return True


def evaluate(profile, data, split, name):
    prompt = ROOT / profile["path"]
    rendered = OUT / f"{profile['id']}-{name}-rendered.jsonl"
    if not rendered.exists():
        run([PYTHON, "-X", "utf8", str(ROOT / "benchmarks/giga20-gfusion/render_gigachat20.py"),
             "--data", str(data), "--prompt", str(prompt), "--output", str(rendered)])
    raw = OUT / f"{profile['id']}-{name}-raw.jsonl"
    guarded = OUT / f"{profile['id']}-{name}-guarded.jsonl"
    if not completed(raw):
        print(f"Запросы {profile['id']} / {name}", flush=True)
        log = dart(["bin/benchmark.dart", "--model", MODEL, "--endpoint", "http://127.0.0.1:11435",
                    "--raw", "--response-mode", "text-json", "--data", str(rendered),
                    "--prompt", str(prompt), "--split", split, "--output", str(raw)])
        (OUT / f"{profile['id']}-{name}.log").write_text(log, encoding="utf-8")
    expected = {row["id"]: row for row in read_rows(data) if row["split"] == split}
    cases = [row for row in read_rows(raw) if row["type"] == "case"]
    assert len(cases) == len(expected) and {row["id"] for row in cases} == set(expected)
    for row in cases:
        assert row["text"] == expected[row["id"]]["text"] and row["expected"] == expected[row["id"]]["edits"]
    if not completed(guarded):
        dart(["bin/protect_results.dart", "--input", str(raw), "--output", str(guarded)])
    comparison = json.loads(dart(["bin/compare_texts.dart", str(raw), str(guarded)]))
    save(OUT / f"{profile['id']}-{name}-comparison.json", comparison)
    retention = OUT / f"{profile['id']}-{name}-retention.json"
    if all("protected" in row for row in expected.values()) and not retention.exists():
        run([sys.executable, "-X", "utf8", str(ROOT / "benchmarks/preservation/check_retention.py"),
             "--data", str(data), "--output", str(retention), str(raw), str(guarded)])
    return compact(comparison, cases)


def compact(comparison, cases):
    failures = {row["id"] for row in cases if not row.get("schema_valid") or "error" in row or row.get("done_reason") != "stop"}
    profiles = []
    for result in comparison["results"]:
        summary = {key: result[key] for key in ["count", "gold_corrections", "matched_corrections", "controls", "changed_controls", "atomic_precision", "median_seconds", "p95_seconds"]}
        summary["clean_corrections"] = sum(row["exact"] and not row["control"] and row["id"] not in failures for row in result["cases"])
        summary["contract_failures"] = sorted(failures)
        summary["changed_control_ids"] = [row["id"] for row in result["cases"] if row["changed_control"]]
        profiles.append(summary)
    return {"raw": profiles[0], "guarded": profiles[1]}


def select(protocol, summaries):
    baseline = summaries["baseline"]["guarded"]
    options = [profile for profile in protocol["candidates"]
               if summaries[profile["id"]]["guarded"]["clean_corrections"] >= baseline["clean_corrections"] - 3
               and len(summaries[profile["id"]]["guarded"]["contract_failures"]) <= len(baseline["contract_failures"])]
    order = [profile["id"] for profile in protocol["candidates"]]
    def key(profile):
        row = summaries[profile["id"]]
        return (row["guarded"]["changed_controls"], -row["guarded"]["clean_corrections"],
                row["raw"]["changed_controls"], order.index(profile["id"]))
    selected = min(options, key=key)
    selection = {"rule": protocol["selection_rule"], "dev": summaries, "selected": selected}
    save(OUT / "selection.json", selection)
    print(json.dumps(selection, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["dev", "test", "regression"], required=True)
    args = parser.parse_args()
    protocol = verify_frozen()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.phase == "dev":
        summaries = {profile["id"]: evaluate(profile, HERE / "dev-v1.jsonl", "dev", "dev") for profile in protocol["candidates"]}
        select(protocol, summaries)
    elif args.phase == "test":
        selected = read_json(OUT / "selection.json")["selected"]
        profiles = [protocol["candidates"][0]]
        if selected["id"] != "baseline":
            profiles.append(selected)
        summaries = {profile["id"]: evaluate(profile, HERE / "holdout-v1.jsonl", "test", "holdout") for profile in profiles}
        save(OUT / "holdout-overview.json", summaries)
        print(json.dumps(summaries, ensure_ascii=False), flush=True)
    else:
        selected = read_json(OUT / "selection.json")["selected"]
        summaries = {name: evaluate(selected, ROOT / data, "test", name) for name, data in [
            ("ordinary", "benchmarks/cases-v1.jsonl"), ("preservation", "benchmarks/preservation/cases-v1.jsonl"),
        ]}
        save(OUT / "regression-overview.json", summaries)
        print(json.dumps(summaries, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
