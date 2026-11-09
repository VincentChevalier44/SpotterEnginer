"""Copie de travail git de SpotterEnginer, tenue hors du dossier de l'app (git y écrit à chaque commande : CSP rechargerait
l'app en jeu) : recopie le dossier de l'app dans la copie de travail, fichier par fichier, sans les fichiers ignorés
(.gitignore de l'app), et retire de la copie ce qui n'existe plus dans l'app (jamais .git). Rien n'est écrit dans le
dossier de l'app.
Usage : python tools/sync_repo.py <copie de travail>     (par exemple C:/Users/<vous>/Documents/GitHub/SpotterEnginer)
Ensuite, dans la copie : git status, git add -A, git commit, git push."""
from pathlib import Path
import fnmatch
import shutil
import sys

APP = Path(__file__).resolve().parents[1]


def ignored_patterns():
    out = []
    for line in (APP / '.gitignore').read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            out.append(line)
    return out


def ignored(rel, patterns):
    parts = rel.split('/')
    for pat in patterns:
        if pat.endswith('/'):
            if pat[:-1] in parts[:-1]:
                return True
        elif fnmatch.fnmatch(parts[-1], pat) or fnmatch.fnmatch(rel, pat):
            return True
    return False


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    repo = Path(sys.argv[1]).resolve()
    assert (repo / '.git').is_dir(), f'pas une copie de travail git : {repo}'
    assert APP not in repo.parents and repo != APP, 'la copie de travail doit être hors du dossier de l\'app'
    patterns = ignored_patterns()
    wanted = {}
    for p in APP.rglob('*'):
        if p.is_file():
            rel = p.relative_to(APP).as_posix()
            if not ignored(rel, patterns):
                wanted[rel] = p
    copied = removed = 0
    for rel, src in sorted(wanted.items()):
        dst = repo / rel
        if not dst.exists() or dst.read_bytes() != src.read_bytes():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            copied += 1
    for p in sorted(repo.rglob('*'), reverse=True):
        rel = p.relative_to(repo).as_posix()
        if rel == '.git' or rel.startswith('.git/'):
            continue
        if p.is_file() and rel not in wanted and not ignored(rel, patterns):
            p.unlink()
            removed += 1
        elif p.is_dir() and not any(p.iterdir()):
            p.rmdir()
    print(f'{len(wanted)} fichiers suivis, {copied} copiés, {removed} retirés -> {repo}')
    return 0


if __name__ == '__main__':
    sys.dont_write_bytecode = True
    sys.exit(main())
