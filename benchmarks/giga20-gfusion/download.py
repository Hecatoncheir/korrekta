"""Загрузка закреплённых весов на E: с проверкой размера и SHA-256."""

from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen

ROOT = Path("E:/korrekta").resolve()
OLLAMA_ROOT = Path("E:/ollama/models").resolve()
CHUNK = 64 * 1024 * 1024


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fetch_range(url, target, size, start):
    end = min(size - 1, start + CHUNK - 1)
    for attempt in range(3):
        try:
            request = Request(url + f"?download=true&chunk={start}", headers={"Range": f"bytes={start}-{end}"})
            with urlopen(request, timeout=60) as source, target.open("r+b") as sink:
                if source.status != 206 or source.headers.get("Content-Range") != f"bytes {start}-{end}/{size}":
                    raise ValueError("Неверный диапазон ответа")
                sink.seek(start)
                remaining = end - start + 1
                while remaining:
                    data = source.read(min(1024 * 1024, remaining))
                    if not data:
                        raise IOError("Загрузка прервана")
                    sink.write(data)
                    remaining -= len(data)
            return end - start + 1
        except Exception:
            if attempt == 2:
                raise


def download(model, weight):
    name, sha, size = weight["name"], weight["sha256"], weight["bytes"]
    if name.endswith(".gguf"):
        blob = OLLAMA_ROOT / "blobs" / f"sha256-{sha}"
    else:
        blob = ROOT / "cache/huggingface/hub" / ("models--" + model["repo"].replace("/", "--")) / "blobs" / sha
    target = ROOT / "downloads" / (name + ".part")
    if not target.resolve().is_relative_to(ROOT) or not any(blob.resolve().is_relative_to(base) for base in [ROOT, OLLAMA_ROOT]):
        raise ValueError("Целевые пути должны находиться в каталогах исследования на E:")
    if blob.exists():
        if blob.stat().st_size != size or digest(blob) != sha:
            raise ValueError(f"Существующий файл не совпал с официальной суммой: {name}")
        print(f"Уже проверен: {name}", flush=True)
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    progress = target.with_suffix(".progress.json")
    done = set()
    if target.exists():
        if target.stat().st_size != size:
            raise ValueError(f"Неожиданный размер временного файла: {target}")
        if progress.exists():
            saved = json.loads(progress.read_text(encoding="utf-8"))
            if saved["sha256"] != sha:
                raise ValueError("Временный файл относится к другим весам")
            done = set(saved["completed"])
    else:
        with target.open("xb") as sink:
            sink.truncate(size)
    started = time.monotonic()
    completed = sum(min(CHUNK, size - start) for start in done)
    previous = -1
    url = f'https://huggingface.co/{model["repo"]}/resolve/{model["revision"]}/{name}'
    with ThreadPoolExecutor(max_workers=4) as executor:
        jobs = {executor.submit(fetch_range, url, target, size, start): start for start in range(0, size, CHUNK) if start not in done}
        for job in as_completed(jobs):
            completed += job.result()
            done.add(jobs[job])
            progress.write_text(json.dumps({"sha256": sha, "completed": sorted(done)}), encoding="utf-8")
            percent = completed * 100 // size
            if percent // 10 != previous // 10:
                print(f"{name}: {percent}% за {time.monotonic() - started:.1f} с", flush=True)
                previous = percent
    if digest(target) != sha:
        raise ValueError(f"Не совпала контрольная сумма: {name}")
    blob.parent.mkdir(parents=True, exist_ok=True)
    target.rename(blob)
    progress.unlink(missing_ok=True)
    print(f"SHA-256 подтверждён: {blob}", flush=True)


def main():
    protocol = json.loads(Path("benchmarks/giga20-gfusion/protocol-v1.json").read_text(encoding="utf-8"))
    for model in protocol["models"]:
        for weight in model["weights"]:
            download(model, weight)


if __name__ == "__main__":
    main()
