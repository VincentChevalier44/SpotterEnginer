"""Génère les clips de voix de SpotterEnginer avec la même voix que les clips d'origine (script generer_voix.py des
voix FIA) : edge-tts, voix fr-FR-HenriNeural et en-US-GuyNeural. La liste, les textes exacts, les langues, les
sous-dossiers et leurs bornes viennent de src/catalog.lua (clips 01 à 34 d'origine, clips 35 et plus, nombres dans
vox/<LANGUE>/num/, durées dans vox/<LANGUE>/sec/, positions « Tu es P7 » dans vox/<LANGUE>/pos/) ; les durées sont
écrites par la même fonction que la radio (Say.secondsText).
Format, choisi pour la place et la clarté : MP3 VBR (LAME V9), 24 kHz mono, silences de début et de fin retirés, un
seul encodage livré depuis la sortie d'edge-tts. Fichiers nommés .wav comme les clips d'origine (le moteur audio d'AC
reconnaît le format au contenu).
Effet radio (demande du 09/11/2026, intensité « léger » choisie à l'écoute) : bande de la radio 300 à 3 400 Hz, médium
présent, légère saturation, avant la mesure du niveau.
Niveau : chaque clip est légèrement compressé, filtré (radio), amené à FINAL_RMS (environ -14 LUFS) mesuré après
encodage sans les silences de bord, puis limité ; la crête vraie du fichier livré ne dépasse jamais PEAK_MAX (marge
pour les crêtes que l'encodage MP3 recrée). Sans ffmpeg, les clips restent tels qu'edge-tts les rend.
Signal d'ouverture de la radio (Catalog.toneFile, joué par l'app au début de chaque transmission) : tonalité numérique
de deux notes brèves (85 ms) suivie de 45 ms de blanc.

Le jeu doit être fermé : les clips sont écrits dans le dossier de l'app (vox/, sounds/), que CSP recharge en jeu à chaque
fichier changé. Chaque clip est écrit à côté (.tmp) puis mis en place d'un seul coup : une interruption ne laisse jamais
un clip tronqué, qui passerait ensuite pour présent.
Nécessite une connexion (service de synthèse de Microsoft Edge), Python avec edge-tts et lupa.
Voix du spotter (1.3.9, choix du pilote) : voix féminine de Catalog.femaleVoices (Denise, Jenny) pour les clips
du spotter seul (Catalog.spotterOnly, à leur place) et pour la copie féminine des clips communs, nombres, durées et
positions (vox/<LANGUE>/F/…) ; l'ingénieur garde la voix masculine.
Usage :  python tools/generer_voix.py            (seulement les clips absents, et le signal s'il manque)
         python tools/generer_voix.py --feminin  (refaire en voix féminine les clips du spotter seul déjà présents)
         python tools/generer_voix.py --force    (refaire les clips 35 et plus, nombres, durées, positions, signal)
         python tools/generer_voix.py --tout     (tout refaire, clips 01 à 34 compris)
"""
from pathlib import Path
import asyncio
import os
import re
import shutil
import subprocess
import sys
import tempfile

import edge_tts
from lupa import LuaRuntime

APP = Path(__file__).resolve().parents[1]
VOICES = {'FR': 'fr-FR-HenriNeural', 'EN': 'en-US-GuyNeural'}
FFMPEG = shutil.which('ffmpeg')
TRIM = ('silenceremove=start_periods=1:start_duration=0:start_threshold=-50dB:start_silence=0.02,areverse,'
        'silenceremove=start_periods=1:start_duration=0:start_threshold=-50dB:start_silence=0.06,areverse')


ENCODE = ['-ar', '24000', '-ac', '1', '-c:a', 'libmp3lame', '-q:a', '9']
# Pauses internes (edge-tts met environ 1 s après un point) ramenées à 0,25 s : l'information suit sans blanc.
PAUSE = 'silenceremove=stop_periods=-1:stop_duration=0.15:stop_threshold=-45dB:stop_silence=0.1'
COMP = 'acompressor=threshold=0.063:ratio=3:attack=5:release=80:knee=2'
RADIO = ('highpass=f=300:poles=2,lowpass=f=3400:poles=2,equalizer=f=1700:t=q:w=1.2:g=3,'
         'volume=4dB,asoftclip=type=tanh,volume=-4dB')
LIMIT = 'alimiter=limit=0.72:attack=2:release=40:level=false'
# Premier gain : niveau moyen avant encodage visé (le limiteur en mange une partie, corrigée ensuite).
TARGET_RMS = -13.0
# Niveau moyen visé après encodage (celui des clips d'avant l'effet radio, environ -14 LUFS) et crête vraie maximale.
FINAL_RMS = -14.0
PEAK_MAX = -0.5
# Mesure du niveau sans aucun silence de bord (sinon les clips courts, « un », paraissent plus faibles).
MEASURE = TRIM.replace('start_silence=0.02', 'start_silence=0').replace('start_silence=0.06', 'start_silence=0')


def deliver(source, target):
    """Clip mis en place d'un seul coup : copié à côté (.tmp, même dossier), puis renommé."""
    tmp = target.with_name(target.name + '.tmp')
    try:
        shutil.copyfile(source, tmp)
        os.replace(tmp, target)
    finally:
        tmp.unlink(missing_ok=True)


def mean_volume(path, chain):
    """Niveau moyen (dBFS) du clip après la chaîne donnée, ou None."""
    r = subprocess.run([FFMPEG, '-hide_banner', '-nostats', '-i', str(path), '-af', chain + ',volumedetect', '-f', 'null', '-'],
                       capture_output=True, text=True)
    found = re.findall(r'mean_volume: (-?[\d.]+) dB', r.stderr)
    return float(found[-1]) if found else None


def true_peak(path):
    """Crête vraie (dBTP) d'un fichier, ou None."""
    r = subprocess.run([FFMPEG, '-hide_banner', '-nostats', '-i', str(path), '-af', 'ebur128=peak=true:framelog=quiet', '-f', 'null', '-'],
                       capture_output=True, text=True)
    found = re.findall(r'Peak:\s+(-?[\d.]+) dBFS', r.stderr)
    return float(found[-1]) if found else None


# Écarts lus vite (demande du 04/11/2026 : « 9,3 secondes » trop lent) : nombre et unité en un seul clip, et débit un peu
# plus rapide pour les mots des écarts.
FAST = '+10%'
FAST_CLIPS = {'gapAhead', 'gapBehind', 'andBehind'}
# Ton du clip (1.3.0, src/catalog.lua : tone) : débit et hauteur d'edge-tts (rate, pitch), la même voix ; le niveau
# reste celui de tous les clips (FINAL_RMS). Aucun style SSML (non pris par ces voix) : le ton tient à la formulation et
# à la prosodie. Neutre : rien de changé (clips d'avant 1.3.0 identiques).
TONES = {
    'neutral': (None, None),
    'calm': ('-4%', '-2Hz'),
    'urgent': ('+14%', '+4Hz'),
    'motivating': ('+7%', '+3Hz'),
    'frustrated': ('-6%', '-4Hz'),
}


def runtime():
    lua = LuaRuntime()
    lua.execute("local p=... ; package.path=p..'/?.lua;'..package.path", APP.as_posix())
    return lua


def catalog(everything=False):
    lua = runtime()
    cat = lua.eval("(require('src/catalog'))")
    say = lua.eval("(require('src/say'))")
    languages = [cat.languages[k] for k in range(1, len(cat.languages) + 1)]
    assert set(languages) == set(VOICES), 'une voix edge-tts par langue du catalogue'
    jobs = []
    order = cat.order
    female = {str(k): str(v) for k, v in cat.femaleVoices.items()}
    spotter = {cat.spotterOnly[k] for k in range(1, len(cat.spotterOnly) + 1)}
    shared = {cat.shared[k] for k in range(1, len(cat.shared) + 1)}
    fdir = str(cat.femaleDir)
    # Chaque clip : (langue, fichier, texte, refait par --force, débit) ; un clip absent est toujours généré. Les clips
    # d'origine 01 à 34 ne sont refaits que par --tout.
    for lang in languages:
        for k in range(1, len(order) + 1):
            c = cat.clips[order[k]]
            rate, pitch = TONES[c.tone]
            rate = FAST if order[k] in FAST_CLIPS else rate
            # Clip du spotter seul : voix féminine à sa place (refaite par --feminin) ; clip commun : voix masculine à
            # sa place et féminine dans F/.
            own = order[k] in spotter
            jobs.append((lang, c[lang], c['text' + lang], everything or not c.shipped, rate, pitch,
                         female[lang] if own else VOICES[lang], own))
            if order[k] in shared:
                jobs.append((lang, fdir + c[lang], c['text' + lang], True, rate, pitch, female[lang], True))
        numbers = []
        for n in range(int(cat.maxNumber) + 1):
            numbers.append((cat.numberFile(n), str(n), None))
        for n in range(int(cat.maxTenths) + 1):
            numbers.append((cat.secondsFile(n), say.secondsText(lang, n / 10, 1 if n % 10 else 0), FAST))
        # Positions « Tu es P7 » (écrit « Pé 7 » pour edge-tts en français : « P7 » y est mal prononcé).
        for n in range(1, int(cat.maxPosition) + 1):
            numbers.append((cat.positionFile(n), cat.positionSpoken(lang, n), FAST))
        for name, text, rate in numbers:
            jobs.append((lang, name, text, True, rate, None, VOICES[lang], False))
        for name, text, rate in numbers:
            jobs.append((lang, fdir + name, text, True, rate, None, female[lang], True))
    assert len(jobs) == int(cat.fileCount()), 'un travail par fichier attendu'
    return jobs, str(cat.toneFile)


def radio_tone(rel, force):
    """Signal d'ouverture de la radio : deux notes brèves (1 750 puis 2 350 Hz), 45 ms de blanc."""
    target = APP / rel
    if not FFMPEG or target.exists() and not force:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        made = Path(tmp) / 'tone.wav'
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y',
                        '-f', 'lavfi', '-i', 'sine=f=1750:d=0.04:r=24000', '-f', 'lavfi', '-i', 'sine=f=2350:d=0.045:r=24000',
                        '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono:d=0.045', '-filter_complex',
                        '[0][1][2]concat=n=3:v=0:a=1,afade=t=in:d=0.004,highpass=f=300,lowpass=f=3400,volume=4dB[a]',
                        '-map', '[a]', '-ac', '1', '-c:a', 'pcm_s16le', str(made)], check=True)
        deliver(made, target)
    print(f"  {rel}  (signal d'ouverture)")


def encode(raw, chain, out, tmp):
    """Encode raw au niveau FINAL_RMS, crête vraie au plus PEAK_MAX ; le meilleur encodage qui respecte la crête est
    copié dans out. Gain corrigé après chaque mesure, jamais au-dessus d'un gain déjà trouvé trop fort (pas
    d'oscillation) ; au plus 8 encodages. Renvoie False si aucun ne respecte la crête."""
    mean = mean_volume(raw, chain)
    gain = 0.0 if mean is None else max(-6.0, min(20.0, TARGET_RMS - mean))
    hot = None          # plus petit gain trouvé trop fort (crête)
    best = None         # (écart de niveau, gain) du meilleur encodage qui passe
    trial = Path(tmp) / 'trial.mp3'
    for _ in range(8):
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(raw), '-af',
                        f'{chain},volume={gain:.2f}dB,{LIMIT}', *ENCODE, '-f', 'mp3', str(trial)], check=True)
        peak = true_peak(trial)
        if peak is not None and peak > PEAK_MAX:
            hot = gain if hot is None else min(hot, gain)
            gain -= peak - PEAK_MAX + 0.1
            continue
        got = mean_volume(trial, MEASURE)
        error = 0.0 if got is None else abs(got - FINAL_RMS)
        if best is None or error < best[0]:
            best = (error, gain)
            shutil.copyfile(trial, out)
        if got is None or error < 0.4:
            break
        wanted = gain + FINAL_RMS - got
        if hot is not None and wanted >= hot - 0.05:
            wanted = (gain + hot) / 2
        if abs(wanted - gain) < 0.05:
            break
        gain = min(26.0, wanted)
    return best is not None


async def one(lang, name, text, redo, rate, pitch, voice_name, femaleNow, force, sem, report):
    target = APP / 'vox' / lang / name
    if target.exists() and not (force and redo) and not femaleNow:
        report['skipped'] += 1
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    async with sem:
        for attempt in range(4):
            try:
                with tempfile.TemporaryDirectory() as tmp:
                    raw = Path(tmp) / 'raw.mp3'
                    voice = edge_tts.Communicate(text, voice_name, rate=rate or '+0%', pitch=pitch or '+0Hz')
                    await voice.save(str(raw))
                    if FFMPEG:
                        out = Path(tmp) / 'clip.mp3'
                        if not encode(raw, TRIM + ',' + PAUSE + ',' + COMP + ',' + RADIO, out, tmp):
                            raise RuntimeError(f'crête au-dessus de {PEAK_MAX} dBTP')
                        deliver(out, target)
                    else:
                        deliver(raw, target)
                report['done'] += 1
                print(f'  {lang}/{name}  «{text}»')
                return
            except Exception as e:  # noqa: BLE001
                if attempt == 3:
                    report['failed'].append(f'{lang}/{name}: {e}')
                await asyncio.sleep(1.5 * (attempt + 1))


async def main(force, everything, feminin=False):
    jobs, tone = catalog(everything)
    # --feminin : les clips du spotter seul déjà présents (voix masculine d'avant 1.3.9) sont refaits.
    jobs = [(l, n, t, r, ra, p, v, own and feminin) for l, n, t, r, ra, p, v, own in jobs]
    radio_tone(tone, force)
    report = {'done': 0, 'skipped': 0, 'failed': []}
    sem = asyncio.Semaphore(4)
    await asyncio.gather(*(one(lang, name, text, redo, rate, pitch, voice, again, force, sem, report)
                           for lang, name, text, redo, rate, pitch, voice, again in jobs))
    print(f"\n{report['done']} clips générés, {report['skipped']} déjà présents, {len(report['failed'])} en échec")
    for f in report['failed']:
        print('  ÉCHEC', f)
    if not FFMPEG:
        print('ffmpeg introuvable : silences non retirés.')
    return 1 if report['failed'] else 0


if __name__ == '__main__':
    everything = '--tout' in sys.argv
    sys.exit(asyncio.run(main('--force' in sys.argv or everything, everything, '--feminin' in sys.argv)))
