# Génère les répliques vocales des personnages (docs/CHARACTERS.md). Deux moteurs,
# choisis par personnage dans tools/voices/cast.json (clé "engine") :
#
# - "chatterbox" (défaut ; Callahan, Orlov, Arakawa, Weissmann) :
#   1. une voix de référence synthétique par personnage avec Kokoro-82M
#      (Apache 2.0 ; aucune voix de personne réelle n'est clonée) ;
#   2. chaque réplique, en français et en anglais, avec Chatterbox Multilingual
#      (MIT, Resemble AI ; même voix dans les deux langues, expressivité réglable) ;
# - "qwen_clone" (Mercer) : clonage Qwen3-TTS 1.7B-Base d'une référence par
#   langue, dans un autre environnement Python : ce script délègue alors à
#   tools/voices/qwen_clone.py (voir son en-tête) ;
#
# puis, pour tous : nettoyage, niveau et encodage Ogg Vorbis (vox_common.py).
#
#   tools/tts/.venv/Scripts/python.exe tools/voices/make_voices.py [--lang fr|en] [--only callahan,orlov]
#       [--category idle,hurt] [--sample N] [--out DOSSIER] [--refs] [--force]
#
# - textes : assets/voices/<personnage>.json ; réglages : tools/voices/cast.json ;
# - environnement (Python, PyTorch, modèles) : tools/tts/ (hors git, voir docs/ASSETS.md) ;
# - sortie : assets/audio/vox/<langue>/<personnage>/<catégorie>_<n>.ogg ;
# - les fichiers existants sont gardés (reprise) sauf avec --force ;
# - --category : seulement ces catégories (ex. une nouvelle catégorie de taquinerie) ;
# - --sample N : N répliques par personnage et un fichier d'écoute par langue ;
# - --refs : régénère les voix de référence Kokoro (tools/tts/refs/<personnage>.wav).
import hashlib, os, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_common import ROOT, TTS, speakable, process, write_ogg, load_cast, load_lines  # noqa: E402

os.environ.setdefault("HF_HOME", os.path.join(TTS, "hf"))

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402

QWEN_PY = os.path.join(TTS, "qwen3tts", "Scripts", "python.exe")


def args():
    a = sys.argv[1:]
    opt = {"lang": None, "only": None, "category": None, "sample": 0,
           "out": os.path.join(ROOT, "assets", "audio", "vox"), "refs": False, "force": False}
    i = 0
    while i < len(a):
        k = a[i].lstrip("-")
        if k in ("refs", "force"):
            opt[k] = True
            i += 1
            continue
        opt[k] = a[i + 1]
        i += 2
    opt["sample"] = int(opt["sample"])
    return opt


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


def synth(model, text, lang, spec, key):
    """Synthèse d'une réplique, graine fixe par réplique (une régénération donne le
    même résultat). Chatterbox échoue parfois sur les cris très courts (« Back! ») :
    autres graines, puis texte légèrement allongé (points de suspension, répétition)."""
    import torch
    base = int(hashlib.md5(key.encode()).hexdigest()[:8], 16)
    for attempt, t in enumerate([text, text, text, text.rstrip("!.?") + "...", text + " " + text]):
        torch.manual_seed(base + attempt)
        try:
            wav = model.generate(t, language_id=lang, exaggeration=spec["exaggeration"],
                                 cfg_weight=spec["cfg"], temperature=spec["temperature"])
        except Exception as e:  # erreur de l'aligneur sur les textes minuscules
            print("[vox] essai %d en échec pour %r : %s" % (attempt + 1, t, e), flush=True)
            continue
        if wav is not None and wav.numel() > 2400:
            if attempt:
                print("[vox] %r obtenu à l'essai %d (%r)" % (text, attempt + 1, t), flush=True)
            return wav
    return None


def run_qwen(chars, opt):
    """Personnages clonés avec Qwen3-TTS : autre venv, autre script."""
    cmd = [QWEN_PY, os.path.join(ROOT, "tools", "voices", "qwen_clone.py"), "--only", ",".join(chars)]
    for k in ("lang", "category", "out"):
        if opt[k]:
            cmd += ["--" + k, str(opt[k])]
    if opt["sample"]:
        cmd += ["--sample", str(opt["sample"])]
    if opt["force"]:
        cmd += ["--force"]
    print("[vox] Qwen3-TTS : %s" % " ".join(cmd), flush=True)
    return subprocess.call(cmd)


def main():
    opt = args()
    cast = load_cast()
    langs = [opt["lang"]] if opt["lang"] else ["fr", "en"]
    cats = set(opt["category"].split(",")) if opt["category"] else None
    chars = opt["only"].split(",") if opt["only"] else list(cast.keys())
    qwen = [ch for ch in chars if cast[ch].get("engine", "chatterbox") == "qwen_clone"]
    chars = [ch for ch in chars if ch not in qwen]
    if not chars:
        sys.exit(run_qwen(qwen, opt) if qwen else 0)
    import torch
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
            lines = load_lines(ch)
            jobs = [(cat, i, speakable(v[lang], lang)) for cat, vs in lines.items() for i, v in enumerate(vs)
                    if cats is None or cat in cats]
            if opt["sample"]:
                step = max(1, len(jobs) // opt["sample"])
                jobs = jobs[::step][:opt["sample"]]
            model.prepare_conditionals(refs[ch], exaggeration=spec["exaggeration"])
            for cat, i, text in jobs:
                out = os.path.join(opt["out"], lang, ch, "%s_%d.ogg" % (cat, i))
                if not opt["sample"] and not opt["force"] and os.path.exists(out):
                    continue  # reprise d'une génération interrompue
                wav = synth(model, text, lang, spec, "%s/%s/%s/%d" % (lang, ch, cat, i))
                if wav is None:
                    print("[vox] ÉCHEC %s %s %s_%d : %r" % (lang, ch, cat, i, text), flush=True)
                    continue
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
    if qwen:
        del model
        torch.cuda.empty_cache()
        run_qwen(qwen, opt)  # après Chatterbox : un seul gros calcul GPU à la fois


main()
