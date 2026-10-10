class_name ProfileStore
extends RefCounted
## Enregistrement du profil du joueur (PlayerProfile) dans user://profile.json.
## Pendant les autotests : un fichier par processus
## (user://profile_autotest_<pid>.json, effacé à la fin, comme CareerStats).
##
## Format (JSON, lisible ; JSON ne décode jamais d'objet ni de ressource,
## contrairement à ConfigFile, voir SafeConfig) :
##   {"format": "profile", "version": 2, "saved_at": <unix>,
##    "profile": {"xp", "level" (informatif), "next_uid", "starting_weapons",
##                "samples": {type: n}, "weapons": [...], "parts": [...],
##                "contracts": {...} (ContractState), "exchanges": {"done": {id: n}},
##                "seen": {"weapons": [uid...], "parts": [uid...]}}}
## Version 2 (hub, docs/HUB_PLAN.md §5.4) : sections « contracts »,
## « exchanges » et « seen ». Un fichier version 1 se lit sans perte
## (_migrate) : contrats neufs (graine tirée, tableau rempli à la première
## rotation), aucun échange, tout l'arsenal existant marqué vu ; il est
## réécrit en version 2 au prochain enregistrement.
## Arme : {"uid", "id", "level", "rarity": "common"|"rare"|"epic"|"legendary"|"unique",
##         "parts": [pièce...]} ; pièce : {"uid", "id", "level", "mods": {stat: valeur}}.
##
## Robustesse : jamais de perte silencieuse.
## * Écriture dans « .tmp », puis l'ancien fichier (s'il est lisible) devient
##   la copie de secours « .bak », puis « .tmp » prend sa place : une coupure
##   à n'importe quel moment laisse un fichier complet.
## * Fichier illisible (JSON cassé, mauvais format, version plus récente) :
##   il est mis de côté en « .corrupt-<date unix> » (jamais écrasé) avec un
##   avertissement, puis la copie de secours est lue ; sans copie lisible, le
##   profil repart de zéro (le fichier mis de côté reste récupérable).
## * Entrées illisibles dans un fichier lisible (arme inconnue de format...) :
##   écartées, et une copie du fichier d'origine est gardée en « .invalid-<date> ».

const PATH := "user://profile.json"
const TEST_PATH_PREFIX := "user://profile_autotest_"
const FORMAT := "profile"
## Version du format. À augmenter (avec une migration dans _migrate) à chaque
## changement incompatible.
const VERSION := 2
## Taille maximale lue (octets) : arsenal illimité, mais un fichier de cette
## taille n'est plus un profil normal.
const MAX_BYTES := 16 << 20

## Résultat du dernier chargement : "ok", "new" (aucun fichier), "backup"
## (fichier principal illisible, copie de secours lue) ou "reset" (rien de
## lisible : profil neuf, fichiers mis de côté).
static var last_status := ""


static func path() -> String:
	return "%s%d.json" % [TEST_PATH_PREFIX, OS.get_process_id()] if Autotest.active else PATH


static func backup_path(p: String) -> String:
	return p + ".bak"


## Profil enregistré (`p` : fichier, par défaut path()). Ne renvoie jamais null.
static func load_profile(p := "") -> PlayerProfile:
	if p == "":
		p = path()
	var main := read_file(p)
	if main.ok:
		if main.dropped > 0:
			push_warning("[Profile] %d entrée(s) illisible(s) écartée(s) de %s (copie gardée)" % [main.dropped, p])
			_keep_copy(p, "invalid")
		last_status = "ok"
		return main.profile
	var had_main := FileAccess.file_exists(p)
	if had_main:
		push_warning("[Profile] %s illisible (%s) : mis de côté" % [p, main.reason])
		_set_aside(p, "corrupt")
	var bak_path := backup_path(p)
	var bak := read_file(bak_path)
	if bak.ok:
		push_warning("[Profile] copie de secours %s utilisée" % bak_path)
		if bak.dropped > 0:
			_keep_copy(bak_path, "invalid")
		last_status = "backup"
		return bak.profile
	var had_bak := FileAccess.file_exists(bak_path)
	if had_bak:
		push_warning("[Profile] copie de secours %s illisible (%s) : mise de côté" % [bak_path, bak.reason])
		_set_aside(bak_path, "corrupt")
	last_status = "reset" if had_main or had_bak else "new"
	return PlayerProfile.new()


## Enregistre le profil (`p` : fichier, par défaut path()).
static func save_profile(pr: PlayerProfile, p := "") -> Error:
	if p == "":
		p = path()
	var doc := {"format": FORMAT, "version": VERSION, "saved_at": int(Time.get_unix_time_from_system()),
			"profile": pr.to_dict()}
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var e := FileAccess.get_open_error()
		push_warning("[Profile] profil non enregistré (%s)" % error_string(e))
		return e
	f.store_string(JSON.stringify(doc, "\t"))
	var werr := f.get_error()
	f.close()
	if werr != OK:
		push_warning("[Profile] profil non enregistré (%s)" % error_string(werr))
		DirAccess.remove_absolute(_abs(tmp))
		return werr
	if FileAccess.file_exists(p):
		if read_file(p).ok:
			# Le fichier actuel, lisible, devient la copie de secours.
			var bak := backup_path(p)
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(_abs(bak))
			DirAccess.rename_absolute(_abs(p), _abs(bak))
		else:
			# Abîmé depuis son chargement : mis de côté, la copie de secours reste.
			_set_aside(p, "corrupt")
	var err := DirAccess.rename_absolute(_abs(tmp), _abs(p))
	if err != OK:
		push_warning("[Profile] profil non enregistré (%s)" % error_string(err))
	return err


## Lit et vérifie un fichier de profil :
## {ok, profile (PlayerProfile ou null), dropped (entrées écartées), reason}.
static func read_file(p: String) -> Dictionary:
	var out := {"ok": false, "profile": null, "dropped": 0, "reason": ""}
	if not FileAccess.file_exists(p):
		out.reason = "absent"
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		out.reason = "ouverture impossible"
		return out
	if f.get_length() > MAX_BYTES:
		out.reason = "trop gros"
		return out
	var text := f.get_as_text()
	f.close()
	return parse_text(text)


## Vérifie le texte d'un fichier de profil (même résultat que read_file).
static func parse_text(text: String) -> Dictionary:
	var out := {"ok": false, "profile": null, "dropped": 0, "reason": ""}
	var json := JSON.new()
	if json.parse(text) != OK:
		out.reason = "JSON invalide ligne %d" % json.get_error_line()
		return out
	var doc: Variant = json.data
	if not doc is Dictionary or doc.get("format") != FORMAT:
		out.reason = "format inconnu"
		return out
	var v: Variant = doc.get("version")
	if not (v is float or v is int) or not is_finite(float(v)) or int(v) < 1:
		out.reason = "version absente"
		return out
	if int(v) > VERSION:
		out.reason = "version %d plus récente que le jeu (%d)" % [int(v), VERSION]
		return out
	var data: Variant = doc.get("profile")
	if not data is Dictionary:
		out.reason = "profil absent"
		return out
	data = _migrate(data, int(v))
	var dropped := [0]
	out.profile = PlayerProfile.from_dict(data, dropped)
	out.dropped = dropped[0]
	out.ok = true
	return out


## Efface le profil et ses copies (tests ; fin d'un autotest).
static func reset(p := "") -> void:
	if p == "":
		p = path()
	var dir := p.get_base_dir()
	var base := p.get_file()
	for name in DirAccess.get_files_at(dir):
		if name == base or name.begins_with(base + "."):
			DirAccess.remove_absolute(_abs(dir.path_join(name)))


## Passage d'un ancien format au format actuel.
## 1 -> 2 : les sections du hub n'existaient pas ; toute clé de ce nom dans un
## fichier v1 (modifié à la main) est ignorée : PlayerProfile.from_dict crée
## alors des contrats neufs, aucun échange, et marque l'existant comme vu.
static func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version < 2:
		data = data.duplicate()
		for k in ["contracts", "exchanges", "seen"]:
			data.erase(k)
	return data


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## Nom libre pour mettre de côté `p` : « <p>.<raison>-<date unix>[-n] ».
static func _aside_name(p: String, reason: String) -> String:
	var stem := "%s.%s-%d" % [p, reason, int(Time.get_unix_time_from_system())]
	var out := stem
	var n := 1
	while FileAccess.file_exists(out):
		out = "%s-%d" % [stem, n]
		n += 1
	return out


## Déplace le fichier `p` à côté (il ne sera plus lu ni écrasé).
static func _set_aside(p: String, reason: String) -> void:
	DirAccess.rename_absolute(_abs(p), _abs(_aside_name(p, reason)))


## Garde une copie du fichier `p` (qui reste en place).
static func _keep_copy(p: String, reason: String) -> void:
	DirAccess.copy_absolute(_abs(p), _abs(_aside_name(p, reason)))
