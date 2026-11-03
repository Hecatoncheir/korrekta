"""Сохраняет указанные в макете шрифты и их лицензии для автономного просмотра."""
from pathlib import Path
from urllib.request import Request, urlopen
import re

target = Path(__file__).parent / 'dist' / 'assets' / 'fonts'
target.mkdir(parents=True, exist_ok=True)
url = 'https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800;900;1000&family=Nunito+Sans:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500&display=swap'
request = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
css = urlopen(request).read().decode()
urls = list(dict.fromkeys(re.findall(r'https://[^)\s]+', css)))
for index, font_url in enumerate(urls):
    filename = f'font-{index}{Path(font_url).suffix}'
    (target / filename).write_bytes(urlopen(font_url).read())
    css = css.replace(font_url, filename)
(target / 'fonts.css').write_text(css, encoding='utf-8')
for name in ['nunito', 'nunitosans', 'jetbrainsmono']:
    license_url = f'https://raw.githubusercontent.com/google/fonts/main/ofl/{name}/OFL.txt'
    (target / f'{name}-OFL.txt').write_bytes(urlopen(license_url).read())
print(f'Сохранено файлов шрифтов: {len(urls)}')
