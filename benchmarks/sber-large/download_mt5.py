"""Резервная загрузка официальных весов mT5 диапазонами с проверкой SHA-256."""

from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
from pathlib import Path
import time
from urllib.request import Request, urlopen

REVISION = "ab7807052d9728547c97270408cccd9c605af897"
DIGEST = "a5d1ab037fb4500851275bfcab177442afb63d8a6b348136946c84f8a9844899"
SIZE = 4918393736
URL = f"https://huggingface.co/ai-forever/sage-mt5-large/resolve/{REVISION}/model.safetensors?download=true"
ROOT = Path("E:/korrekta").resolve()
TARGET = ROOT / "downloads/sage-mt5-large.safetensors.part"
BLOB = ROOT / "cache/huggingface/hub/models--ai-forever--sage-mt5-large/blobs" / DIGEST
CHUNK_SIZE = 64 * 1024 * 1024


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def download(start):
    end = min(SIZE - 1, start + CHUNK_SIZE - 1)
    for attempt in range(3):
        try:
            request = Request(URL + f"&chunk={start}", headers={"Range": f"bytes={start}-{end}"})
            with urlopen(request, timeout=60) as source, TARGET.open("r+b") as target:
                if source.status != 206 or source.headers.get("Content-Range") != f"bytes {start}-{end}/{SIZE}":
                    raise ValueError("Неверный диапазон ответа")
                target.seek(start)
                remaining = end - start + 1
                while remaining:
                    data = source.read(min(1024 * 1024, remaining))
                    if not data:
                        raise IOError("Загрузка прервана")
                    target.write(data)
                    remaining -= len(data)
            return end - start + 1
        except Exception:
            if attempt == 2:
                raise


def main():
    if BLOB.exists():
        if digest(BLOB) != DIGEST:
            raise ValueError("Существующий файл не совпадает с официальной суммой")
        print("Проверенные веса уже находятся в кеше")
        return
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with TARGET.open("wb") as target:
        target.truncate(SIZE)
    started = time.monotonic()
    completed = 0
    previous = -1
    with ThreadPoolExecutor(max_workers=4) as executor:
        jobs = [executor.submit(download, start) for start in range(0, SIZE, CHUNK_SIZE)]
        for job in as_completed(jobs):
            completed += job.result()
            percent = completed * 100 // SIZE
            if percent // 10 != previous // 10:
                print(f"{percent}% за {time.monotonic() - started:.1f} с", flush=True)
                previous = percent
    if digest(TARGET) != DIGEST:
        raise ValueError("Не совпала контрольная сумма весов")
    if not BLOB.resolve().is_relative_to(ROOT):
        raise ValueError("Целевой путь находится вне E:/korrekta")
    BLOB.parent.mkdir(parents=True, exist_ok=True)
    TARGET.rename(BLOB)
    print(f"SHA-256 подтверждён: {BLOB}", flush=True)


if __name__ == "__main__":
    main()
