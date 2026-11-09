"""Paquet de distribution de SpotterEnginer (comme celui d'AdvancedIA) : seulement ce que le jeu charge (point d'entrée,
manifeste, icône, modules, signal radio, voix, polices) et les notices du pilote, sous apps/lua/SpotterEnginer/ ;
SpotterEnginer-<version>.zip et son empreinte SpotterEnginer-<version>.sha256 (« <sha256>  <nom du zip> »). Les tests,
les outils et la documentation technique n'y sont jamais.
Le paquet est ensuite contrôlé par le vrai module de mise à jour (src/update.lua, sous lupa), comme l'app le fera :
chemins sûrs, fichiers indispensables, modules requis, version du manifeste, nom accepté par M.release, taille bornée,
pont compatible avec AdvancedIA installé.
Rien n'est écrit dans le dossier de l'app (CSP la recharge en jeu dès qu'un de ses fichiers change) : paquet dans le
dossier temporaire par défaut.
Usage : python tools/package.py [dossier de sortie]"""
from pathlib import Path
import hashlib
import sys
import tempfile
import zipfile
from lupa import LuaRuntime

APP = Path(__file__).resolve().parents[1]
PREFIX = 'apps/lua/SpotterEnginer/'
NOTICES = ['README.md', 'CHANGELOG.md', 'COMPATIBILITY.md', 'LICENSE']


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("local p=... ; package.path=p..'/?.lua;'..package.path", APP.as_posix())
    return lua


def collect():
    files = [APP / name for name in ['SpotterEnginer.lua', 'manifest.ini', 'icon.png', *NOTICES]]
    for folder, patterns in [('src', ['*.lua']), ('sounds', ['*.wav']), ('vox', ['*/*.wav', '*/*/*.wav']), ('fonts', ['*/*.ttf', '*/OFL.txt'])]:
        for pattern in patterns:
            files.extend((APP / folder).glob(pattern))
    missing = [p.name for p in files if not p.exists()]
    assert not missing, f'fichiers absents : {missing}'
    return sorted({p for p in files if p.is_file()})


def main():
    lua = runtime()
    up = lua.eval("(require('src/update'))")
    version = up.manifestVersion((APP / 'manifest.ini').read_text(encoding='utf-8'))
    assert version, 'version du manifeste illisible'
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.gettempdir()) / 'SpotterEnginer-dist'
    out.mkdir(parents=True, exist_ok=True)
    zip_path = out / f'{up.assetPrefix}{version}.zip'
    sha_path = out / f'{up.assetPrefix}{version}.sha256'
    for old in [*out.glob(f'{up.assetPrefix}*.zip'), *out.glob(f'{up.assetPrefix}*.sha256')]:
        if old.stem != zip_path.stem:
            old.unlink()
    files = collect()
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            archive.write(path, PREFIX + path.relative_to(APP).as_posix())
    data = zip_path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    sha_path.write_text(f'{digest}  {zip_path.name}\n', encoding='ascii', newline='\n')
    check(lua, up, zip_path, sha_path, version)
    print(f'{zip_path.name}: {len(files)} fichiers, {len(data)} octets, SHA256 {digest}')
    print(f'{sha_path}')


def check(lua, up, zip_path, sha_path, version):
    """Contrôles de l'app (src/update.lua) sur le paquet construit."""
    with zipfile.ZipFile(zip_path) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        entries = lua.table_from(names)
        texts = {n: archive.read(n) for n in names}
    for bad in ('/tests/', '/tools/', '/docs/', '__pycache__', '.pyc', '/dist/'):
        assert not any(bad in n for n in names), bad
    assert up.content(entries), 'contenu refusé (chemins ou fichiers indispensables)'

    def read(name):
        raw = texts.get(name)
        return raw.decode('utf-8', 'replace') if raw is not None else None
    ok = up.requires(entries, read)
    assert ok is True or (isinstance(ok, tuple) and ok[0]), f'module absent : {ok}'
    assert up.manifestVersion(read(PREFIX + 'manifest.ini')) == version, 'version du manifeste du paquet'
    # Nom et adresse acceptés par M.release, taille sous la borne.
    number = '.'.join(str(int(x)) for x in up.version(version).values())
    release = lua.table_from({'tag_name': 'v' + number, 'draft': False, 'prerelease': False, 'published_at': '2026-01-01T00:00:00Z',
                              'html_url': up.page + '/tag/v' + number, 'body': '',
                              'assets': lua.table_from([
                                  lua.table_from({'name': zip_path.name, 'size': zip_path.stat().st_size,
                                                  'browser_download_url': up.download + 'v' + number + '/' + zip_path.name}),
                                  lua.table_from({'name': sha_path.name, 'size': sha_path.stat().st_size,
                                                  'browser_download_url': up.download + 'v' + number + '/' + sha_path.name})])})
    r = up.release(release)
    assert r and r.version == version, 'nom du paquet refusé par M.release'
    digest = up.digest(sha_path.read_text(encoding='ascii'), zip_path.name)
    assert digest == hashlib.sha256(zip_path.read_bytes()).hexdigest(), 'empreinte'
    # Pont compatible avec AdvancedIA installé (s'il est là).
    companion = None
    for name in lua.eval("(require('src/update')).companion.folders").values():
        d = APP.parent / name
        if (d / 'manifest.ini').exists():
            companion = (d / 'src' / 'bridge_layout.lua').read_text(encoding='utf-8')
            break
    if companion is not None:
        res = up.compatible(read(PREFIX + 'src/bridge_layout.lua'), companion)
        fits = res if not isinstance(res, tuple) else res[0]
        assert fits is True, f'pont incompatible avec AdvancedIA installé : {res}'
    print('contrôles de l\'app : contenu, modules, version, nom, empreinte, pont' + (' (AdvancedIA installé)' if companion else ''))


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    main()
