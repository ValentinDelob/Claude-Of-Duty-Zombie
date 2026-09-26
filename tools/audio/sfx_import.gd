extends SceneTree
## Importe les sons libres de droits (CC0, voir docs/ASSETS.md) dans
## res://assets/audio/ : téléchargement des sources (curl), décodage,
## traitement (SfxRecipes) et écriture en WAV mono 16 bits 44,1 kHz.
##
##   godot --headless --path . -s res://tools/audio/sfx_import.gd [-- options] [noms...]
##     --cache=<dossier>   sources téléchargées (défaut : <temp>/cod_sfx_cache)
##     --no-fetch          ne télécharge rien (sources déjà en cache)
##     --analyze=<dossier> analyse chaque .ogg/.wav du dossier (aucune écriture)
##     --dry               traite sans écrire, affiche seulement l'analyse
##     --loudness          intensité perçue (LUFS) de chaque son, par catégorie
##     --level             met les sons procéduraux (sans recette) au niveau
##                         de leur catégorie (SfxLoudness), en place
## Sans nom : traite toutes les recettes. Déterministe (graines fixes).

const OUT := "res://assets/audio/"


func _initialize() -> void:
	var names: Array[String] = []
	var cache := OS.get_temp_dir().path_join("cod_sfx_cache")
	var fetch := true
	var dry := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cache="):
			cache = a.substr(8)
		elif a == "--no-fetch":
			fetch = false
		elif a == "--dry":
			dry = true
		elif a.begins_with("--analyze="):
			_analyze_dir(a.substr(10))
			quit()
			return
		elif a == "--doc":
			_doc()
			quit()
			return
		elif a.begins_with("--segments="):
			_segments(a.substr(11))
			quit()
			return
		elif a == "--loudness":
			_loudness_report()
			quit()
			return
		elif a == "--level":
			quit(_level_procedural())
			return
		else:
			names.append(a)
	DirAccess.make_dir_recursive_absolute(cache)
	var todo: Array = names if not names.is_empty() else SfxRecipes.RECIPES.keys()
	var failed := 0
	for n in todo:
		if not SfxRecipes.RECIPES.has(n):
			push_error("recette inconnue : " + n)
			failed += 1
			continue
		var b := _build(n, SfxRecipes.RECIPES[n], cache, fetch)
		if b.is_empty():
			failed += 1
			continue
		print(SfxDsp.describe(n, b))
		if not dry:
			var loop: bool = SfxRecipes.RECIPES[n].get("loop", false)
			if SfxDsp.save_wav(b, ProjectSettings.globalize_path(OUT + n + ".wav"), loop) != OK:
				push_error("échec d'écriture " + n)
				failed += 1
	print("sfx_import : %d son(s), %d échec(s)" % [todo.size(), failed])
	quit(1 if failed > 0 else 0)


## Chemin local d'une source, téléchargée au besoin.
func _source(id: String, cache: String, fetch: bool) -> String:
	var src: Dictionary = SfxRecipes.SOURCES.get(id, {})
	if src.is_empty():
		push_error("source inconnue : " + id)
		return ""
	var path := cache.path_join(id + "." + String(src.url).get_extension())
	if not FileAccess.file_exists(path) and fetch:
		var out := []
		OS.execute("curl", ["-s", "-f", "-L", "-o", path, src.url], out, true)
	if not FileAccess.file_exists(path):
		push_error("source absente : %s (%s)" % [id, src.url])
		return ""
	return path


var _decoded := {}


func _load(id: String, cache: String, fetch: bool) -> PackedFloat32Array:
	if not _decoded.has(id):
		var p := _source(id, cache, fetch)
		_decoded[id] = SfxDsp.decode(p) if p != "" else PackedFloat32Array()
	return _decoded[id]


## Couche : {src, start, end, pitch, gain, at, hp, lp, eq:[[type,f,q,dB]...], fade_in, fade_out, trim}
func _layer(l: Dictionary, cache: String, fetch: bool) -> PackedFloat32Array:
	# Piste procédurale originale (SynthStems) mélangée aux enregistrements.
	var raw := SynthStems.build(String(l.stem)) if l.has("stem") else _load(String(l.src), cache, fetch)
	if raw.is_empty():
		return raw
	var b := SfxDsp.slice(raw, float(l.get("start", 0.0)), float(l.get("end", 0.0)))
	b = SfxDsp.dc_block(b)
	if l.get("trim", true):
		b = SfxDsp.trim_silence(b, float(l.get("head_db", -40.0)), -60.0)
	if l.has("pitch"):
		b = SfxDsp.resample(b, float(l.pitch))
	if l.has("hp"):
		b = SfxDsp.biquad(b, "hp", float(l.hp))
	if l.has("lp"):
		b = SfxDsp.biquad(b, "lp", float(l.lp))
	for e in l.get("eq", []):
		b = SfxDsp.biquad(b, e[0], e[1], e[2], e[3])
	if l.has("len"):
		b = SfxDsp.truncate(b, float(l.len), float(l.get("fade_out", 0.05)))
	b = SfxDsp.fade(b, float(l.get("fade_in", 0.001)), float(l.get("fade_out", 0.01)))
	# Couches mises au même niveau crête avant le gain relatif.
	b = SfxDsp.normalize(b, 0.0)
	return SfxDsp.gain(b, db_to_linear(float(l.get("gain", 0.0))))


## Recette complète : préréglage (SfxRecipes.PRESETS) puis surcharges.
static func recipe(n: String) -> Dictionary:
	var r: Dictionary = SfxRecipes.RECIPES[n]
	var out: Dictionary = SfxRecipes.PRESETS.get(r.get("preset", ""), {}).duplicate(true)
	out.merge(r, true)
	return out


func _build(n: String, r: Dictionary, cache: String, fetch: bool) -> PackedFloat32Array:
	r = recipe(n)
	var b := PackedFloat32Array()
	for l in r.layers:
		var lb := _layer(l, cache, fetch)
		if lb.is_empty():
			push_error("couche vide pour " + n)
			return lb
		# `times` : la couche est répétée à ces instants (liste, ou nom d'une
		# grille de temps de SynthStems, ex. "monkey_beats").
		var times: Variant = l.get("times", [0.0])
		if times is String:
			times = SynthStems.grid(times)
		var k := 0
		for t in times:
			# `alt_pitch` : une frappe sur deux légèrement désaccordée.
			var hit := lb
			if l.has("alt_pitch") and k % 2 == 1:
				hit = SfxDsp.resample(lb, float(l.alt_pitch))
			b = SfxDsp.mix(b, hit, float(l.get("at", 0.0)) + float(t))
			k += 1
	for e in r.get("eq", []):
		b = SfxDsp.biquad(b, e[0], e[1], e[2], e[3])
	if r.has("comp"):
		b = SfxDsp.compress(b, r.comp[0], r.comp[1], r.comp[2] if r.comp.size() > 2 else 0.002, r.comp[3] if r.comp.size() > 3 else 0.08)
	if r.has("drive"):
		b = SfxDsp.drive(b, float(r.drive))
	if r.has("room"):
		var rm: Array = r.room  # [taille, mouillé, queue s, amortissement]
		b = SfxDsp.room(b, rm[0], rm[1], rm[2], rm[3] if rm.size() > 3 else 0.4)
	if r.has("len"):
		b = SfxDsp.truncate(b, float(r.len), float(r.get("fade_out", 0.08)))
	b = SfxDsp.fade(b, 0.001, float(r.get("fade_out", 0.02)))
	b = SfxDsp.trim_silence(SfxDsp.normalize(b, -6.0), -80.0, -66.0)
	# Intensité perçue (et non plus crête) : cible de la catégorie du son,
	# limiteur pour les crêtes (SfxLoudness).
	return SfxLoudness.level(n, b, float(r.get("loud", 0.0)))


## Tous les sons du jeu (noms sans extension).
static func all_sounds() -> Array:
	var out := []
	for f in DirAccess.get_files_at(OUT):
		if f.get_extension() == "wav":
			out.append(f.get_basename())
	out.sort()
	return out


## Intensité perçue de chaque son, groupée par catégorie, avec l'écart à la
## cible (et la crête).
func _loudness_report() -> void:
	var by := {}
	for n in all_sounds():
		var b := SfxLoudness.read_wav(ProjectSettings.globalize_path(OUT + n + ".wav"))
		var c := SfxLoudness.category(n)
		var off: float = float(SfxRecipes.RECIPES[n].get("loud", 0.0)) if SfxRecipes.RECIPES.has(n) else float(SfxRecipes.LEVEL_OFFSETS.get(n, 0.0))
		var l := SfxLoudness.measure(n, b, 12.0)
		var line := "  %-22s %6.1f LUFS  écart %+5.1f  crête %5.1f  %s" % [n, l, l - float(c.target) - off, SfxLoudness.peak_db(b),
			"CC0" if SfxRecipes.RECIPES.has(n) else "proc"]
		if not by.has(c.id):
			by[c.id] = []
		by[c.id].append(line)
	for c in SfxLoudness.CATEGORIES:
		if by.has(c.id):
			print("%s (cible %.1f ±%.1f, %s)" % [c.id, c.target, c.tol, c.mode])
			for l in by[c.id]:
				print(l)


## Nivelle en place les sons procéduraux (générés par gen_audio*.gd) :
## même cible par catégorie que les sons importés.
func _level_procedural() -> int:
	var failed := 0
	for n in all_sounds():
		if SfxRecipes.RECIPES.has(n):
			continue
		var path := ProjectSettings.globalize_path(OUT + n + ".wav")
		var w := AudioStreamWAV.load_from_file(path)
		var b := SfxLoudness.read_wav(path)
		if b.is_empty():
			failed += 1
			continue
		var off := float(SfxRecipes.LEVEL_OFFSETS.get(n, 0.0))
		var before := SfxLoudness.deviation(n, b, off, 20.0)
		# Déjà dans la moitié de la tolérance : fichier (et identité) intacts.
		if absf(before) <= float(SfxLoudness.category(n).tol) * 0.5:
			continue
		b = SfxLoudness.balance(n, b, off)
		var loop := w.loop_mode != AudioStreamWAV.LOOP_DISABLED
		if SfxDsp.save_wav(b, path, loop) != OK:
			failed += 1
		print("  %-22s %+5.1f -> %+5.1f LU" % [n, before, SfxLoudness.deviation(n, b, off, 20.0)])
	return 1 if failed > 0 else 0


## Découpe un fichier en événements (au-dessus de -30 dB du pic, séparés
## par au moins 60 ms de silence relatif) : début, fin, crête. Aide à choisir
## start/end des recettes.
func _segments(path: String) -> void:
	for f in path.split(","):
		var b := SfxDsp.decode(f)
		var pk := SfxDsp.peak(b)
		var th := pk * db_to_linear(-30.0)
		var w := int(0.01 * SfxDsp.RATE)
		var out := []
		var start := -1.0
		var last_loud := -1.0
		var seg_pk := 0.0
		for s in range(0, b.size() - w, w):
			var m := 0.0
			for i in range(s, s + w):
				m = maxf(m, absf(b[i]))
			var t := float(s) / SfxDsp.RATE
			if m > th:
				if start < 0.0:
					start = t
					seg_pk = 0.0
				last_loud = t
				seg_pk = maxf(seg_pk, m)
			elif start >= 0.0 and t - last_loud > 0.06:
				out.append("%.2f-%.2f(%.0f)" % [start, last_loud + 0.01, SfxDsp.db(seg_pk / pk)])
				start = -1.0
		if start >= 0.0:
			out.append("%.2f-%.2f(%.0f)" % [start, last_loud + 0.01, SfxDsp.db(seg_pk / pk)])
		print("%s : %s" % [f.get_file().get_basename(), " ".join(out)])


## Tableau Markdown (docs/ASSETS.md) : fichier, sources, modifications.
func _doc() -> void:
	print("| Fichier | Source(s) (freesound.org, CC0 1.0) | Modifications |")
	print("|---|---|---|")
	for n in SfxRecipes.RECIPES:
		var r := recipe(n)
		var srcs := []
		var mods := ["mono 44,1 kHz 16 bits"]
		for l in r.layers:
			if l.has("stem"):
				srcs.append("air original procédural (`SynthStems.%s`)" % l.stem)
				continue
			var s: Dictionary = SfxRecipes.SOURCES[l.src]
			var cut := ""
			if l.has("start") or l.has("end"):
				cut = " [%.2f-%s s]" % [float(l.get("start", 0.0)), ("%.2f" % l.end) if l.has("end") else "fin"]
			srcs.append("[%s](https://freesound.org/s/%s/) par %s%s" % [String(s.title).replace("|", "/"), l.src, s.author, cut])
			if l.has("pitch"):
				mods.append("hauteur x%.2f" % float(l.pitch))
			if l.has("len"):
				mods.append("coupé à %.2f s" % float(l.len))
		if r.layers.size() > 1:
			mods.append("%d couches mixées" % r.layers.size())
		if r.has("eq"):
			mods.append("égalisation")
		if r.has("comp"):
			mods.append("compression")
		if r.has("drive"):
			mods.append("saturation x%.1f" % float(r.drive))
		if r.has("room"):
			mods.append("réverbération d'intérieur %.2f s" % float(r.room[2]))
		var c := SfxLoudness.category(n)
		mods.append("intensité %.0f LUFS (%s)" % [float(c.target) + float(r.get("loud", 0.0)), c.id])
		print("| `%s.wav` | %s | %s |" % [n, "<br>".join(srcs), ", ".join(mods)])


func _analyze_dir(dir: String) -> void:
	var files := DirAccess.get_files_at(dir)
	for f in files:
		if f.get_extension() in ["ogg", "wav", "mp3"]:
			var b := SfxDsp.decode(dir.path_join(f))
			print(SfxDsp.describe(f.get_basename(), b))
