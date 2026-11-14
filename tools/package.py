"""Paquet de distribution de SpotterEnginer (comme celui d'AdvancedIA) : seulement ce que le jeu charge (point d'entrée,
manifeste, icône, modules, signal radio, voix, polices) et les notices du pilote, sous apps/lua/SpotterEnginer/ ;
SpotterEnginer-<version>.zip et son empreinte SpotterEnginer-<version>.sha256 (« <sha256>  <nom du zip> »). Les tests,
les outils et la documentation technique n'y sont jamais.
Le paquet est ensuite contrôlé par le vrai module de mise à jour (src/update.lua, sous lupa), comme l'app le fera :
chemins sûrs, fichiers indispensables, modules requis, version du manifeste, nom accepté par M.release, taille bornée
(avec une marge : la borne est celle des versions déjà installées), pont compatible avec AdvancedIA installé. Chaque
module Lua du paquet est compilé et les deux modules de la mise à jour sont chargés (contrat de démarrage du haut de
SpotterEnginer.lua) : une version dont ces modules ne se chargent pas ne pourrait ni se défaire ni se mettre à jour.
Rien n'est écrit dans le dossier de l'app (CSP la recharge en jeu dès qu'un de ses fichiers change) : paquet dans le
dossier temporaire par défaut, dossier de sortie refusé s'il est dans l'app.
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
# Part de M.sizeMax (src/update.lua) qu'un paquet peut atteindre : au-delà, les versions déjà installées (qui portent
# leur propre borne) seraient bientôt incapables de l'installer seules ; relever la borne ne les atteint pas.
SIZE_MARGIN = 0.8


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("local p=... ; package.path=p..'/?.lua;'..package.path", APP.as_posix())
    return lua


def collect():
    files = [APP / name for name in ['SpotterEnginer.lua', 'manifest.ini', 'icon.png', *NOTICES]]
    for folder, patterns in [('src', ['*.lua']), ('sounds', ['*.wav']), ('vox', ['*/*.wav', '*/*/*.wav', '*/*/*/*.wav']), ('fonts', ['*/*.ttf', '*/OFL.txt'])]:
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
    out = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.gettempdir()) / 'SpotterEnginer-dist').resolve()
    assert out != APP and APP not in out.parents, f'dossier de sortie dans le dossier de l\'app (rechargée en jeu) : {out}'
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
    assert up.content(entries), 'contenu refusé (chemins, doublons à la casse près ou fichiers indispensables)'
    # Fichier vide : la comparaison du paquet extrait ne saurait pas le distinguer d'une lecture en échec.
    empty = [n for n in names if not n.endswith('/') and not texts[n]]
    assert not empty, f'fichiers vides : {empty}'
    size = zip_path.stat().st_size
    assert size <= SIZE_MARGIN * up.sizeMax, f'paquet de {size} octets : plus de {SIZE_MARGIN:.0%} de la borne des versions installées ({int(up.sizeMax)})'
    modules(lua, names, texts)

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
    print('contrôles de l\'app : contenu, modules compilés, contrat de démarrage, version, nom, taille, empreinte, pont'
          + (' (AdvancedIA installé)' if companion else ''))


def modules(lua, names, texts):
    """Chaque module Lua du paquet se compile, et les deux modules de la mise à jour se chargent et tiennent le contrat de
    démarrage. lupa embarque ici Lua 5.5, pas le LuaJIT de CSP : la compilation attrape les fautes de syntaxe communes
    aux deux, pas une écriture propre à Lua 5.3+ que LuaJIT refuserait (les tests ne la voient pas non plus)."""
    compile_ = lua.eval("function(text,name) local f,e=load(text,'@'..name); return e or '' end")
    bad = [e for e in (compile_(texts[n].decode('utf-8'), n) for n in names if n.endswith('.lua')) if e]
    assert not bad, f'modules qui ne se compilent pas : {bad}'
    for rel in ('src/update.lua', 'src/remote.lua'):
        assert texts[PREFIX + rel] == (APP / rel).read_bytes(), f'{rel} du paquet différent de celui chargé ici'
    why = lua.eval("""(function()
      local okU,Update=pcall(require,'src/update'); if not okU or type(Update)~='table' then return 'src/update : '..tostring(Update) end
      local okR,Remote=pcall(require,'src/remote'); if not okR or type(Remote)~='table' then return 'src/remote : '..tostring(Remote) end
      if type(Update.recover)~='function' or type(Update.recoverText)~='function' or type(Remote.new)~='function' then return 'Update.recover, Update.recoverText ou Remote.new absent' end
      local okP,port=pcall(Remote.new,function() end)
      if not okP or type(port)~='table' then return 'Remote.new : '..tostring(port) end
      if port.ready~=false then return 'port actif hors de CSP' end
      for _,name in ipairs({'restart','log','bootOk'}) do if type(port[name])~='function' then return 'port.'..name..' absent' end end
      if port.work~=nil and type(port.work)~='string' then return 'port.work' end
      local okV,r=pcall(Update.recover,port); if not okV or r~=nil then return 'Update.recover(port inerte) : '..tostring(r) end
      return ''
    end)()""")
    assert why == '', f'contrat de démarrage : {why}'


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    main()
