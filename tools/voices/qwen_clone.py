# Répliques des personnages au moteur "qwen_clone" (tools/voices/cast.json ; Mercer) :
# clonage de voix Qwen3-TTS 12Hz 1.7B-Base (Apache 2.0, Alibaba Qwen) en mode ICL
# (audio de référence + sa transcription), une référence par langue, avec contrôle
# qualité automatique de chaque fichier et nouvelles prises pour les ratés.
#
#   tools/tts/qwen3tts/Scripts/python.exe tools/voices/qwen_clone.py --only mercer
#       [--lang fr|en] [--category no_money,hurt] [--sample N] [--out DOSSIER] [--force] [--qa-only]
#   (ou simplement make_voices.py, qui délègue ici les personnages "qwen_clone")
#
# - références : cast.json "ref_fr"/"ref_en" (WAV 24 kHz, chemins relatifs à la racine)
#   et leurs transcriptions exactes "ref_text_fr"/"ref_text_en" ; la voix française
#   et la voix anglaise sont deux timbres différents (accepté : une seule langue
#   est entendue en jeu) ;
# - génération par lots de "batch" répliques (bien plus rapide qu'une par une) ;
# - contrôle qualité de chaque prise, Whisper large-v3-turbo (MIT) chargé dans le
#   même processus : transcription comparée au texte (chiffres et interjections
#   normalisés), langue détectée (p >= "min_lang" dans la langue visée, sauf
#   répliques de moins de trois mots), hauteur médiane (librosa pyin) à moins de
#   "max_semitones" de celle de la référence, ressemblance de timbre (empreinte du
#   locuteur de Qwen3-TTS, cosinus >= "min_spk"), durée plausible ;
# - une prise ratée est refaite avec une autre graine, jusqu'à "tries" essais ; on
#   garde la meilleure ; rapport complet dans tools/tts/qa/<personnage>_<langue>.json
#   (hors git) et tableau des échecs restants à la fin ;
# - même nettoyage et même encodage que make_voices.py (vox_common.py) :
#   assets/audio/vox/<langue>/<personnage>/<catégorie>_<n>.ogg ;
# - fichiers existants gardés (reprise) sauf --force ; --qa-only : mesure les
#   fichiers existants sans rien générer ;
# - environnement : tools/tts/qwen3tts/ (venv Python 3.11, torch 2.6 cu124,
#   qwen-tts, openai-whisper, num2words), modèles dans tools/tts/hf et tools/tts/whisper.
import difflib, gc, hashlib, json, os, re, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vox_common import ROOT, TTS, speakable, process, write_ogg, load_cast, load_lines  # noqa: E402

os.environ.setdefault("HF_HOME", os.path.join(TTS, "hf"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import torch  # noqa: E402

LANG = {"fr": "French", "en": "English"}
# Interjections que Whisper écrit à sa façon (« Argh » -> « Ugh », « Ah ») : ignorées
# dans la comparaison des textes.
INTERJ = {"argh", "agh", "ah", "aah", "ha", "hah", "huh", "ugh", "ow", "ouch", "oh", "aïe", "ouille", "ouch",
          "bah", "han", "eh", "hé", "hey", "hein", "hm", "hmm", "uh", "euh", "ouais", "whoa"}
DEFAULTS = {"model": "Qwen/Qwen3-TTS-12Hz-1.7B-Base", "temperature": 0.9, "top_k": 50, "top_p": 1.0,
            "repetition_penalty": 1.05, "batch": 8, "batch_chars": 260, "takes": 1, "ogg_compression": None, "tries": 4, "min_sim": 0.8, "min_lang": 0.9,
            "max_semitones": 6.0, "min_spk": 0.85}


def args():
    a = sys.argv[1:]
    opt = {"lang": None, "only": None, "category": None, "sample": 0,
           "out": os.path.join(ROOT, "assets", "audio", "vox"), "force": False, "qa-only": False}
    i = 0
    while i < len(a):
        k = a[i].lstrip("-")
        if k in ("force", "qa-only"):
            opt[k] = True
            i += 1
            continue
        opt[k] = a[i + 1]
        i += 2
    opt["sample"] = int(opt["sample"])
    return opt


def words(s, lang):
    from num2words import num2words
    s = s.lower().replace("’", "'").replace("-", " ")
    if lang == "en":  # anglais parlé écrit dans les répliques, écrit en entier par Whisper
        s = re.sub(r"\bc'mon\b", "come on", s)
        s = re.sub(r"(?<=\s)'em\b|^'em\b", "them", s)
        s = re.sub(r"\b(gimme|outta|gonna|ya)\b", lambda m: {"gimme": "give me", "outta": "out of",
                                                             "gonna": "going to", "ya": "you"}[m.group(1)], s)
        s = re.sub(r"\b(\w+)in'(?=\W|$)", r"\1ing", s)
    if lang == "fr":  # argot écrit (Jojo) : « j'te » se dit « je te » ; « wesh », Whisper l'écrit « ouais »
        s = re.sub(r"\bj'(?=[bcdfgjklmnpqrstvwxz])", "je ", s)
        s = re.sub(r"\bwesh\b", "ouais", s)
    s = re.sub(r"\d+", lambda m: " " + num2words(int(m.group(0)), lang=lang).replace("-", " ") + " ", s)
    w = re.sub(r"[^a-zàâçéèêëîïôûùüÿœæ' ]", " ", s).split()
    w = [x for x in w if x not in INTERJ] or w
    if lang == "fr":  # homophones (« soldat/soldats », « couché/coucher », « grillé/griller »)
        w = [re.sub(r"(ées|ée|és|er|ez|ai)$", "é", re.sub(r"(?<=.)[sx]$", "", x)) for x in w]
    return w


def rasp_metrics(x, sr):
    """Voix éraillée ou lisse, sur les trames parlées : rapport énergie harmonique /
    percussive (HPSS, dB ; plus bas = plus de souffle et de grain) et platitude
    spectrale moyenne (plus haut = plus bruité). Les clones sortent souvent plus
    lisses que la référence (tools/voices/bakeoff/mercer_rasp/README.md)."""
    import librosa
    y = np.asarray(x, np.float32).reshape(-1)
    if sr != 24000:
        y = librosa.resample(y, orig_sr=sr, target_sr=24000)
    S = np.abs(librosa.stft(y, n_fft=1024, hop_length=256))
    rms = librosa.feature.rms(S=S, frame_length=1024, hop_length=256)[0]
    sp = rms > 0.1 * rms.max()
    H, P = librosa.decompose.hpss(S)
    hp = 10 * np.log10((H[:, sp] ** 2).sum() / max((P[:, sp] ** 2).sum(), 1e-12))
    fl = float(librosa.feature.spectral_flatness(S=S)[0][sp].mean())
    return {"hp_db": round(float(hp), 2), "flat": round(max(fl, 1e-5), 4)}


class Judge:
    """Contrôle qualité d'une prise (Whisper + hauteur + timbre)."""

    def __init__(self, model, spec):
        import whisper
        self.whisper = whisper
        # fp16 : moitié moins de mémoire GPU (en fp32, Qwen + Whisper débordent des 8 Go et tout ralentit)
        # (couches linéaires et convolutions seulement : les LayerNorm de Whisper restent en fp32).
        self.w = whisper.load_model("large-v3-turbo", device="cuda", download_root=os.path.join(TTS, "whisper"))
        for mod in self.w.modules():
            if isinstance(mod, (torch.nn.Linear, torch.nn.Conv1d, torch.nn.Embedding)):
                mod.half()
        self.m, self.spec = model, spec
        self.ref_emb, self.ref_f0 = {}, {}
        self.ref_rasp = {}
        self.times = {"whisper": 0.0, "f0": 0.0, "timbre": 0.0, "grain": 0.0}

    def emb(self, x, sr):
        import librosa
        if sr != 24000:
            x = librosa.resample(x, orig_sr=sr, target_sr=24000)
        e = self.m.model.extract_speaker_embedding(audio=x.astype(np.float32), sr=24000).float().reshape(-1)
        return e / e.norm()

    def f0(self, x, sr):
        import librosa
        # YIN sur les trames sonores (pyin est dix fois plus lent pour un résultat voisin).
        y = librosa.resample(x.astype(np.float32), orig_sr=sr, target_sr=16000)
        f = librosa.yin(y, fmin=60, fmax=500, sr=16000, frame_length=1024, hop_length=256)
        rms = librosa.feature.rms(y=y, frame_length=1024, hop_length=256)[0][:len(f)]
        f = f[:len(rms)][(rms > 0.25 * rms.max()) & (f < 490)]
        return float(np.median(f)) if len(f) else 0.0

    def f0_pyin(self, x, sr):
        """pyin, plus lent mais sans erreurs d'octave : vérifie les valeurs YIN hors limites."""
        import librosa
        y = librosa.resample(x.astype(np.float32), orig_sr=sr, target_sr=16000)
        f, _, _ = librosa.pyin(y, fmin=60, fmax=500, sr=16000, frame_length=1024)
        f = f[~np.isnan(f)]
        return float(np.median(f)) if len(f) else 0.0

    def set_ref(self, lang, x, sr):
        self.ref_emb[lang] = self.emb(x, sr)
        self.ref_f0[lang] = self.f0(x, sr)
        self.ref_rasp[lang] = rasp_metrics(x, sr)

    def rasp(self, x, sr, lang):
        """Grain de la prise brute comparé à la référence : dist = écart de rapport
        harmonique/percussif (dB / 2) + écart de platitude (log / 0,4) ; 0 = même grain."""
        t = time.time()
        m, r = rasp_metrics(x, sr), self.ref_rasp[lang]
        m["dist"] = round(abs(m["hp_db"] - r["hp_db"]) / 2.0 + abs(np.log(m["flat"] / r["flat"])) / 0.4, 3)
        self.times["grain"] += time.time() - t
        return m

    def __call__(self, x, sr, lang, text):
        import librosa
        t = time.time()
        y16 = librosa.resample(x.astype(np.float32), orig_sr=sr, target_sr=16000)
        mel = self.whisper.log_mel_spectrogram(self.whisper.pad_or_trim(torch.from_numpy(y16)), n_mels=128).to("cuda").half()
        _, probs = self.w.detect_language(mel)
        heard = self.w.transcribe(y16, language=lang, temperature=0.0)["text"].strip()
        want = words(text, lang)
        sim = difflib.SequenceMatcher(None, words(heard, lang), want).ratio()
        self.times["whisper"] += time.time() - t
        t = time.time()
        f0 = self.f0(x, sr)
        st = 12 * np.log2(f0 / self.ref_f0[lang]) if f0 > 0 else 99.0
        if abs(st) > self.spec["max_semitones"]:
            f0 = self.f0_pyin(x, sr)
            st = 12 * np.log2(f0 / self.ref_f0[lang]) if f0 > 0 else 99.0
        self.times["f0"] += time.time() - t
        t = time.time()
        spk = float(torch.dot(self.emb(x, sr), self.ref_emb[lang]))
        self.times["timbre"] += time.time() - t
        dur = len(x) / sr
        p = float(probs.get(lang, 0.0))
        s = self.spec
        why = []
        if sim < s["min_sim"]:
            why.append("texte")
        if len(want) >= 3 and p < s["min_lang"]:
            why.append("langue")
        if abs(st) > s["max_semitones"]:
            why.append("hauteur")
        if spk < s["min_spk"]:
            why.append("timbre")
        if dur > 1.2 + 0.1 * len(text):
            why.append("durée")
        score = sim + 0.3 * p + 0.5 * spk - 0.05 * max(0.0, abs(st) - 4.0) - 0.3 * len(why)
        return {"ok": not why, "why": why, "score": round(score, 3), "sim": round(sim, 2), "p_lang": round(p, 3),
                "f0": round(f0), "semitones": round(float(st), 1), "spk": round(spk, 3), "dur": round(dur, 2),
                "heard": heard}


def seed(key, attempt):
    return int(hashlib.md5(("%s#%d" % (key, attempt)).encode()).hexdigest()[:8], 16)


def main():
    opt = args()
    cast = load_cast()
    chars = opt["only"].split(",") if opt["only"] else [c for c, s in cast.items() if s.get("engine") == "qwen_clone"]
    langs = [opt["lang"]] if opt["lang"] else ["fr", "en"]
    cats = set(opt["category"].split(",")) if opt["category"] else None
    from qwen_tts import Qwen3TTSModel
    t_start = time.time()
    model = None
    for ch in chars:
        spec = dict(DEFAULTS, **cast[ch])
        assert spec.get("engine") == "qwen_clone", "%s : moteur %r" % (ch, spec.get("engine"))
        if model is None:
            model = Qwen3TTSModel.from_pretrained(spec["model"], device_map="cuda:0", dtype=torch.bfloat16,
                                                  attn_implementation="sdpa")
            judge = Judge(model, spec)
        judge.spec = spec
        sampling = {k: spec[k] for k in ("temperature", "top_k", "top_p", "repetition_penalty")}
        lines = load_lines(ch)
        for lang in langs:
            ref = os.path.join(ROOT, spec["ref_" + lang])
            ref_text = spec["ref_text_" + lang]
            rx, rsr = sf.read(ref, dtype="float32")
            judge.set_ref(lang, rx, rsr)
            prompt = model.create_voice_clone_prompt(ref_audio=ref, ref_text=ref_text, x_vector_only_mode=False)
            jobs = [(cat, i, speakable(v[lang], lang)) for cat, vs in lines.items() for i, v in enumerate(vs)
                    if cats is None or cat in cats]
            if opt["sample"]:
                step = max(1, len(jobs) // opt["sample"])
                jobs = jobs[::step][:opt["sample"]]
            out_of = lambda cat, i: os.path.join(opt["out"], lang, ch, "%s_%d.ogg" % (cat, i))  # noqa: E731
            qa_path = os.path.join(TTS, "qa", "%s_%s.json" % (ch, lang))
            report = json.load(open(qa_path, encoding="utf-8")) if os.path.exists(qa_path) else {}
            t0 = time.time()
            if opt["qa-only"]:
                for cat, i, text in jobs:
                    path = out_of(cat, i)
                    if os.path.exists(path):
                        x, sr = sf.read(path, dtype="float32")
                        r = judge(x, sr, lang, text)
                        report["%s_%d" % (cat, i)] = dict(r, text=text, take=report.get("%s_%d" % (cat, i), {}).get("take"))
                        print("[qa] %s %s %s_%d %s %s" % (lang, ch, cat, i, "ok" if r["ok"] else "RATÉ " + ",".join(r["why"]), r["heard"]), flush=True)
            else:
                pending = [j for j in jobs if opt["sample"] or opt["force"] or not os.path.exists(out_of(j[0], j[1]))]
                best = {}
                print("[qwen] %s %s : %d répliques à générer (référence %.1f Hz)" % (lang, ch, len(pending), judge.ref_f0[lang]), flush=True)
                for attempt in range(spec["tries"]):
                    if not pending:
                        break
                    pending.sort(key=lambda j: len(j[2]))  # lots de longueurs voisines
                    retry = []
                    # Chaque réplique est tirée "takes" fois (prises différentes du même lot) ; parmi les
                    # prises validées par le contrôle, on garde la plus « éraillée » (grain le plus proche
                    # de la référence, voir rasp_metrics()). Lots de "batch" prises au plus et "batch_chars"
                    # caractères au plus : au-delà, la mémoire GPU déborde (8 Go avec Whisper) et tout
                    # ralentit fortement. Les prises d'une même réplique restent dans le même lot.
                    n_takes = max(1, int(spec["takes"]))
                    chunks, cur = [], []
                    for j in pending:
                        size = sum(len(t) for _, _, t in cur) * n_takes
                        if cur and ((len(cur) + 1) * n_takes > max(spec["batch"], n_takes)
                                    or size + len(j[2]) * n_takes > max(spec["batch_chars"], len(j[2]) * n_takes)):
                            chunks.append(cur)
                            cur = []
                        cur.append(j)
                    chunks += [cur] if cur else []
                    for chunk in chunks:
                        key = "%s/%s/%s" % (lang, ch, "|".join("%s_%d" % (c, i) for c, i, _ in chunk))
                        torch.manual_seed(seed(key, attempt))
                        texts = [t for _, _, t in chunk for _ in range(n_takes)]
                        tg = time.time()
                        wavs, sr = model.generate_voice_clone(text=texts, language=LANG[lang],
                                                              voice_clone_prompt=prompt * len(texts), **sampling)
                        tg = time.time() - tg
                        torch.cuda.empty_cache()
                        for n, (cat, i, text) in enumerate(chunk):
                            name = "%s_%d" % (cat, i)
                            cands = []
                            for k in range(n_takes):
                                raw = np.asarray(wavs[n * n_takes + k], dtype=np.float32).reshape(-1)
                                y = process(raw, sr)
                                r = judge(y, sr, lang, text)
                                r.update(text=text, take=attempt + 1, sub=k + 1, rasp=judge.rasp(raw, sr, lang))
                                cands.append((r, y))
                                if name not in best or r["score"] > best[name][0]["score"]:
                                    best[name] = (r, y, sr)
                            good = [c for c in cands if c[0]["ok"]]
                            if good:
                                r, y = min(good, key=lambda c: c[0]["rasp"]["dist"])
                                write_ogg(y, sr, out_of(cat, i), spec.get("ogg_compression"))
                                report[name] = r
                            else:
                                r = max(cands, key=lambda c: c[0]["score"])[0]
                                retry.append((cat, i, text))
                            print("[qwen] %s %s %s essai %d : %s (%d/%d prises ok) sim=%.2f p=%.2f f0=%d (%+.1f dt) spk=%.2f grain=%.2f | %s" % (
                                lang, ch, name, attempt + 1, "ok" if r["ok"] else "RATÉ " + ",".join(r["why"]), len(good), n_takes,
                                r["sim"], r["p_lang"], r["f0"], r["semitones"], r["spk"], r["rasp"]["dist"], r["heard"]), flush=True)
                        print("[qwen] lot de %d prises : %.1f s (%.0f s écoulées ; contrôle cumulé : %s)" % (
                            len(texts), tg, time.time() - t0,
                            ", ".join("%s %.0f s" % kv for kv in judge.times.items())), flush=True)
                        if not opt["sample"]:  # rapport à jour après chaque lot (reprise possible)
                            os.makedirs(os.path.dirname(qa_path), exist_ok=True)
                            json.dump(report, open(qa_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
                    pending = retry
                for cat, i, text in pending:  # échecs après tous les essais : on garde la meilleure prise
                    name = "%s_%d" % (cat, i)
                    r, y, sr = best[name]
                    write_ogg(y, sr, out_of(cat, i), spec.get("ogg_compression"))
                    report[name] = r
                    print("[qwen] %s %s %s gardé malgré %s (meilleur essai %d)" % (lang, ch, name, ",".join(r["why"]), r["take"]), flush=True)
            if not opt["sample"]:
                os.makedirs(os.path.dirname(qa_path), exist_ok=True)
                json.dump(report, open(qa_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            bad = {k: v for k, v in report.items() if not v.get("ok")}
            print("[qwen] %s %s : %d fichiers mesurés, %d échecs restants, %.0f s" % (
                lang, ch, len(report), len(bad), time.time() - t0), flush=True)
            for k, v in sorted(bad.items()):
                print("    %-22s %-16s sim=%.2f p=%.2f f0=%d spk=%.2f | %s | %s" % (
                    k, ",".join(v["why"]), v["sim"], v["p_lang"], v["f0"], v["spk"], v["text"], v["heard"]), flush=True)
    print("[qwen] terminé en %.0f s" % (time.time() - t_start), flush=True)
    del model
    gc.collect()
    torch.cuda.empty_cache()


main()
