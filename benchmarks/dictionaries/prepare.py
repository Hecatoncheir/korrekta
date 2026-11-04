"""Изолированная подготовка словарей и эталонного Hunspell на E:."""

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import urllib.request
import zipfile

STORE = Path("E:/korrekta/dictionaries-v1")
MANIFEST = STORE / "manifest.json"
RECORDS = {}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "korrekta-research"}), timeout=30)


def fetch(url, name, expected=None):
    path = STORE / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        print(f"Получение {name}", flush=True)
        with get(url) as source, path.open("wb") as sink:
            while block := source.read(1024 * 1024):
                sink.write(block)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if expected and digest != expected:
        raise ValueError(f"Не совпадает SHA-256: {path}")
    RECORDS[name] = {"url": url, "sha256": digest, "bytes": path.stat().st_size}
    return path


def wheel(package):
    metadata = json.load(get(f"https://pypi.org/pypi/{package}/json"))
    item = next(item for item in metadata["urls"] if item["filename"].endswith(".whl"))
    return fetch(item["url"], item["filename"], item["digests"]["sha256"])


def prepare_opencorpora():
    dictionary = wheel("pymorphy3-dicts-ru")
    decoder = wheel("DAWG-Python")
    with zipfile.ZipFile(dictionary) as archive:
        prefix = "pymorphy3_dicts_ru/data/"
        meta = dict(json.loads(archive.read(prefix + "meta.json")))
        source = STORE / "words.dawg"
        source.write_bytes(archive.read(prefix + "words.dawg"))
    sys.path.insert(0, str(decoder))
    from dawg_python import RecordDAWG
    output = STORE / "known-ru.txt"
    cache = STORE / "known-ru.provenance.json"
    source_hash = hashlib.sha256(dictionary.read_bytes()).hexdigest()
    if output.exists() and cache.exists():
        cached = json.loads(cache.read_text(encoding="utf-8"))
        if cached["source_sha256"] == source_hash and cached["output_sha256"] == hashlib.sha256(output.read_bytes()).hexdigest():
            forms = set(output.read_text(encoding="utf-8").splitlines())
            RECORDS[output.name] = {"sha256": cached["output_sha256"], "count": len(forms)}
            return forms, meta
    dawg = RecordDAWG(">HH").load(str(source))
    forms = set()
    for index, word in enumerate(dawg.iterkeys()):
        if re.fullmatch("[а-яё]+", word):
            forms.add(word.replace("ё", "е"))
        if index and index % 1000000 == 0:
            print(f"Прочитано записей OpenCorpora: {index}", flush=True)
    output.write_text("".join(word + "\n" for word in sorted(forms)), encoding="utf-8", newline="\n")
    RECORDS[output.name] = {"sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "count": len(forms)}
    cache.write_text(json.dumps({"source_sha256": source_hash, "output_sha256": RECORDS[output.name]["sha256"]}), encoding="utf-8")
    return forms, meta


def github_revision(repo):
    return json.load(get(f"https://api.github.com/repos/{repo}/commits?per_page=1"))[0]["sha"]


def prepare_frequency(forms):
    revision = github_revision("wolfgarbe/SymSpell")
    for language, filename in [("ru", "ru-100k.txt"), ("en", "en-80k.txt")]:
        source = fetch(f"https://raw.githubusercontent.com/wolfgarbe/SymSpell/{revision}/SymSpell.FrequencyDictionary/{filename}", filename)
        entries = {}
        for line in source.read_text(encoding="utf-8-sig").splitlines():
            parts = line.split()
            if len(parts) != 2 or not parts[1].isdigit():
                continue
            word, count = parts[0].lower(), int(parts[1])
            pattern = "[а-яё]+" if language == "ru" else "[a-z]+"
            if not re.fullmatch(pattern, word):
                continue
            if language == "ru" and word.replace("ё", "е") not in forms:
                continue
            entries[word] = entries.get(word, 0) + count
        output = STORE / f"frequency-{language}.tsv"
        output.write_text("".join(f"{word}\t{count}\n" for word, count in sorted(entries.items())), encoding="utf-8", newline="\n")
        RECORDS[output.name] = {"sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "count": len(entries)}
    return revision


def prepare_hunspell():
    pending = ["mingw-w64-ucrt-x86_64-hunspell"]
    done = set()
    while pending:
        package = pending.pop()
        if package in done:
            continue
        done.add(package)
        print(f"Метаданные {package}", flush=True)
        page_path = STORE / "package-metadata" / (package + ".html")
        page_path.parent.mkdir(exist_ok=True)
        if not page_path.exists():
            for attempt in range(3):
                try:
                    with get("https://packages.msys2.org/packages/" + package) as response:
                        chunks = []
                        while block := response.read1(8192):
                            chunks.append(block)
                            if b"Optional Dependencies:" in b"".join(chunks):
                                break
                    page_path.write_bytes(b"".join(chunks))
                    break
                except (TimeoutError, OSError):
                    if attempt == 2:
                        raise
        page = page_path.read_text(encoding="utf-8")
        url = re.search(r'href="(https://mirror.msys2.org/mingw/ucrt64/[^"]+\.pkg\.tar\.zst)"', page)[1]
        checksum = re.search(r'SHA256:</dt>\s*<dd[^>]*><code>([a-f0-9]{64})', page)[1]
        archive = fetch(url, "packages/" + url.rsplit("/", 1)[1], checksum)
        listing = subprocess.check_output(["tar", "-tf", str(archive)], text=True, encoding="utf-8")
        assert all(not PurePosixPath(name).is_absolute() and ".." not in PurePosixPath(name).parts for name in listing.splitlines())
        target = STORE / "native"
        target.mkdir(exist_ok=True)
        subprocess.run(["tar", "-xf", str(archive), "-C", str(target)], check=True)
        section = page.split("Dependencies:</dt>", 1)[1].split("Optional Dependencies:", 1)[0]
        pending.extend(re.findall(r'href="https://packages.msys2.org/packages/(mingw-w64-ucrt-x86_64-[^"]+)"', section))
    revision = github_revision("LibreOffice/dictionaries")
    for language, files in [("ru_RU", ["ru_RU.aff", "ru_RU.dic", "README_ru_RU.txt"]),
                            ("en", ["en_US.aff", "en_US.dic", "license.txt"])]:
        for name in files:
            fetch(f"https://raw.githubusercontent.com/LibreOffice/dictionaries/{revision}/{language}/{name}", "hunspell/" + name)
    executable = STORE / "native/ucrt64/bin/hunspell.exe"
    version = subprocess.check_output([str(executable), "-v"], encoding="utf-8", text=True)
    return revision, version.strip()


def main():
    STORE.mkdir(parents=True, exist_ok=True)
    forms, meta = prepare_opencorpora()
    frequency_revision = prepare_frequency(forms)
    hunspell_revision, version = prepare_hunspell()
    result = {"opencorpora": meta, "symspell_revision": frequency_revision,
              "libreoffice_revision": hunspell_revision, "hunspell_version": version,
              "artifacts": RECORDS}
    MANIFEST.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"known_forms": len(forms), "hunspell": version}, ensure_ascii=False))


if __name__ == "__main__":
    main()
