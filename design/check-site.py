"""Проверяет наличие локальных ресурсов HTML и CSS перед публикацией."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import re
import sys

ROOT = Path(__file__).parent / 'dist'
missing = []


def check_link(source, value):
    url = urlsplit(value)
    if url.scheme or url.netloc or not url.path:
        return
    target = source.parent / unquote(url.path)
    if not target.is_file():
        missing.append(f'{source.relative_to(ROOT)}: {value}')


class Resources(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.source = source

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('href', 'src') and value:
                check_link(self.source, value)


for source in ROOT.glob('*.html'):
    Resources(source).feed(source.read_text(encoding='utf-8'))

for source in ROOT.rglob('*.css'):
    content = source.read_text(encoding='utf-8')
    for value in re.findall(r'url\([\"\x27]?([^\)\"\x27]+)', content):
        check_link(source, value.strip())

if missing:
    print('Не найдены ресурсы:\n' + '\n'.join(missing))
    sys.exit(1)

print('Все локальные ресурсы HTML и CSS доступны.')
