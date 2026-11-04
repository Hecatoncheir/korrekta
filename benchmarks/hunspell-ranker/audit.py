"""Независимая проверка, что модель применила только предложенные варианты."""

from collections import Counter, defaultdict
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "benchmarks/results/2026-11-04/hunspell-ranker"


def read(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def position(text, utf16):
    return len(text.encode("utf-16-le")[:utf16 * 2].decode("utf-16-le"))


def reconstruct(row, choices):
    text = row["text"]
    assert len(choices) == len(row["slots"])
    edits = []
    previous = 0
    for slot, choice in zip(row["slots"], choices, strict=True):
        start = position(text, slot["start"])
        end = start + len(slot["original"])
        assert start >= previous and text[start:end] == slot["original"]
        assert type(choice) is int and 0 <= choice < len(slot["options"])
        edits.append((start, end, slot["options"][choice]))
        previous = end
    output = text
    for start, end, replacement in reversed(edits):
        output = output[:start] + replacement + output[end:]
    return output


def main():
    raw = read(OUT / "responses.jsonl")
    rows = [row for row in raw if row["type"] == "case"]
    groups = defaultdict(list)
    for row in rows:
        if "error" in row:
            assert row["output"] == row["text"]
            continue
        assert reconstruct(row, row["choices"]) == row["output"]
        assert reconstruct(row, [1] * len(row["slots"])) == row["first_output"]
        if row["slots"]:
            parsed = json.loads(row["response"]["response"])
            assert set(parsed) == {f"c{i}" for i in range(len(row["slots"]))}
            assert [parsed[f"c{i}"] for i in range(len(row["slots"]))] == row["choices"]
            groups[row["rendered_prompt_sha256"]].append(row)
    varied = [[{"run": row["run"], "mode": row["mode"], "id": row["id"], "choices": row["choices"]} for row in group]
              for group in groups.values() if len({tuple(row["choices"]) for row in group}) > 1]
    baseline_differences = {}
    for run in sorted({row["run"] for row in rows}):
        for mode in ["spelling", "layout"]:
            for profile in ["first", "frequency"]:
                name = "hunspell" if profile == "first" else "hunspell-frequency"
                path = ROOT / f"benchmarks/results/2026-11-04/dictionaries/{run}-{name}-{mode}.jsonl"
                old = {row["id"]: row["output"] for row in read(path) if row["type"] == "case"}
                different = [row["id"] for row in rows if row["run"] == run and row["mode"] == mode and row[f"{profile}_output"] != old[row["id"]]]
                if different:
                    baseline_differences[f"{run}-{mode}-{profile}"] = different
    times = sorted(row["model_seconds"] for row in rows if row["slots"])
    summary = {"rows": len(rows), "model_requests": len(times),
               "statuses": dict(Counter(row["status"] for row in rows)),
               "contract_failures": sum("error" in row for row in rows),
               "outside_candidate_changes": 0,
               "repeated_input_groups": sum(len(group) > 1 for group in groups.values()),
               "different_choices_for_identical_inputs": varied,
               "differences_from_previous_uncapped_baselines": baseline_differences,
               "model_median_seconds": statistics.median(times),
               "model_p95_seconds": times[(len(times) * 95 + 99) // 100 - 1]}
    target = OUT / "audit.json"
    if target.exists():
        assert json.loads(target.read_text(encoding="utf-8")) == summary
    else:
        target.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
