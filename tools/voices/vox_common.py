# Commun aux générateurs de répliques (tools/voices/make_voices.py, Chatterbox ;
# tools/voices/qwen_clone.py, Qwen3-TTS) : texte prêt pour la synthèse, nettoyage
# du son et encodage Ogg Vorbis. Ne dépend que de numpy et soundfile (présents
# dans les deux environnements Python de tools/tts/).
import math, os, re

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TTS = os.path.join(ROOT, "tools", "tts")

NUM = {"fr": ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix"],
       "en": ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]}


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


def write_ogg(x, sr, path, compression=None):
    """compression : niveau libsndfile de 0 (meilleure qualité) à 1 ; None = défaut
    (qualité Vorbis moyenne, qui lisse un peu le souffle d'une voix éraillée)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if compression is None:
        sf.write(path, x, sr, format="OGG", subtype="VORBIS")
    else:
        sf.write(path, x, sr, format="OGG", subtype="VORBIS", compression_level=float(compression))


def load_cast():
    import json
    return json.load(open(os.path.join(ROOT, "tools", "voices", "cast.json"), encoding="utf-8"))["characters"]


def load_lines(ch):
    import json
    return json.load(open(os.path.join(ROOT, "assets", "voices", ch + ".json"), encoding="utf-8"))["lines"]
