# Génère les répliques vocales des personnages (docs/CHARACTERS.md) :
#   1. une voix de référence synthétique par personnage avec Kokoro-82M
#      (Apache 2.0 ; aucune voix de personne réelle n'est clonée) ;
#   2. chaque réplique, en français et en anglais, avec Chatterbox Multilingual
#      (MIT, Resemble AI ; même voix dans les deux langues, expressivité réglable) ;
#   3. nettoyage, niveau et encodage Ogg Vorbis.
#
#   tools/tts/.venv/Scripts/python.exe tools/voices/make_voices.py [--lang fr|en] [--only callahan,orlov] [--sample N] [--out DOSSIER] [--refs]
#
# - textes : assets/voices/<personnage>.json ; réglages : tools/voices/cast.json ;
# - environnement (Python, PyTorch, modèles) : tools/tts/ (hors git, voir docs/ASSETS.md) ;
# - sortie : assets/audio/vox/<langue>/<personnage>/<catégorie>_<n>.ogg ;
# - --sample N : N répliques par personnage et un fichier d'écoute par langue ;
# - --refs : régénère les voix de référence (tools/tts/refs/<personnage>.wav).
import hashlib, json, math, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TTS = os.path.join(ROOT, "tools", "tts")
os.environ.setdefault("HF_HOME", os.path.join(TTS, "hf"))

import numpy as np
import soundfile as sf
import torch

NUM = {"fr": ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix"],
       "en": ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]}


def args():
    a = sys.argv[1:]
    opt = {"lang": None, "only": None, "sample": 0, "out": os.path.join(ROOT, "assets", "audio", "vox"), "refs": False}
    i = 0
    while i < len(a):
        k = a[i].lstrip("-")
        if k == "refs":
            opt["refs"] = True
            i += 1
            continue
        opt[k] = a[i + 1]
        i += 2
    opt["sample"] = int(opt["sample"])
    return opt


def speakable(text, lang):
    """Texte prêt pour la synthèse : noms en majuscules en casse normale (sinon
    épelés), chiffres en toutes lettres."""
    def cap(m):
        return "-".join(p.capitalize() for p in m.group(0).split("-"))
    text = re.sub(r"\b[A-ZÀ-Ý][A-ZÀ-Ý&'-]{2,}\b", cap, text)

    def num(m):
        n = int(m.group(2))
        w = NUM[lang][n] if n <= 10 else m.group(2)
        return m.group(1) + (w.capitalize() if m.group(1) == "-" else w)
    return re.sub(r"(-?)(\d+)", num, text)


def shift(x, semitones):
    """Décalage de hauteur par relecture (la durée change aussi : sans
    importance pour une voix de référence)."""
    p = 2 ** (semitones / 12.0)
    if abs(p - 1.0) < 1e-3:
        return x
    n = int(len(x) / p)
    return np.interp(np.arange(n) * p, np.arange(len(x)), x).astype(np.float32)


def make_ref(ch, spec, path):
    from kokoro import KPipeline
    voice = spec["kokoro"]
    pipe = KPipeline(lang_code="b" if voice.startswith("b") else "a", repo_id="hexgrad/Kokoro-82M")
    parts = [np.asarray(audio, dtype=np.float32) for _, _, audio in pipe(spec["ref"], voice=voice, speed=1.0)]
    x = shift(np.concatenate(parts), spec.get("ref_semitones", 0.0))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, x, 24000)
    print("[vox] référence %s : %s, %.1f s" % (ch, voice, len(x) / 24000))


def process(x, sr):
    """Silences coupés, passe-haut léger, niveau des parties parlées à -19 dBFS,
    crêtes adoucies, fondus."""
    env = np.convolve(np.abs(x), np.ones(256) / 256, "same")
    idx = np.where(env > 10 ** (-45 / 20))[0]
    if len(idx):
        pad = int(0.03 * sr)
        x = x[max(0, idx[0] - pad):min(len(x), idx[-1] + pad)]
    n = 1 << int(math.ceil(math.log2(len(x) + 1024)))
    f = np.fft.rfftfreq(n, 1 / sr)
    g = 1.0 / np.sqrt(1.0 + (80.0 / np.maximum(f, 1.0)) ** 4)
    x = np.fft.irfft(np.fft.rfft(x, n) * g, n)[:len(x)].astype(np.float32)
    frame = int(0.05 * sr)
    rms = np.sqrt(np.convolve(x * x, np.ones(frame) / frame, "same"))
    speech = rms > np.max(rms) * 0.1
    level = np.sqrt(np.mean(x[speech] ** 2)) if np.any(speech) else 1e-3
    x = x * (10 ** (-19 / 20) / max(level, 1e-4))
    x = np.tanh(x * 1.2) / np.tanh(1.2)
    fade = int(0.012 * sr)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return np.clip(x, -0.98, 0.98).astype(np.float32)


def write_ogg(x, sr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, x, sr, format="OGG", subtype="VORBIS")


def main():
    opt = args()
    cast = json.load(open(os.path.join(ROOT, "tools", "voices", "cast.json"), encoding="utf-8"))["characters"]
    langs = [opt["lang"]] if opt["lang"] else ["fr", "en"]
    chars = opt["only"].split(",") if opt["only"] else list(cast.keys())
    refs = {}
    for ch in chars:
        refs[ch] = os.path.join(TTS, "refs", ch + ".wav")
        if opt["refs"] or not os.path.exists(refs[ch]):
            make_ref(ch, cast[ch], refs[ch])
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS
    model = ChatterboxMultilingualTTS.from_pretrained(device="cuda" if torch.cuda.is_available() else "cpu")
    sr = model.sr
    t0 = time.time()
    total = 0
    for lang in langs:
        preview = []
        for ch in chars:
            spec = cast[ch]
            lines = json.load(open(os.path.join(ROOT, "assets", "voices", ch + ".json"), encoding="utf-8"))["lines"]
            jobs = [(cat, i, speakable(v[lang], lang)) for cat, vs in lines.items() for i, v in enumerate(vs)]
            if opt["sample"]:
                step = max(1, len(jobs) // opt["sample"])
                jobs = jobs[::step][:opt["sample"]]
            model.prepare_conditionals(refs[ch], exaggeration=spec["exaggeration"])
            for cat, i, text in jobs:
                out = os.path.join(opt["out"], lang, ch, "%s_%d.ogg" % (cat, i))
                if not opt["sample"] and os.path.exists(out):
                    continue  # reprise d'une génération interrompue
                # Graine fixe par réplique : une régénération donne le même résultat.
                torch.manual_seed(int(hashlib.md5(("%s/%s/%s/%d" % (lang, ch, cat, i)).encode()).hexdigest()[:8], 16))
                wav = model.generate(text, language_id=lang, exaggeration=spec["exaggeration"],
                                     cfg_weight=spec["cfg"], temperature=spec["temperature"])
                y = process(wav.squeeze(0).cpu().numpy().astype(np.float32), sr)
                write_ogg(y, sr, out)
                if opt["sample"]:
                    preview += [y, np.zeros(int(0.45 * sr), np.float32)]
                total += 1
            print("[vox] %s %s : %d répliques (%.0f s)" % (lang, ch, len(jobs), time.time() - t0), flush=True)
        if opt["sample"] and preview:
            # Fichier d'écoute en WAV : libsndfile plante sur les longs Ogg Vorbis.
            sf.write(os.path.join(opt["out"], "ecoute_%s.wav" % lang), np.concatenate(preview), sr)
    print("[vox] %d fichiers -> %s" % (total, opt["out"]))


main()
