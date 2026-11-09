"""Tests de SpotterEnginer hors du jeu (Python + lupa) : modules purs chargés sous globales strictes (toute lecture ou
écriture d'une globale non déclarée est une erreur, comme dans les tests d'AdvancedIA), puis chaque fichier
tests/*_spec.lua (table de fonctions de test). Vérifie aussi :
- que src/bridge_layout.lua est identique au caractère près dans AdvancedIA (ou ACAdvancedIA) et ici ;
- le pont réel d'AdvancedIA (src/bridge.lua) sur un moteur factice, lu par src/link.lua ;
- la syntaxe de tous les fichiers Lua de l'app ;
et refait vox/VOICE_CLIPS.md (liste des clips de voix, en anglais) à partir de src/catalog.lua.
Usage : python tests/run.py"""
from pathlib import Path
import sys
from lupa import LuaRuntime

APP = Path(__file__).resolve().parents[1]


def aai_dir():
    """Dossier d'AdvancedIA installé, avec la même règle que src/port.lua M.detect() : dossiers de la mise à jour
    (src/update.lua, Update.companion.folders : nouveau nom d'abord) ; seul le manifeste compte."""
    lua = LuaRuntime()
    lua.execute("local p = ... ; package.path = p .. '/?.lua;' .. package.path", APP.as_posix())
    for name in lua.eval("(require('src/update')).companion.folders").values():
        d = APP.parent / name
        if (d / 'manifest.ini').exists():
            return d
    return APP.parent / 'AdvancedIA'


AAI = aai_dir()


def doc_bridge():
    """Code du raccordement d'applier.lua, tel qu'écrit dans docs/PONT_ACADVANCEDIA.md (testé tel quel)."""
    text = (APP / 'docs' / 'PONT_ACADVANCEDIA.md').read_text(encoding='utf-8')
    part = text.split('## Hook-up in `src/applier.lua`', 1)[1]
    return part.split('```lua', 1)[1].split('```', 1)[0]


def installed_bridge():
    """Raccordement d'applier.lua tel qu'installé dans AdvancedIA (de bridgeItem jusqu'au return final), ou ''."""
    p = AAI / 'src' / 'applier.lua'
    if not p.exists():
        return ''
    text = p.read_text(encoding='utf-8')
    if 'function M.bridgeOpen' not in text:
        return ''
    start = text.index('local function bridgeItem')
    end = text.rindex('return M')
    return text[start:end]


def vox_files():
    out = []
    for f in (APP / 'vox').rglob('*'):
        if f.is_file() and f.suffix.lower() in ('.wav', '.mp3', '.ogg'):
            out.append(f.relative_to(APP / 'vox').as_posix())
    return out


def runtime(host=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("local p = ... ; package.path = p .. '/?.lua;' .. package.path", APP.as_posix())
    # Toute partie de phrase inconnue du catalogue fait échouer les tests (au lieu d'une annonce seulement écrite).
    lua.execute("(require('src/say')).strict = true")
    if host:
        lua.execute((APP / 'tests' / 'host.lua').read_text(encoding='utf-8'))
        g = lua.globals()
        g.VOX = lua.table_from(vox_files())
        g.DOC_BRIDGE = doc_bridge()
        g.INSTALLED_BRIDGE = installed_bridge()
        g.APP_SOURCE = (APP / 'SpotterEnginer.lua').read_text(encoding='utf-8')
        g.APP_MANIFEST = (APP / 'manifest.ini').read_text(encoding='utf-8')
    # Pont réel d'AdvancedIA, chargé sous le nom 'aai/bridge' (il lit src/bridge_layout, identique dans les deux apps).
    bridge = AAI / 'src' / 'bridge.lua'
    if bridge.exists():
        lua.execute("local src=... ; package.preload['aai/bridge']=function() return assert(load(src,'@AdvancedIA/src/bridge.lua'))() end",
                    bridge.read_text(encoding='utf-8'))
    lua.execute("""
      setmetatable(_G, {
        __index=function(_,k) error('undeclared global read: '..tostring(k),2) end,
        __newindex=function(_,k) error('undeclared global write: '..tostring(k),2) end
      })
    """)
    return lua


def syntax():
    lua = LuaRuntime()
    files = [APP / 'SpotterEnginer.lua', *sorted((APP / 'src').glob('*.lua'))]
    bad = []
    for f in files:
        if not f.exists():
            continue
        ok = lua.execute("local s=...; local f,e=load(s,'@x'); return e or ''", f.read_text(encoding='utf-8'))
        if ok:
            bad.append(f'{f.name}: {ok}')
    return len(files), bad


def shipped_requires():
    """Code livré accepté par la mise à jour : tous les require('src/…') écrits en clair (src/update.lua, M.requires) visent
    un module de l'app, et les fichiers indispensables (M.required) existent. Renvoie '' ou la raison."""
    lua = runtime()
    up = lua.eval("(require('src/update'))")
    files = ['SpotterEnginer.lua', 'manifest.ini', *[p.relative_to(APP).as_posix() for p in sorted((APP / 'src').glob('*.lua'))]]
    entries = lua.table_from([up.prefix + f for f in files])
    ok = up.requires(entries, lambda name: (APP / name[len(up.prefix):]).read_text(encoding='utf-8'))
    if not (ok is True or (isinstance(ok, tuple) and ok[0])):
        return f'module absent : {ok[1] if isinstance(ok, tuple) else ok}'
    if not up.content(entries):
        return 'fichiers indispensables absents'
    return ''


def layout_identical():
    a = (APP / 'src' / 'bridge_layout.lua').read_bytes()
    p = AAI / 'src' / 'bridge_layout.lua'
    return p.exists() and a == p.read_bytes()


def recording_list():
    """vox/VOICE_CLIPS.md (in English, like every document of the repository): every clip with its file and text, rebuilt
    from src/catalog.lua."""
    lua = runtime()
    cat = lua.eval("(require('src/catalog'))")
    sec_text = lambda lang, n: lua.eval('(require("src/say")).secondsText')(lang, n / 10, 1 if n % 10 else 0)
    last_num, last_sec, last_pos = int(cat.maxNumber), int(cat.maxTenths), int(cat.maxPosition)
    lines = ['# Voice clips', '',
             'Every clip is generated by `python tools/generer_voix.py` (edge-tts, voices fr-FR-HenriNeural and en-US-GuyNeural,',
             'the same as the original clips 01 to 34): radio effect, VBR MP3 24 kHz mono, silences trimmed, named .wav (AC reads',
             'the content, not the extension). For another voice, record files with the same names: a missing clip blocks',
             'nothing, the call is then only written on the overlay radio.',
             'This list is rebuilt by `python tests/run.py` from `src/catalog.lua`.', '',
             f'{int(cat.fileCount())} files in all ({len(cat.languages)} languages).', '']
    lines += ['## Calls', '', '| No. | FR file (vox/FR) | FR text | EN file (vox/EN) | EN text |', '|---|---|---|---|---|']
    order = cat.order
    for k in range(1, len(order) + 1):
        c = cat.clips[order[k]]
        lines.append(f'| {c.number} | `{c.FR}` | {c.textFR} | `{c.EN}` | {c.textEN} |')
    lines += ['', '## Numbers', '', f'Folder `num` in each language: `vox/FR/num/00.wav` to `vox/FR/num/{last_num:02d}.wav`, same in English.', '',
              '| File | FR | EN |', '|---|---|---|']
    for n in range(last_num + 1):
        lines.append(f'| `num/{n:02d}.wav` | {cat.numberFR(n)} | {cat.numberEN(n)} |')
    lines += ['', '## Durations', '', f'Folder `sec` in each language: `vox/FR/sec/000.wav` (0 s) to `vox/FR/sec/{last_sec:03d}.wav` ({sec_text("EN", last_sec)}),',
              'number and unit in one clip, spoken 10 % faster (gaps read in one breath). Beyond: number, then "seconds".', '',
              '| File | FR | EN |', '|---|---|---|']
    for n in range(last_sec + 1):
        lines.append(f'| `sec/{n:03d}.wav` | {sec_text("FR", n)} | {sec_text("EN", n)} |')
    lines += ['', '## Positions', '', f'Folder `pos` in each language: `vox/FR/pos/01.wav` to `vox/FR/pos/{last_pos:02d}.wav`, spoken 10 % faster.',
              'Written on the radio: "Tu es P7." / "You\'re P7."; sent to edge-tts in French as "Tu es Pé 7." ("P7" is mispronounced).', '',
              '| File | FR (spoken) | EN |', '|---|---|---|']
    for n in range(1, last_pos + 1):
        lines.append(f'| `pos/{n:02d}.wav` | {cat.positionSpoken("FR", n)} | {cat.positionSpoken("EN", n)} |')
    # Rewritten only when it changes: CSP reloads the app in game as soon as one of its files changes.
    out = APP / 'vox' / 'VOICE_CLIPS.md'
    text = '\n'.join(lines) + '\n'
    if not out.exists() or out.read_text(encoding='utf-8') != text:
        out.write_text(text, encoding='utf-8', newline='\n')


def main():
    failures = 0
    checks = 0
    count, bad = syntax()
    checks += 1
    if bad:
        failures += 1
        print('FAIL syntax', bad)
    else:
        print(f'PASS syntax ({count} files)')
    checks += 1
    if layout_identical():
        print(f'PASS bridge_layout identical in {AAI.name} and SpotterEnginer')
    else:
        failures += 1
        print(f'FAIL bridge_layout differs between {AAI.name} and SpotterEnginer (or missing)')
    checks += 1
    why = shipped_requires()
    if why:
        failures += 1
        print(f'FAIL shipped code refused by the updater: {why}')
    else:
        print('PASS shipped code accepted by the updater (requires, required files)')
    for spec in sorted((APP / 'tests').glob('*_spec.lua')):
        lua = runtime(host=spec.name.startswith('integration'))
        try:
            tests = lua.execute(spec.read_text(encoding='utf-8'))
        except Exception as e:  # noqa: BLE001
            checks += 1
            failures += 1
            print(f'FAIL {spec.stem} (load): {e}')
            continue
        names = sorted(tests.keys())
        for name in names:
            checks += 1
            try:
                tests[name]()
                print(f'PASS {spec.stem}.{name}')
            except Exception as e:  # noqa: BLE001
                failures += 1
                print(f'FAIL {spec.stem}.{name}: {e}')
    recording_list()
    print(f'{checks} checks, {failures} failures')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
