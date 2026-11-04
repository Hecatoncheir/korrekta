"""Вторая итерация только по dev, до первого запуска нового holdout."""

import argparse
import hashlib
import json

from run import HERE, OUT, ROOT, evaluate, read_json, save, verify_frozen


def verify_round2():
    verify_frozen()
    protocol = read_json(HERE / "protocol-v2.json")
    for name, expected in protocol["sha256_lf"].items():
        assert hashlib.sha256((ROOT / name).read_text(encoding="utf-8").encode()).hexdigest() == expected, name
    return protocol


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["dev", "test", "regression"], required=True)
    args = parser.parse_args()
    protocol = verify_round2()
    if args.phase == "dev":
        previous = read_json(OUT / "selection.json")
        summaries = {**previous["dev"]}
        profile = protocol["candidates"][-1]
        summaries[profile["id"]] = evaluate(profile, HERE / "dev-v1.jsonl", "dev", "dev")
        baseline = summaries["baseline"]["guarded"]
        eligible = [p for p in protocol["candidates"] if summaries[p["id"]]["guarded"]["clean_corrections"] >= baseline["clean_corrections"] - 3
                    and len(summaries[p["id"]]["guarded"]["contract_failures"]) <= len(baseline["contract_failures"])]
        order = [p["id"] for p in protocol["candidates"]]
        def key(p):
            row = summaries[p["id"]]
            return (row["guarded"]["changed_controls"], -row["guarded"]["clean_corrections"], row["raw"]["changed_controls"], order.index(p["id"]))
        selected = min(eligible, key=key)
        selection = {"rule": previous["rule"], "dev": summaries, "selected": selected,
                     "round": 2, "note": protocol["reason"]}
        save(OUT / "selection-round2.json", selection)
        print(json.dumps(selection, ensure_ascii=False), flush=True)
        return
    selected = read_json(OUT / "selection-round2.json")["selected"]
    if args.phase == "test":
        profiles = [protocol["candidates"][0]] + ([] if selected["id"] == "baseline" else [selected])
        summaries = {p["id"]: evaluate(p, HERE / "holdout-v1.jsonl", "test", "holdout") for p in profiles}
        save(OUT / "holdout-overview.json", summaries)
    else:
        summaries = {name: evaluate(selected, ROOT / data, "test", name) for name, data in [
            ("ordinary", "benchmarks/cases-v1.jsonl"), ("preservation", "benchmarks/preservation/cases-v1.jsonl"),
        ]}
        save(OUT / "regression-overview.json", summaries)
    print(json.dumps(summaries, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
