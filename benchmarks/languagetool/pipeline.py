"""Подготовка промежуточных данных и сборка результата LanguageTool → SAGE."""

import argparse
import json
from pathlib import Path


def read_records(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8-sig").splitlines() if line.strip()]


def write_records(path, records):
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8") as sink:
        for record in records:
            sink.write(json.dumps(record, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "merge"])
    parser.add_argument("--lt", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--sage-stage")
    args = parser.parse_args()
    records = read_records(args.lt)
    metadata = next(row for row in records if row["type"] == "metadata")
    cases = [row for row in records if row["type"] == "case"]
    summary = records[-1]
    if summary.get("completed") is not True or summary.get("count") != len(cases):
        raise ValueError("Прогон LanguageTool не завершён")
    if len({row["id"] for row in cases}) != len(cases):
        raise ValueError("Повторяющиеся идентификаторы LanguageTool")
    if args.action == "prepare":
        write_records(args.output, [
            {"id": row["id"], "split": metadata["split"], "category": row["category"],
             "text": row["output"], "edits": []}
            for row in cases
        ])
        return
    if not args.sage_stage:
        parser.error("Для merge нужен --sage-stage")
    stage = [row for row in read_records(args.sage_stage) if row["type"] == "case"]
    by_id = {row["id"]: row for row in stage}
    if len(stage) != len(cases) or len(by_id) != len(stage) or set(by_id) != {row["id"] for row in cases}:
        raise ValueError("Наборы LanguageTool и SAGE не совпадают")
    results = [{"type": "metadata", "model": "LanguageTool 6.8 → SAGE 95M FP32 CPU",
                "split": metadata["split"], "source_languagetool": args.lt,
                "source_sage_stage": args.sage_stage,
                "timing": "Сумма повторного HTTP-запроса LT и вызова SAGE, без передачи между этапами"}]
    for original in cases:
        corrected = by_id[original["id"]]
        if corrected["text"] != original["output"]:
            raise ValueError("На втором этапе проверен другой текст")
        results.append({
            "type": "case", "id": original["id"], "category": original["category"],
            "text": original["text"], "expected": original["expected"],
            "output": corrected["output"],
            "seconds": original["seconds"] + corrected["seconds"],
            "languagetool_output": original["output"],
        })
    results.append({"type": "summary", "completed": True, "count": len(cases)})
    write_records(args.output, results)


if __name__ == "__main__":
    main()
