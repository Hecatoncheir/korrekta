"""Проверка сохранения заданных фрагментов в сырых результатах движков."""

import argparse
from collections import Counter
import json
from pathlib import Path


def read(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("results", nargs="+")
    args = parser.parse_args()
    cases = {row["id"]: row for row in read(args.data)}
    summaries = []
    for path in args.results:
        rows = [row for row in read(path) if row["type"] == "case"]
        if len(rows) != len(cases) or {row["id"] for row in rows} != set(cases):
            raise ValueError(f"Неполный или другой набор: {path}")
        details = []
        categories = Counter()
        notices_on_controls = 0
        changed_controls = 0
        for row in rows:
            case = cases[row["id"]]
            if row["text"] != case["text"] or row["expected"] != case["edits"]:
                raise ValueError(f"Другой вход или эталон: {row['id']}")
            if not case["edits"]:
                changed_controls += row["output"] != case["text"]
                notices_on_controls += row.get("notice_count", 0) > 0
            changes = [
                {"fragment": part, "expected_count": case["text"].count(part),
                 "output_count": row["output"].count(part)}
                for part in case["protected"]
                if case["text"].count(part) != row["output"].count(part)
            ]
            if changes:
                categories[case["category"]] += 1
                details.append({"id": row["id"], "category": case["category"],
                                "control": not case["edits"], "changes": changes})
        summaries.append({
            "path": path, "count": len(rows), "retention_failures": len(details),
            "retention_failures_on_controls": sum(row["control"] for row in details),
            "changed_controls": changed_controls,
            "notices_on_controls": notices_on_controls if "notice_count" in rows[0] else None,
            "failures_by_category": dict(categories), "details": details,
        })
    with Path(args.output).open("x", encoding="utf-8") as target:
        json.dump({"method": "Число дословных вхождений protected без нормализации",
                   "results": summaries}, target, ensure_ascii=False, indent=2)
        target.write("\n")


if __name__ == "__main__":
    main()
