"""Copie de travail git de SpotterEnginer, tenue hors du dossier de l'app (git y écrit à chaque commande : CSP rechargerait
l'app en jeu) : recopie le dossier de l'app dans la copie de travail, fichier par fichier, sans les fichiers ignorés
(.gitignore de l'app), et retire de la copie ce qui n'existe plus dans l'app. Rien n'est écrit dans le dossier de l'app.
Garde-fous (un autre dépôt passé par erreur serait vidé) :
- la cible doit être le dépôt de SpotterEnginer : son manifest.ini porte NAME=SpotterEnginer, ou elle est vide (rien
  d'autre que .git*, premier envoi) ; sinon rien n'est écrit ;
- jamais retirés : .git, tout ce dont le nom commence par .git à la racine (.gitattributes, .github/…) et les fichiers
  propres au dépôt, listés dans .syncrepo-keep à sa racine (un motif par ligne, comme .gitignore ; « dossier/ » garde
  tout un dossier) ;
- --dry-run : dit ce qui serait copié et retiré, sans rien écrire.
Usage : python tools/sync_repo.py <copie de travail> [--dry-run]
        (par exemple C:/Users/<vous>/Documents/GitHub/SpotterEnginer)
Ensuite, dans la copie : git status, git add -A, git commit, git push."""
from pathlib import Path
import fnmatch
import shutil
import sys

APP = Path(__file__).resolve().parents[1]
NAME = 'SpotterEnginer'
KEEP_FILE = '.syncrepo-keep'


def patterns_of(path):
    if not path.is_file():
        return []
    lines = (line.strip() for line in path.read_text(encoding='utf-8').splitlines())
    return [line for line in lines if line and not line.startswith('#')]


def matches(rel, patterns):
    parts = rel.split('/')
    for pat in patterns:
        if pat.endswith('/'):
            if pat[:-1] in parts[:-1]:
                return True
        elif fnmatch.fnmatch(parts[-1], pat) or fnmatch.fnmatch(rel, pat):
            return True
    return False


def manifest_name(path):
    """NAME du manifeste (section [ABOUT]), ou None."""
    if not path.is_file():
        return None
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        key, sep, value = line.partition('=')
        if sep and key.strip() == 'NAME':
            return value.strip()
    return None


def git_owned(rel):
    """.git, .gitattributes, .github/… : à git et au dépôt, jamais à l'app (.gitignore, lui, vient de l'app)."""
    return rel.split('/')[0].startswith('.git') and rel != '.gitignore'


def main():
    args = [a for a in sys.argv[1:] if a != '--dry-run']
    dry = '--dry-run' in sys.argv[1:]
    if len(args) != 1:
        print(__doc__)
        return 2
    repo = Path(args[0]).resolve()
    assert (repo / '.git').is_dir(), f'pas une copie de travail git : {repo}'
    assert APP not in repo.parents and repo != APP, 'la copie de travail doit être hors du dossier de l\'app'
    assert repo not in APP.parents, f'le dossier de l\'app est dans cette copie de travail : {repo}'
    assert manifest_name(APP / 'manifest.ini') == NAME, 'manifest.ini de l\'app : NAME inattendu'
    found = manifest_name(repo / 'manifest.ini')
    blank = all(p.name.startswith('.git') for p in repo.iterdir())
    assert found == NAME or blank, (f'{repo} n\'est pas le dépôt de {NAME} (manifest.ini : NAME={found}) et n\'est pas vide : '
                                    'rien n\'est écrit')
    ignore = patterns_of(APP / '.gitignore')
    keep = patterns_of(repo / KEEP_FILE)
    wanted = {}
    for p in APP.rglob('*'):
        if p.is_file():
            rel = p.relative_to(APP).as_posix()
            if not matches(rel, ignore) and not git_owned(rel):
                wanted[rel] = p
    copied = removed = 0
    for rel, src in sorted(wanted.items()):
        dst = repo / rel
        if not dst.exists() or dst.read_bytes() != src.read_bytes():
            if dry:
                print('  copierait', rel)
            else:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)
            copied += 1
    for p in sorted(repo.rglob('*'), reverse=True):
        rel = p.relative_to(repo).as_posix()
        if git_owned(rel) or rel == KEEP_FILE or matches(rel, keep) or matches(rel + '/', keep):
            continue
        if p.is_file() and rel not in wanted and not matches(rel, ignore):
            if dry:
                print('  retirerait', rel)
            else:
                p.unlink()
            removed += 1
        elif p.is_dir() and not dry and not any(p.iterdir()):
            p.rmdir()
    print(f'{len(wanted)} fichiers suivis, {copied} {"à copier" if dry else "copiés"}, {removed} {"à retirer" if dry else "retirés"} -> {repo}'
          + (' (essai : rien d\'écrit)' if dry else ''))
    return 0


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    sys.exit(main())
