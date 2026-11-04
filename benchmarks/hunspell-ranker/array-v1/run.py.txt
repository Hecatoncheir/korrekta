"""Сбор вариантов, локальный отбор GigaChat и независимая оценка выбора."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / "benchmarks/results/2026-11-04/hunspell-ranker"
DART = r"C:\Users\vostr\code\flutter\bin\dart.bat"
PYTHON = r"E:\korrekta\sage-venv\Scripts\python.exe"


def read(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def digest(path):
    return hashlib.sha256(path.read_text(encoding="utf-8").encode()).hexdigest()


def save(path, value):
    text = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if path.exists():
        assert path.read_text(encoding="utf-8") == text, path
    else:
        path.write_text(text, encoding="utf-8")


def call(command, cwd=ROOT, capture=False):
    result = subprocess.run(command, cwd=cwd, capture_output=capture, text=True, encoding="utf-8", check=True)
    return result.stdout


def dart(arguments, capture=False):
    return call([DART, "run", *arguments], ROOT / "tools/model_benchmark", capture)


def verify():
    protocol = json.loads((HERE / "protocol-v1.json").read_text(encoding="utf-8"))
    for name, sha in protocol["sha256_lf"].items():
        assert digest(ROOT / name) == sha, name
    return protocol


def prepare(protocol):
    installed = json.loads(Path("E:/korrekta/dictionaries-v1/manifest.json").read_text(encoding="utf-8"))
    assert installed == json.loads((ROOT / "benchmarks/dictionaries/data-manifest.json").read_text(encoding="utf-8"))
    plain = OUT / "candidates.jsonl"
    rendered = OUT / "rendered.jsonl"
    if not plain.exists():
        dart(["bin/prepare_hunspell_choices.dart", "--protocol", str(HERE / "protocol-v1.json"), "--output", str(plain)])
    rows = read(plain)
    assert len(rows) == 2 * sum(run["count"] for run in protocol["runs"])
    if not rendered.exists():
        call([PYTHON, "-X", "utf8", str(HERE / "render.py"), "--input", str(plain), "--output", str(rendered)])
    loaded = read(rendered)
    assert len(rows) == len(loaded)
    save(OUT / "preparation.json", {"rows": len(rows),
        "candidate_rows": sum(bool(row["slots"]) for row in rows),
        "max_slots": max(len(row["slots"]) for row in rows),
        "maximum_prompt_tokens": max(row["prompt_tokens"] for row in loaded),
        "sha256_lf": {f.name: digest(f) for f in [plain, rendered]}})


def target_reachable(row):
    text = row["text"]
    target = text
    edits = [(text.index(e["original"]), e) for e in row["expected"]]
    assert all(text.count(e["original"]) == 1 for _, e in edits)
    for start, edit in sorted(edits, reverse=True):
        target = target[:start] + edit["replacement"] + target[start + len(edit["original"]):]
    def utf16_position(offset):
        return len(text.encode("utf-16-le")[:offset * 2].decode("utf-16-le"))
    pieces = []
    end = 0
    for slot in row["slots"]:
        start = utf16_position(slot["start"])
        assert text[start:start + len(slot["original"])] == slot["original"]
        pieces += [re.escape(text[end:start]), "(?:" + "|".join(re.escape(o) for o in slot["options"]) + ")"]
        end = start + len(slot["original"])
    pieces.append(re.escape(text[end:]))
    return re.fullmatch("".join(pieces), target) is not None


def evaluate(protocol, check):
    rows = read(OUT / "responses.jsonl")
    assert rows[-1]["type"] == "summary" and rows[-1]["completed"]
    cases = [row for row in rows if row["type"] == "case"]
    inputs = read(OUT / "rendered.jsonl")
    assert len(cases) == len(inputs) == rows[-1]["count"]
    for row, source in zip(cases, inputs, strict=True):
        for key in ["run", "mode", "id", "text", "expected", "slots", "rendered_prompt_sha256"]:
            assert row[key] == source[key], key
    overview = {}
    for run in protocol["runs"]:
        for mode in ["spelling", "layout"]:
            selected = [row for row in cases if row["run"] == run["id"] and row["mode"] == mode]
            assert len(selected) == run["count"]
            sources = {row["id"]: row for row in read(ROOT / run["data"]) if row["split"] == run["split"]}
            assert {row["id"] for row in selected} == set(sources)
            assert all(row["text"] == sources[row["id"]]["text"] and row["expected"] == sources[row["id"]]["edits"] for row in selected)
            files = []
            for profile in ["first", "frequency", "giga"]:
                path = OUT / f"{run['id']}-{mode}-{profile}.jsonl"
                files.append(path)
                if check:
                    loaded = read(path)
                    actual = [row for row in loaded if row["type"] == "case"]
                    assert loaded[-1]["type"] == "summary" and len(actual) == run["count"]
                    for row, stored in zip(selected, actual, strict=True):
                        assert row["id"] == stored["id"] and row["text"] == stored["text"] and row["expected"] == stored["expected"]
                        assert stored["output"] == (row["output"] if profile == "giga" else row[f"{profile}_output"])
                    continue
                if path.exists():
                    continue
                with path.open("x", encoding="utf-8") as sink:
                    sink.write(json.dumps({"type": "metadata", "profile": profile, "run": run, "mode": mode}) + "\n")
                    for row in selected:
                        output = row["output"] if profile == "giga" else row[f"{profile}_output"]
                        value = {"type": "case", "id": row["id"], "category": row["category"],
                            "text": row["text"], "expected": row["expected"], "output": output,
                            "seconds": row["seconds"] if profile == "giga" else row["hunspell_seconds"]}
                        if profile == "giga" and "error" in row:
                            value["error"] = row["error"]
                        sink.write(json.dumps(value, ensure_ascii=False) + "\n")
                    sink.write(json.dumps({"type": "summary", "count": len(selected), "completed": True}) + "\n")
            comparison = OUT / f"{run['id']}-{mode}-comparison.json"
            if not check:
                save(comparison, json.loads(dart(["bin/compare_texts.dart", *map(str, files)], True)))
            summaries = {}
            for profile, result in zip(["first", "frequency", "giga"], json.loads(comparison.read_text(encoding="utf-8"))["results"], strict=True):
                failures = {row["id"] for row in selected if "error" in row} if profile == "giga" else set()
                summaries[profile] = {key: result[key] for key in ["count", "matched_corrections", "gold_corrections", "controls", "changed_controls", "atomic_precision", "median_seconds", "p95_seconds"]}
                summaries[profile]["clean_corrections"] = sum(case["exact"] and not case["control"] and case["id"] not in failures for case in result["cases"])
                summaries[profile]["contract_failures"] = sorted(failures)
            summaries["candidate_error_ceiling"] = sum(bool(row["expected"]) and target_reachable(row) for row in selected)
            summaries["requested"] = sum(bool(row["slots"]) for row in selected)
            summaries["statuses"] = dict(Counter(row["status"] for row in selected))
            if all("protected" in row for row in sources.values()):
                retention = OUT / f"{run['id']}-{mode}-retention.json"
                if not check and not retention.exists():
                    call([sys.executable, "-X", "utf8", str(ROOT / "benchmarks/preservation/check_retention.py"),
                          "--data", str(ROOT / run["data"]), "--output", str(retention), *map(str, files)])
                for profile, kept in zip(["first", "frequency", "giga"], json.loads(retention.read_text(encoding="utf-8"))["results"], strict=True):
                    summaries[profile]["protected_failures"] = kept["retention_failures"]
            overview[f"{run['id']}-{mode}"] = summaries
            print(run["id"], mode, {p: [summaries[p]["clean_corrections"], summaries[p]["changed_controls"]] for p in ["first", "frequency", "giga"]}, flush=True)
    save(OUT / "overview.json", overview)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["prepare", "run", "evaluate", "check"], required=True)
    args = parser.parse_args()
    protocol = verify()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.phase == "prepare":
        prepare(protocol)
        return
    for name, sha in json.loads((OUT / "preparation.json").read_text(encoding="utf-8"))["sha256_lf"].items():
        assert digest(OUT / name) == sha, name
    if args.phase == "run":
        dart(["bin/rank_hunspell_choices.dart", "--input", str(OUT / "rendered.jsonl"), "--output", str(OUT / "responses.jsonl")])
    else:
        evaluate(protocol, args.phase == "check")


if __name__ == "__main__":
    main()
