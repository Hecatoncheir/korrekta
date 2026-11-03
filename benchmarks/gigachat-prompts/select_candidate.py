"""Выбор варианта по замороженному критерию, только на dev."""

import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--comparison", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    protocol = json.loads(Path(__file__).with_name("protocol-v1.json").read_text(encoding="utf-8"))
    candidates = {item["id"]: item for item in protocol["candidates"]}
    rows = []
    for summary in json.loads(Path(args.comparison).read_text(encoding="utf-8-sig"))["results"]:
        source = root / "tools/model_benchmark" / summary["path"]
        records = [json.loads(line) for line in source.read_text(encoding="utf-8").splitlines() if line.strip()]
        metadata = records[0]
        if metadata["split"] != "dev":
            raise ValueError("Выбор по test запрещён")
        cases = {row["id"]: row for row in records if row["type"] == "case"}
        if len(cases) != 40 or records[-1]["type"] != "summary":
            raise ValueError("Неполный dev-прогон")
        failures = {key for key, row in cases.items()
                    if not row.get("schema_valid") or "error" in row or row.get("done_reason") != "stop"}
        clean = sum(row["exact"] and not row["control"] and row["id"] not in failures
                    for row in summary["cases"])
        changed = summary["changed_controls"]
        name = source.name.removesuffix("-dev.jsonl")
        rows.append({"id": name, "path": summary["path"], "clean_corrections": clean,
                     "changed_controls": changed, "contract_failures": len(failures),
                     "utility": clean - 2 * changed - 4 * len(failures)})
    options = [row for row in rows if row["id"] in candidates]
    if len(options) != len(candidates):
        raise ValueError("Проверены не все заранее заданные варианты")
    order = list(candidates)
    chosen = min(options, key=lambda row: (-row["utility"], row["changed_controls"],
                                         -row["clean_corrections"], order.index(row["id"])))
    output = {"rule": protocol["selection"], "dev": rows,
              "selected": {**candidates[chosen["id"]], **chosen}}
    with Path(args.output).open("x", encoding="utf-8") as target:
        json.dump(output, target, ensure_ascii=False, indent=2)
        target.write("\n")
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
