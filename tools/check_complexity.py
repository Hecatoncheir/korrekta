"""Проверка нового Flutter-кода официальным анализатором выбранного проекта."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--nvim', default='nvim')
    options = parser.parse_args()
    plugin = ROOT / 'work/complexity'
    sources = sorted((ROOT / 'app/lib').rglob('*.dart'))
    sources += sorted((ROOT / 'tools/model_benchmark/lib/src').glob('desktop_*.dart'))
    file_list = ROOT / 'work/complexity-files.txt'
    file_list.write_text('\n'.join(p.as_posix() for p in sources), encoding='utf-8')
    command = [options.nvim, '--headless', '-u', 'NONE', '-l',
               str(plugin / 'scripts/dump-complexity.lua'), 'dart', str(file_list), 'inline']
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', check=True)
    entries = []
    for line in result.stdout.splitlines():
        path, row, cc, cog, name = line.split('\t', 4)
        entries.append(dict(path=path, line=int(row), cc=int(cc), cog=int(cog), name=name))
    if not entries:
        raise RuntimeError('Анализатор не вернул функций; результат не принимается')
    (ROOT / 'work/complexity-report.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2), encoding='utf-8')
    bad = [e for e in entries if e['cog'] > 10 or e['cc'] > 15]
    for entry in sorted(entries, key=lambda e: e['cog'], reverse=True)[:10]:
        print(f"COG={entry['cog']} CC={entry['cc']} {entry['path']}:{entry['line']} {entry['name']}")
    print(f'Проверено функций: {len(entries)}; превышений: {len(bad)}')
    return int(bool(bad))


if __name__ == '__main__':
    sys.exit(main())
