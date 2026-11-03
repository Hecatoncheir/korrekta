"""Подготовка отдельного LanguageTool 6.8 и Java на E: для исследования."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.request
import zipfile

JRE = "OpenJDK21U-jre_x64_windows_hotspot_21.0.13_9.zip"
JRE_URL = f"https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/{JRE}"
JRE_SHA256 = "2332c0b4cff6bed722da3567c91d5e47568bcba863fa4945d0a8d6fc76158628"
MAVEN = "apache-maven-3.9.11-bin.zip"
MAVEN_URL = f"https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.11/{MAVEN}"
MAVEN_SHA512 = "03e2d65d4483a3396980629f260e25cac0d8b6f7f2791e4dc20bc83f9514db8d0f05b0479e699a5f34679250c49c8e52e961262ded468a20de0be254d8207076"


def digest(path, algorithm):
    with path.open("rb") as source:
        return hashlib.file_digest(source, algorithm).hexdigest()


def prepare_archive(root, filename, url, algorithm, expected, marker):
    archive = root / "downloads" / filename
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists() or digest(archive, algorithm) != expected:
        temporary = archive.with_suffix(".part")
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=60) as source, temporary.open("wb") as target:
            while chunk := source.read(1024 * 1024):
                target.write(chunk)
        if digest(temporary, algorithm) != expected:
            raise ValueError(f"Не совпала контрольная сумма: {filename}")
        temporary.replace(archive)
    destination = (root / "runtimes").resolve()
    destination.mkdir(parents=True, exist_ok=True)
    if not (destination / marker).exists():
        with zipfile.ZipFile(archive) as bundle:
            if not all((destination / item.filename).resolve().is_relative_to(destination) for item in bundle.infolist()):
                raise ValueError("Небезопасный путь в архиве")
            bundle.extractall(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storage", default="E:/korrekta")
    args = parser.parse_args()
    root = Path(args.storage).resolve()
    prepare_archive(root, JRE, JRE_URL, "sha256", JRE_SHA256, "jdk-21.0.13+9-jre/bin/java.exe")
    prepare_archive(root, MAVEN, MAVEN_URL, "sha512", MAVEN_SHA512, "apache-maven-3.9.11/bin/mvn.cmd")
    temporary = root / "tmp"
    temporary.mkdir(parents=True, exist_ok=True)
    environment = {**os.environ, "JAVA_HOME": str(root / "runtimes/jdk-21.0.13+9-jre"),
                   "TEMP": str(temporary), "TMP": str(temporary)}
    libraries = root / "languagetool/6.8/lib"
    subprocess.run([
        str(root / "runtimes/apache-maven-3.9.11/bin/mvn.cmd"), "-B", "-ntp", "-C",
        "-f", str(Path(__file__).parent / "runtime/pom.xml"),
        f"-Dmaven.repo.local={root / 'cache/maven'}",
        "org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy-dependencies",
        f"-DoutputDirectory={libraries}", "-DincludeScope=runtime",
    ], check=True, env=environment)
    manifest = {"engine": "LanguageTool 6.8", "java": "Temurin 21.0.13+9 Windows x64",
                "jre_url": JRE_URL, "jre_sha256": JRE_SHA256,
                "maven_url": MAVEN_URL, "maven_sha512": MAVEN_SHA512,
                "files": [{"name": path.name, "bytes": path.stat().st_size,
                           "sha256": digest(path, "sha256")}
                          for path in sorted(libraries.glob("*.jar"))]}
    manifest_path = root / "languagetool/6.8/installation-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Подготовлено: {libraries}; файлов: {len(manifest['files'])}")


if __name__ == "__main__":
    main()
