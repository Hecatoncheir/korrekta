"""Проверка полноты, происхождения ответов и выбора промпта без модели."""

from run import HERE, OUT, ROOT, read_json, read_rows, verify_frozen
from round2 import verify_round2


def verify_result(profile, name, data, split):
    expected = {row["id"]: row for row in read_rows(data) if row["split"] == split}
    raw_rows = read_rows(OUT / f"{profile['id']}-{name}-raw.jsonl")
    guarded_rows = read_rows(OUT / f"{profile['id']}-{name}-guarded.jsonl")
    assert raw_rows[-1]["type"] == guarded_rows[-1]["type"] == "summary"
    assert raw_rows[0]["prompt"].replace("\r\n", "\n") == (ROOT / profile["path"]).read_text(encoding="utf-8")
    assert raw_rows[0]["raw"] and raw_rows[0]["response_mode"] == "text-json"
    assert guarded_rows[0]["personal_names"] == []
    raw = {row["id"]: row for row in raw_rows if row["type"] == "case"}
    guarded = {row["id"]: row for row in guarded_rows if row["type"] == "case"}
    assert set(raw) == set(guarded) == set(expected)
    for key, source in expected.items():
        assert raw[key]["text"] == guarded[key]["text"] == source["text"]
        assert raw[key]["expected"] == guarded[key]["expected"] == source["edits"]
        assert raw[key]["output"] == guarded[key]["unfiltered_output"]
        assert raw[key]["content"] == guarded[key]["content"]
        assert guarded[key]["guard"]["version"] == "text-guard-v1"
    comparison = read_json(OUT / f"{profile['id']}-{name}-comparison.json")
    for result in comparison["results"]:
        assert result["count"] == len(expected) == len(result["cases"])
        assert {row["id"] for row in result["cases"]} == set(expected)


def main():
    verify_frozen()
    protocol = verify_round2()
    selection = read_json(OUT / "selection-round2.json")
    summaries = selection["dev"]
    baseline = summaries["baseline"]["guarded"]
    candidates = protocol["candidates"]
    eligible = [p for p in candidates
                if summaries[p["id"]]["guarded"]["clean_corrections"] >= baseline["clean_corrections"] - 3
                and len(summaries[p["id"]]["guarded"]["contract_failures"]) <= len(baseline["contract_failures"])]
    order = [p["id"] for p in candidates]
    def key(profile):
        row = summaries[profile["id"]]
        return (row["guarded"]["changed_controls"], -row["guarded"]["clean_corrections"],
                row["raw"]["changed_controls"], order.index(profile["id"]))
    assert selection["selected"] == min(eligible, key=key)
    assert selection["rule"] == protocol["selection_rule"]
    for profile in candidates:
        verify_result(profile, "dev", HERE / "dev-v1.jsonl", "dev")
    selected = selection["selected"]
    profiles = [candidates[0]] + ([] if selected["id"] == "baseline" else [selected])
    for profile in profiles:
        verify_result(profile, "holdout", HERE / "holdout-v1.jsonl", "test")
    for name, data in [("ordinary", "benchmarks/cases-v1.jsonl"), ("preservation", "benchmarks/preservation/cases-v1.jsonl")]:
        verify_result(selected, name, ROOT / data, "test")
    print("Проверены замороженные входы, выбор только по dev и происхождение всех результатов.")


if __name__ == "__main__":
    main()
