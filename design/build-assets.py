"""Готовит самостоятельные векторные логотипы и размеры иконок."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from io import BytesIO
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from PIL import Image
import cairosvg

assets = Path(__file__).parent / 'dist' / 'assets'
font = TTFont(assets / 'fonts' / 'font-6.ttf')
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
scale = 64 / font['head'].unitsPerEm
cursor = 110
paths = []
for letter in 'корректа.':
    name = cmap[ord(letter)]
    pen = SVGPathPen(glyphs)
    glyphs[name].draw(pen)
    paths.append(f'<path d="{pen.getCommands()}" transform="translate({cursor:.3f} 76) scale({scale} {-scale})"/>')
    cursor += font['hmtx'][name][0] * scale - 2.2
mark = '<g fill="none" stroke="currentColor" stroke-width="15" stroke-linecap="round" stroke-linejoin="round"><path d="M30 20C25 35 24 58 28 78"/><path d="M73 22C63 39 49 47 28 51"/><path d="M46 46C54 55 61 70 76 75"/></g>'
for name, color in [('logo', '#282828'), ('logo-light', '#fbf1c7')]:
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {cursor + 12:.1f} 100" color="{color}" fill="currentColor"><title>Корректа</title>{mark}{"".join(paths)}</svg>'
    (assets / f'{name}.svg').write_text(svg, encoding='utf-8')
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(assets / f'{name}.png'), output_width=1600)

alternative = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><title>Корректа — кавычки</title><path d="M24 12C7 12 8 35 15 50L34 87c3 6 12 2 9-4L30 48c19-2 24-36-6-36Zm50 0C57 12 58 35 65 50L84 87c3 6 12 2 9-4L80 48c19-2 24-36-6-36Z" fill="#282828"/></svg>'
(assets / 'mark-quotes.svg').write_text(alternative, encoding='utf-8')
alternative = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><title>Корректа — чернильная точка</title><defs><mask id="cut"><rect width="100" height="100" fill="white"/><path d="m30 53 15 15 27-31" fill="none" stroke="black" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/></mask></defs><path d="M56 7C40 14 10 37 10 58c0 24 17 35 40 35s40-16 40-36C90 36 73 17 56 7Z" fill="#282828" mask="url(#cut)"/></svg>'
(assets / 'mark-ink.svg').write_text(alternative, encoding='utf-8')
icon = (assets / 'app-icon.svg').read_bytes()
for size in [16, 24, 32, 48, 64, 128, 256, 512, 1024]:
    cairosvg.svg2png(bytestring=icon, write_to=str(assets / f'app-icon-{size}.png'), output_width=size, output_height=size)
image = Image.open(assets / 'app-icon-1024.png')
image.save(assets / 'korrekta.ico', format='ICO', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
image.save(assets / 'korrekta.icns', format='ICNS')

with ZipFile(assets / 'korrekta-brand.zip', 'w', ZIP_DEFLATED) as archive:
    for path in sorted(assets.iterdir()):
        if path.suffix in {'.svg', '.png', '.ico', '.icns'}:
            archive.write(path, path.name)
    archive.writestr('О материалах.txt', 'Корректа — дизайн-концепция.\nОсновной знак: mark.svg.\nСловесный логотип: logo.svg, logo-light.svg (буквы переведены в контуры).\nИконка: app-icon.svg, PNG 16–1024, ICO для Windows, ICNS для macOS.\nВарианты: mark-quotes.svg, mark-ink.svg.\nЗначки интерфейса: icons.svg, 21 symbol.\nШрифты: Nunito, Nunito Sans, JetBrains Mono (SIL OFL).\nПалитра: #FBF1C7 #282828 #79740E #B8BB26.\n')
print('Материалы готовы: SVG, PNG, ICO, ICNS и архив.')
