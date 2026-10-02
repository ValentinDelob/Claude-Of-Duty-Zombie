# Convertit une prise enregistrée (sa propre voix, jouée avec l'émotion voulue)
# vers le timbre d'un personnage avec Seed-VC (conversion de voix zéro-shot) :
# le jeu d'acteur (rythme, intonation, souffle, cris, grognements) est gardé,
# seul le timbre change.
#
#   tools/tts/seed-vc/.venv/Scripts/python.exe tools/voices/convert_take.py <prise> [<prise> ...]
#       --character callahan [--semitones N] [--out FICHIER.wav] [--steps N] [--model f0|parole]
#
# - timbre cible : tools/tts/refs/<personnage>.wav (voix de référence SYNTHÉTIQUE
#   produite par make_voices.py ; aucune voix de personne réelle n'est clonée) ;
# - entrée : tout format (wav, m4a, mp3, ogg, flac...) décodé par ffmpeg
#   (tools/tts/bin, PATH ou celui fourni par imageio-ffmpeg), sinon librosa ;
# - sortie : WAV 16 bits mono, silences coupés, parole à -19 dBFS comme les
#   répliques du jeu ; par défaut tools/voices/takes/out/<nom>_<personnage>.wav ;
# - environnement : tools/tts/seed-vc/ (hors git, voir docs/ASSETS.md).
#   Seed-VC : code et poids GPL-3.0 (outil seulement, rien n'est livré avec le jeu).
import argparse, json, math, os, shutil, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TTS = os.path.join(ROOT, "tools", "tts")
SEEDVC = os.path.join(TTS, "seed-vc")
os.environ.setdefault("HF_HOME", os.path.join(TTS, "hf"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

import numpy as np
import soundfile as sf


def opts():
    p = argparse.ArgumentParser(description="Prise enregistrée -> voix d'un personnage (Seed-VC).")
    p.add_argument("inputs", nargs="+", help="fichier(s) audio : une réplique par fichier")
    p.add_argument("--character", required=True, help="callahan, orlov, arakawa, weissmann, mercer")
    p.add_argument("--lang", choices=["fr", "en"], default="fr",
                   help="personnages à une référence par langue (Mercer) : laquelle prendre")
    p.add_argument("--semitones", type=float, default=0.0,
                   help="décalage de hauteur après l'ajustement automatique (mode f0 seulement)")
    p.add_argument("--out", help="fichier de sortie (une seule prise)")
    p.add_argument("--steps", type=int, default=40,
                   help="pas de diffusion : 30-50 = meilleure qualité, 10 = brouillon rapide")
    p.add_argument("--model", choices=["f0", "parole"], default="f0",
                   help="f0 : suit la courbe de hauteur de la prise (recommandé) ; parole : modèle 22 kHz sans f0")
    return p.parse_args()


# ---------------------------------------------------------------- audio

def ffmpeg_exe():
    for c in [os.path.join(TTS, "bin", "ffmpeg.exe"), shutil.which("ffmpeg")]:
        if c and os.path.exists(c):
            return c
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return None


def load(path, sr):
    """Décode n'importe quel format en mono float32 à sr (ffmpeg, sinon librosa)."""
    exe = ffmpeg_exe()
    if exe:
        cmd = [exe, "-v", "error", "-nostdin", "-i", path, "-vn", "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"]
        r = subprocess.run(cmd, capture_output=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if r.returncode == 0 and r.stdout:
            return np.frombuffer(r.stdout, np.float32).copy()
        print("[take] ffmpeg en échec (%s), essai avec librosa" % r.stderr.decode(errors="ignore").strip())
    import librosa
    return librosa.load(path, sr=sr, mono=True)[0].astype(np.float32)


def highpass(x, sr, fc):
    n = 1 << int(math.ceil(math.log2(len(x) + 1024)))
    f = np.fft.rfftfreq(n, 1 / sr)
    g = 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1.0)) ** 4)
    return np.fft.irfft(np.fft.rfft(x, n) * g, n)[:len(x)].astype(np.float32)


def trim(x, sr, floor_db, pad_s):
    """Coupe le silence au début et à la fin. Le seuil suit le bruit de fond de la
    prise (10 dB au-dessus du 10e centile) pour garder souffles et soupirs."""
    env = np.convolve(np.abs(x), np.ones(256) / 256, "same")
    noise = np.percentile(env, 10)
    thr = max(10 ** (floor_db / 20), noise * 10 ** (10 / 20))
    idx = np.where(env > thr)[0]
    if not len(idx):
        return x
    pad = int(pad_s * sr)
    return x[max(0, idx[0] - pad):min(len(x), idx[-1] + pad)]


def prepare(x, sr):
    """Entrée du modèle : bourdonnement et grondements (< 60 Hz) retirés, silences
    coupés (0,15 s de marge pour ne pas manger une inspiration), crête à -3 dBFS."""
    x = highpass(x - np.mean(x), sr, 60.0)
    x = trim(x, sr, -50, 0.15)
    return (x * (10 ** (-3 / 20) / max(np.max(np.abs(x)), 1e-4))).astype(np.float32)


def finish(x, sr):
    """Même traitement final que make_voices.py : silences coupés, passe-haut léger,
    parole à -19 dBFS, crêtes adoucies, fondus."""
    x = trim(x, sr, -45, 0.03)
    x = highpass(x, sr, 80.0)
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


# ---------------------------------------------------------------- Seed-VC

class Converter:
    """Charge Seed-VC v1 une fois (plusieurs prises à la suite sans recharger).

    Choix des réglages pour garder le jeu d'acteur :
    - modèle « f0 » (seed-uvit-whisper-base f0 44 kHz) : la courbe de hauteur
      de la prise (extraite par RMVPE) conditionne la génération ; montées de
      voix, cris, intonation des questions sont donc reproduits tels quels.
      Le modèle « parole » 22 kHz n'a pas d'entrée f0 et réinvente l'intonation ;
    - auto-f0-adjust activé : la hauteur médiane de la prise est ramenée sur celle
      de la référence (sinon une voix aiguë donnerait un Callahan aigu), les
      variations autour de la médiane restent celles de l'acteur ; --semitones
      ajoute un décalage fixe par-dessus ;
    - length-adjust 1.0 : le rythme et les pauses de la prise ne bougent pas ;
    - inference-cfg-rate 0.7 (valeur conseillée par Seed-VC) : timbre fidèle à la
      référence sans artefacts métalliques (plus haut = plus dur, plus bas = timbre
      moins proche) ;
    - 40 pas de diffusion (30-50 conseillés pour la meilleure qualité ; 25 par
      défaut dans Seed-VC) : souffles et consonnes plus nets, coût faible sur des
      répliques de quelques secondes ;
    - fp16 : moitié moins de mémoire GPU, sans perte audible.
    La v2 de Seed-VC (« convert-style ») convertit aussi l'émotion et l'accent vers
    la référence : exactement ce qu'on ne veut pas ici (référence calme)."""

    def __init__(self, f0):
        os.chdir(SEEDVC)  # Seed-VC télécharge ses poids dans ./checkpoints
        sys.path.insert(0, SEEDVC)
        import torch
        import inference as vc
        self.torch, self.vc, self.f0 = torch, vc, f0
        a = argparse.Namespace(f0_condition=f0, checkpoint=None, config=None, fp16=True)
        (self.model, self.semantic_fn, self.f0_fn, self.vocoder_fn, self.campplus,
         self.mel_fn, mel_args) = vc.load_models(a)
        self.sr = mel_args["sampling_rate"]
        self.hop = mel_args["hop_size"]

    def __call__(self, src, ref, steps, semitones):
        torch, vc, dev = self.torch, self.vc, self.vc.device
        import torchaudio
        sr, hop = self.sr, self.hop
        max_ctx = sr // hop * 30
        ov_frames = 16
        ov_wave = ov_frames * hop
        with torch.no_grad():
            src_t = torch.tensor(src)[None].float().to(dev)
            ref_t = torch.tensor(ref[:sr * 25])[None].float().to(dev)
            src16 = torchaudio.functional.resample(src_t, sr, 16000)
            ref16 = torchaudio.functional.resample(ref_t, sr, 16000)
            if src16.size(-1) > 16000 * 30:
                raise SystemExit("prise trop longue (> 30 s) : une réplique par fichier")
            S_alt = self.semantic_fn(src16)
            S_ori = self.semantic_fn(ref16)
            mel = self.mel_fn(src_t)
            mel2 = self.mel_fn(ref_t)
            feat2 = torchaudio.compliance.kaldi.fbank(ref16, num_mel_bins=80, dither=0, sample_frequency=16000)
            style2 = self.campplus((feat2 - feat2.mean(dim=0, keepdim=True))[None])
            f0_alt = f0_ori = None
            if self.f0:
                f0_ori = torch.from_numpy(self.f0_fn(ref16[0], thred=0.03)).to(dev)[None]
                f0_src = torch.from_numpy(self.f0_fn(src16[0], thred=0.03)).to(dev)[None]
                voiced = f0_src > 1
                log_f0 = torch.log(f0_src + 1e-5)
                if voiced.any():
                    shift = torch.median(torch.log(f0_ori[f0_ori > 1] + 1e-5)) - torch.median(log_f0[voiced])
                    log_f0[voiced] += shift + semitones / 12.0 * math.log(2.0)
                f0_alt = torch.exp(log_f0)
                f0_alt[~voiced] = f0_src[~voiced]
            cond = self.model.length_regulator(S_alt, ylens=torch.LongTensor([mel.size(2)]).to(dev),
                                               n_quantizers=3, f0=f0_alt)[0]
            prompt = self.model.length_regulator(S_ori, ylens=torch.LongTensor([mel2.size(2)]).to(dev),
                                                 n_quantizers=3, f0=f0_ori)[0]
            window = max_ctx - mel2.size(2)
            done, chunks, prev = 0, [], None
            while done < cond.size(1):
                part = cond[:, done:done + window]
                last = done + window >= cond.size(1)
                cat = torch.cat([prompt, part], dim=1)
                with torch.autocast(device_type=dev.type, dtype=torch.float16):
                    mel_out = self.model.cfm.inference(cat, torch.LongTensor([cat.size(1)]).to(dev), mel2, style2,
                                                       None, steps, inference_cfg_rate=0.7)[:, :, mel2.size(-1):]
                w = self.vocoder_fn(mel_out.float()).squeeze().cpu().numpy()
                if prev is None and last:
                    chunks.append(w)
                    break
                body = w if last else w[:-ov_wave]
                chunks.append(body if prev is None else vc.crossfade(prev, body.copy(), ov_wave))
                if last:
                    break
                prev = w[-ov_wave:]
                done += mel_out.size(2) - ov_frames
        return np.concatenate(chunks).astype(np.float32)


def main():
    o = opts()
    cast = json.load(open(os.path.join(ROOT, "tools", "voices", "cast.json"), encoding="utf-8"))["characters"]
    # personnage hors distribution accepté s'il a déjà sa référence (voix en cours de création)
    if o.character not in cast and not os.path.exists(os.path.join(TTS, "refs", o.character + ".wav")):
        raise SystemExit("personnage inconnu : %s (%s)" % (o.character, ", ".join(cast)))
    if o.out and len(o.inputs) > 1:
        raise SystemExit("--out n'est possible qu'avec une seule prise")
    if o.semitones and o.model != "f0":
        print("[take] --semitones ignoré avec --model parole")
    inputs = [os.path.abspath(p) for p in o.inputs]
    out = os.path.abspath(o.out) if o.out else None
    ref_path = os.path.join(TTS, "refs", o.character + ".wav")
    if cast.get(o.character, {}).get("ref_" + o.lang):  # moteur qwen_clone : référence de la langue
        ref_path = os.path.join(ROOT, cast[o.character]["ref_" + o.lang])
    if not os.path.exists(ref_path):
        raise SystemExit("référence absente : %s (make_voices.py --refs)" % ref_path)

    t0 = time.time()
    conv = Converter(o.model == "f0")
    print("[take] Seed-VC chargé (%.0f s, %d Hz)" % (time.time() - t0, conv.sr), flush=True)
    ref = prepare(load(ref_path, conv.sr), conv.sr)
    for path in inputs:
        t = time.time()
        conv.torch.cuda.reset_peak_memory_stats() if conv.torch.cuda.is_available() else None
        src = prepare(load(path, conv.sr), conv.sr)
        y = finish(conv(src, ref, o.steps, o.semitones), conv.sr)
        dest = out or os.path.join(ROOT, "tools", "voices", "takes", "out",
                                   "%s_%s.wav" % (os.path.splitext(os.path.basename(path))[0], o.character))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        sf.write(dest, y, conv.sr, subtype="PCM_16")
        vram = conv.torch.cuda.max_memory_allocated() / 2 ** 30 if conv.torch.cuda.is_available() else 0
        print("[take] %s -> %s (%.1f s de son, %.1f s de calcul, %.1f Go GPU max)"
              % (os.path.basename(path), dest, len(y) / conv.sr, time.time() - t, vram), flush=True)


main()
