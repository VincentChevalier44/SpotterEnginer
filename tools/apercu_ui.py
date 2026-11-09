"""Aperçus de l'interface hors du jeu : la fenêtre de réglages (chaque page) et les trois overlays sont dessinés par le
vrai code de l'app sur l'hôte CSP factice (tests/host.lua), pendant une course simulée (tests/integration_spec.lua) ;
les opérations de dessin (rectangles, lignes, textes, images) sont enregistrées puis reproduites en PNG avec les
polices livrées, les largeurs de texte étant mesurées par ces mêmes polices.
Rien n'est écrit dans le dossier de l'app (CSP la recharge en jeu dès qu'un de ses fichiers change) : aperçus dans le
dossier temporaire par défaut, pas de bytecode Python.
Usage : python tools/apercu_ui.py [dossier de sortie]"""
from pathlib import Path
import sys
import tempfile
from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(APP / 'tests'))
import run  # noqa: E402

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.gettempdir()) / 'SpotterEnginer_apercus'
FONTS = {
    ('Barlow', 'Regular', ''): 'barlow/Barlow-Regular.ttf', ('Barlow', 'SemiBold', ''): 'barlow/Barlow-SemiBold.ttf',
    ('Barlow Condensed', 'SemiBold', ''): 'barlowcondensed/BarlowCondensed-SemiBold.ttf',
    ('Barlow Condensed', 'Bold', ''): 'barlowcondensed/BarlowCondensed-Bold.ttf',
    ('Barlow Condensed', 'UltraBold', 'Italic'): 'barlowcondensed/BarlowCondensed-ExtraBoldItalic.ttf',
    ('JetBrains Mono', 'Medium', ''): 'jetbrainsmono/JetBrainsMono-Medium.ttf',
}
cache = {}


def font(name, size):
    family = name.split(':')[0]
    weight = 'Regular'
    style = ''
    for part in name.split(';')[1:]:
        k, _, v = part.partition('=')
        if k == 'Weight': weight = v
        if k == 'Style': style = v
    path = FONTS.get((family, weight, style)) or 'barlow/Barlow-Regular.ttf'
    key = (path, round(size * 4))
    if key not in cache:
        cache[key] = ImageFont.truetype(str(APP / 'fonts' / path), max(1, int(round(size))))
    return cache[key]


def measure(name, text, size):
    return font(name or 'Barlow', size).getlength(text)


def colour(c, alpha=1.0):
    return (int(c.r * 255), int(c.g * 255), int(c.b * 255), int(max(0, min(1, (c.mult if c.mult is not None else 1) * alpha)) * 255))


def render(ops, w, h, path, bg=(30, 32, 38, 255)):
    img = Image.new('RGBA', (int(w), int(h)), bg)
    layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k in range(1, len(ops) + 1):
        op = ops[k]
        kind = op.kind
        if kind == 'rect':
            d.rectangle([op.x1, op.y1, op.x2, op.y2], fill=colour(op.col))
        elif kind == 'rectline':
            d.rectangle([op.x1, op.y1, op.x2, op.y2], outline=colour(op.col), width=max(1, int(op.th or 1)))
        elif kind == 'line':
            d.line([op.x1, op.y1, op.x2, op.y2], fill=colour(op.col), width=max(1, int(op.th or 1)))
        elif kind == 'circle':
            d.ellipse([op.x - op.r, op.y - op.r, op.x + op.r, op.y + op.r], fill=colour(op.col))
        elif kind == 'poly':
            d.polygon([(op.pts[i], op.pts[i + 1]) for i in range(1, len(op.pts), 2)], fill=colour(op.col))
        elif kind == 'text':
            d.text((op.x, op.y), op.str, font=font(op.font or 'Barlow', op.size), fill=colour(op.col))
        elif kind == 'image':
            try:
                im = Image.open(op.path).convert('RGBA').resize((int(op.x2 - op.x1), int(op.y2 - op.y1)))
                layer.alpha_composite(im, (int(op.x1), int(op.y1)))
            except Exception:  # noqa: BLE001
                pass
    img.alpha_composite(layer)
    img.convert('RGB').save(path)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lua = run.runtime(host=True)
    g = lua.globals()
    host = g.HOST
    host.measure = measure
    host.realIcon = str(APP / 'icon.png')
    tests = lua.execute((APP / 'tests' / 'integration_spec.lua').read_text(encoding='utf-8'))
    lua.execute("HOST.recordOn=false")
    tests.full_race_with_bridge()
    app = g.SPE_TEST.app
    # Polices livrées (l'hôte factice ne voit pas le dossier fonts) : rechargées au prochain dessin.
    app.fontDir = 'fonts'
    lua.execute("script.SPE__MAIN()")
    app.view.fonts = False
    lua.execute("HOST.recordOn=true")
    for lang in ('FR', 'EN'):
        app.set('language', lang)
        cfgmod = lua.eval("(require('src/config'))")
        tabs = cfgmod.tabs
        for k in range(1, len(tabs) + 1):
            tab = tabs[k]
            secs = cfgmod.sectionsOf[tab]
            ids = [secs[i].id for i in range(1, len(secs) + 1)] if secs else [None]
            for sid in ids:
                app.view.tab = tab
                if sid:
                    app.view.section[tab] = sid
                lua.execute("HOST.ops={}; HOST.space=vec2(860,640)")
                lua.execute("script.SPE__MAIN()")
                name = f'reglages_{lang}_{tab}' + (f'_{sid}' if sid else '')
                render(host.ops, 860, 640, OUT / f'{name}.png')
        lua.execute("HOST.ops={}; HOST.windowIds={}")
        lua.execute("HOST.space=vec2(1920,1080); script.SPE__HUD()")
        render(host.ops, 1920, 1080, OUT / f'overlays_{lang}.png', bg=(70, 80, 70, 255))
    print('aperçus dans', OUT)


if __name__ == '__main__':
    main()
