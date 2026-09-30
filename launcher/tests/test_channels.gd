extends RefCounted
## Canaux stable / snapshot, manifeste des versions en paquets, installation
## différentielle, réglages et script d'auto-mise à jour (docs/RELEASE.md),
## appelés par test_launcher.gd (seul point d'entrée). Fichiers écrits dans
## tests/_out/launcher_channels_test (supprimé à la fin), jamais chez le joueur.

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")
## Un dossier par processus : deux exécutions simultanées (check en parallèle
## d'un essai à la main) ne se marchent pas dessus.
var TMP := "res://tests/_out/launcher_channels_test_%d" % OS.get_process_id()
const DL := "https://github.com/" + Releases.REPO + "/releases/download/"

var t   # test_launcher.gd (check)


func run(tester) -> void:
	t = tester
	_tags()
	_releases()
	_manifest()
	_manifest_launcher()
	_launcher_update()
	_install()
	_settings()
	_update_script()


func _tags() -> void:
	t.check(Releases.is_safe_tag("v0.2.0-snapshot.37") and Releases.is_safe_tag("v0.2.1-snapshot.1"), "numéros de snapshot acceptés")
	var bad := ["v0.2.0-snapshot", "v0.2.0-snapshot.", "v0.2.0-snapshot.x", "v0.2.0-beta.1", "v0.2.0-snapshot.1234567",
		"v0.2.0-snapshot.1\n", "v0.2.0-SNAPSHOT.1", "v0.2.0-snapshot.1/..", "v0.2-snapshot.1.2"]
	t.check(bad.all(func(b): return not Releases.is_safe_tag(b)), "numéros de snapshot suspects refusés")
	t.check(Releases.channel_of("v0.2.0-snapshot.4") == Releases.SNAPSHOT and Releases.channel_of("v0.2.0") == Releases.STABLE
		and Releases.channel_of("v0.1.157") == Releases.STABLE, "canal d'après le numéro")
	t.check(Releases.snapshot_number("v0.2.0-snapshot.37") == 37 and Releases.snapshot_number("v0.2.0") == -1, "numéro de snapshot lu")
	var order := ["v0.1.157", "v0.2.0-snapshot.9", "v0.2.1-snapshot.1", "v0.2.0", "v0.2.0-snapshot.37", "v0.1.99"]
	order.sort_custom(func(a, b): return Releases.newer(a, b))
	t.check(order == ["v0.2.1-snapshot.1", "v0.2.0", "v0.2.0-snapshot.37", "v0.2.0-snapshot.9", "v0.1.157", "v0.1.99"],
		"ordre : stable après ses snapshots, snapshots par numéro %s" % [order])
	t.check(not Releases.newer("v0.2.0-snapshot.3", "v0.2.0-snapshot.3") and Releases.newer("v0.2.0", "v0.1.300"),
		"égalité et ordre avec les anciens numéros")


func _releases() -> void:
	var snap := "v0.2.0-snapshot.40"
	var api := [
		{"tag_name": snap, "prerelease": true, "name": null, "assets": [
			{"name": "manifest.json", "browser_download_url": DL + snap + "/manifest.json", "size": 900},
			{"name": "SHA256SUMS.txt", "browser_download_url": DL + snap + "/SHA256SUMS.txt", "size": 300}]},
		{"tag_name": "v0.2.0", "assets": [
			{"name": "ClaudeOfDutyZombie-v0.2.0.exe", "browser_download_url": DL + "v0.2.0/ClaudeOfDutyZombie-v0.2.0.exe", "size": 5},
			{"name": "manifest.json", "browser_download_url": DL + "v0.2.0/manifest.json", "size": 900}]},
		{"tag_name": "v0.1.157", "assets": [
			{"name": "ClaudeOfDutyZombie-v0.1.157.exe", "browser_download_url": DL + "v0.1.157/ClaudeOfDutyZombie-v0.1.157.exe", "size": 5}]},
	]
	var v := Releases.parse_releases(JSON.stringify(api))
	t.check(v.size() == 3 and v[0].tag == "v0.2.0" and v[0].channel == Releases.STABLE and v[0].manifest_url != ""
		and v[0].exe_url != "", "stable : exécutable complet (anciens lanceurs) ET manifeste")
	t.check(v[1].tag == snap and v[1].channel == Releases.SNAPSHOT and v[1].manifest_url == DL + snap + "/manifest.json"
		and v[1].exe_url == "", "snapshot en paquets seulement : jouable (manifeste)")
	t.check(v[2].channel == Releases.STABLE and v[2].manifest_url == "", "ancienne version : exécutable complet seulement")


## Manifeste valide de `tag` (modifiable par les tests de refus).
func _good(tag: String) -> Dictionary:
	return {"format": 1, "version": tag, "channel": "snapshot", "build": "0.2.0-snapshot.40",
		"engine": {"godot": "4.7.2", "file": "engine-4.7.2.exe", "sha256": "a".repeat(64), "size": 1000, "release": "v0.2.0-snapshot.30"},
		"packs": [
			{"id": "core", "file": "core-1a2b3c4d.pck", "sha256": "b".repeat(64), "size": 400, "release": tag, "main": true},
			{"id": "vox-fr", "lang": "fr", "file": "vox-fr-5e6f.pck", "sha256": "c".repeat(64), "size": 300, "release": "v0.2.0-snapshot.30"},
		]}


func _manifest() -> void:
	var tag := "v0.2.0-snapshot.40"
	var m := Releases.parse_manifest(JSON.stringify(_good(tag)), tag)
	t.check(not m.is_empty() and m.engine.godot == "4.7.2" and m.packs.size() == 2 and m.packs[0].main and not m.packs[1].main
		and m.packs[1].lang == "fr", "manifeste valide lu")
	t.check(m.engine.url == DL + "v0.2.0-snapshot.30/engine-4.7.2.exe" and m.packs[0].url == DL + tag + "/core-1a2b3c4d.pck",
		"adresses reconstruites à partir du numéro de release (jamais lues dans le fichier)")
	var cases := {
		"autre version": func(d): d.version = "v0.2.0-snapshot.41",
		"format inconnu": func(d): d.format = 2,
		"canal inconnu": func(d): d.channel = "beta",
		"build suspect": func(d): d.build = "x/../y",
		"moteur absent": func(d): d.erase("engine"),
		"version de Godot suspecte": func(d): d.engine.godot = "4.7.2; del",
		"somme courte": func(d): d.packs[0].sha256 = "b".repeat(63),
		"somme non hexadécimale": func(d): d.packs[0].sha256 = "g".repeat(64),
		"taille nulle": func(d): d.packs[0].size = 0,
		"taille énorme": func(d): d.packs[0].size = 1e12,
		"taille en texte": func(d): d.packs[0].size = "400",
		"fichier-chemin": func(d): d.packs[0].file = "../core.pck",
		"mauvaise extension": func(d): d.packs[0].file = "core.exe",
		"moteur non .exe": func(d): d.engine.file = "engine.pck",
		"release suspecte": func(d): d.packs[1].release = "v0.2.0/../../x",
		"aucun paquet": func(d): d.packs = [],
		"deux principaux": func(d): d.packs[1].main = true,
		"aucun principal": func(d): d.packs[0].main = false,
		"identifiant en double": func(d): d.packs[1].id = "core",
		"langue inconnue": func(d): d.packs[1].lang = "de",
		"trop de paquets": func(d): for i in 8: d.packs.append({"id": "p%d" % i, "file": "p%d.pck" % i, "sha256": "d".repeat(64), "size": 1, "release": tag}),
		"paquet non objet": func(d): d.packs.append("x"),
	}
	var accepted := []
	for what in cases:
		var d := _good(tag)
		cases[what].call(d)
		if not Releases.parse_manifest(JSON.stringify(d), tag).is_empty():
			accepted.append(what)
	t.check(accepted.is_empty(), "manifestes piégés refusés (%d cas) %s" % [cases.size(), accepted])
	t.check(Releases.parse_manifest("[1]", tag).is_empty() and Releases.parse_manifest("\"texte\"", tag).is_empty()
		and Releases.parse_manifest(" ".repeat(Releases.MAX_MANIFEST_BYTES + 1), tag).is_empty(), "manifeste illisible ou trop gros refusé")


## Entrée « launcher » valide (lanceur 8, publié avec une snapshot plus ancienne).
func _launcher_entry() -> Dictionary:
	return {"version": 8, "file": "ClaudeOfDutyZombie-Launcher.exe", "sha256": "e".repeat(64), "size": 110000000,
		"release": "v0.2.0-snapshot.38", "inputs": "f".repeat(64)}


func _manifest_launcher() -> void:
	var tag := "v0.2.0-snapshot.40"
	# Manifestes déjà publiés (v0.2.0-snapshot.165 à 167) : pas d'entrée « launcher ».
	var old := Releases.parse_manifest(JSON.stringify(_good(tag)), tag)
	t.check(not old.is_empty() and not old.has("launcher"), "manifeste sans entrée « launcher » (snapshots 165 à 167) accepté")
	var d := _good(tag)
	d.launcher = _launcher_entry()
	var m := Releases.parse_manifest(JSON.stringify(d), tag)
	t.check(not m.is_empty() and m.launcher.version == 8 and m.launcher.version is int and m.launcher.size == 110000000
		and m.launcher.sha256 == "e".repeat(64) and m.launcher.url == DL + "v0.2.0-snapshot.38/ClaudeOfDutyZombie-Launcher.exe",
		"entrée « launcher » lue, adresse reconstruite vers la release qui le porte")
	var ml := d.duplicate(true)
	ml.launcher.sha256 = "E".repeat(64)
	t.check(Releases.parse_manifest(JSON.stringify(ml), tag).get("launcher", {}).get("sha256", "") == "e".repeat(64),
		"somme du lanceur en majuscules ramenée en minuscules")
	var cases := {
		"lanceur non objet": func(d): d.launcher = "ClaudeOfDutyZombie-Launcher.exe",
		"lanceur null": func(d): d.launcher = null,
		"numéro absent": func(d): d.launcher.erase("version"),
		"numéro nul": func(d): d.launcher.version = 0,
		"numéro négatif": func(d): d.launcher.version = -3,
		"numéro décimal": func(d): d.launcher.version = 8.5,
		"numéro en texte": func(d): d.launcher.version = "8",
		"numéro énorme": func(d): d.launcher.version = 1e9,
		"fichier absent": func(d): d.launcher.erase("file"),
		"fichier-chemin": func(d): d.launcher.file = "../ClaudeOfDutyZombie-Launcher.exe",
		"fichier caché": func(d): d.launcher.file = ".Launcher.exe",
		"lanceur non .exe": func(d): d.launcher.file = "ClaudeOfDutyZombie-Launcher.bat",
		"somme courte": func(d): d.launcher.sha256 = "e".repeat(63),
		"somme non hexadécimale": func(d): d.launcher.sha256 = "z".repeat(64),
		"somme absente": func(d): d.launcher.erase("sha256"),
		"taille nulle": func(d): d.launcher.size = 0,
		"taille énorme": func(d): d.launcher.size = 1e12,
		"taille en texte": func(d): d.launcher.size = "110000000",
		"release suspecte": func(d): d.launcher.release = "v0.2.0/../../evil",
		"release d'un autre format": func(d): d.launcher.release = "latest",
		"release absente": func(d): d.launcher.erase("release"),
	}
	var accepted := []
	for what in cases:
		var bad := _good(tag)
		bad.launcher = _launcher_entry()
		cases[what].call(bad)
		if not Releases.parse_manifest(JSON.stringify(bad), tag).is_empty():
			accepted.append(what)
	t.check(accepted.is_empty(), "entrées « launcher » piégées : tout le manifeste refusé (%d cas) %s" % [cases.size(), accepted])


func _launcher_update() -> void:
	var s38 := "v0.2.0-snapshot.38"
	var s40 := "v0.2.0-snapshot.40"
	var s41 := "v0.2.0-snapshot.41"
	var a := func(tag: String, n: String, size: int) -> Dictionary:
		return {"name": n, "size": size, "browser_download_url": DL + tag + "/" + n}
	var api := [
		# Snapshot récente, sans lanceur joint (lanceur inchangé) : manifeste + sommes + core.
		{"tag_name": s41, "prerelease": true, "assets": [a.call(s41, "manifest.json", 1), a.call(s41, "SHA256SUMS.txt", 1),
			a.call(s41, "core-1a2b3c4d.pck", 1)]},
		# Snapshot publiée avant l'entrée « launcher » : lanceur joint + launcher_version.txt.
		{"tag_name": s40, "prerelease": true, "assets": [a.call(s40, "manifest.json", 1), a.call(s40, "SHA256SUMS.txt", 1),
			a.call(s40, "ClaudeOfDutyZombie-Launcher.exe", 110000000), a.call(s40, "launcher_version.txt", 1)]},
		# Stable : exécutable complet, lanceurs, numéro, manifeste.
		{"tag_name": "v0.1.160", "assets": [a.call("v0.1.160", "ClaudeOfDutyZombie-v0.1.160.exe", 1),
			a.call("v0.1.160", "ClaudeOfDutyZombie-Launcher.exe", 109000000), a.call("v0.1.160", "CallOfClaudeZombie-Launcher.exe", 109000000),
			a.call("v0.1.160", "launcher_version.txt", 1), a.call("v0.1.160", "SHA256SUMS.txt", 1)]},
		# Stable ancienne sans sommes.
		{"tag_name": "v0.1.100", "assets": [a.call("v0.1.100", "ClaudeOfDutyZombie-v0.1.100.exe", 1),
			a.call("v0.1.100", "ClaudeOfDutyZombie-Launcher.exe", 1), a.call("v0.1.100", "launcher_version.txt", 1)]},
	]
	var v := Releases.parse_releases(JSON.stringify(api))
	# Canal choisi seulement : la plus récente de CE canal.
	var snap := Releases.launcher_release(v, Releases.SNAPSHOT)
	var stable := Releases.launcher_release(v, Releases.STABLE)
	t.check(snap.get("tag", "") == s41 and stable.get("tag", "") == "v0.1.160", "lanceur : dernière release du canal choisi (%s, %s)"
		% [snap.get("tag", ""), stable.get("tag", "")])
	t.check(Releases.launcher_release(v.filter(func(e): return e.channel == Releases.STABLE), Releases.SNAPSHOT).is_empty(),
		"lanceur : aucune release du canal, rien à faire (jamais celui d'un autre canal)")
	t.check(Releases.launcher_mode(snap) == Releases.LAUNCHER_BY_MANIFEST and Releases.launcher_mode(stable) == Releases.LAUNCHER_BY_ASSETS,
		"lanceur : manifeste d'abord, sinon fichiers joints")
	var no_sums := v.filter(func(e): return e.tag == "v0.1.100")[0] as Dictionary
	t.check(Releases.launcher_mode(no_sums) == "" and Releases.launcher_mode({}) == "", "lanceur : jamais depuis une release sans sommes")
	# Décision depuis le manifeste (vérifié) de la snapshot 41.
	var d := _good(s41)
	d.launcher = _launcher_entry()
	var m := Releases.parse_manifest(JSON.stringify(d), s41)
	var l := Releases.launcher_from_manifest(m, 7)
	t.check(l.get("version", 0) == 8 and l.get("url", "") == DL + s38 + "/ClaudeOfDutyZombie-Launcher.exe"
		and l.get("sha256", "") == "e".repeat(64) and l.get("size", 0) == 110000000,
		"lanceur 7 : le lanceur 8 du manifeste est téléchargé depuis la release qui le porte, somme et taille du manifeste")
	t.check(Releases.launcher_from_manifest(m, 8).is_empty() and Releases.launcher_from_manifest(m, 9).is_empty(),
		"lanceur à jour ou plus récent : rien à faire (jamais de retour en arrière)")
	var old := Releases.parse_manifest(JSON.stringify(_good(s41)), s41)
	t.check(Releases.launcher_from_manifest(old, 1).is_empty() and not old.has("launcher"),
		"manifeste sans entrée « launcher » : aucune décision (repli sur l'ancien mécanisme)")
	# Repli : snapshot 40 (manifeste sans entrée) -> fichiers joints à la release.
	var s40v := v.filter(func(e): return e.tag == s40)[0] as Dictionary
	t.check(Releases.launcher_mode(s40v) == Releases.LAUNCHER_BY_MANIFEST and Releases.has_launcher_assets(s40v),
		"snapshot 165 à 167 : manifeste lu d'abord, fichiers joints disponibles pour le repli")
	var sums := Releases.parse_sums("%s  ClaudeOfDutyZombie-Launcher.exe\n%s  manifest.json\n" % ["1".repeat(64), "2".repeat(64)])
	var la := Releases.launcher_from_assets(s40v, "8\r\n", sums, 7)
	t.check(la.get("version", 0) == 8 and la.get("url", "") == DL + s40 + "/ClaudeOfDutyZombie-Launcher.exe"
		and la.get("sha256", "") == "1".repeat(64) and la.get("size", 0) == 110000000, "repli : launcher_version.txt + lanceur joint + somme publiée")
	t.check(Releases.launcher_from_assets(s40v, "7", sums, 7).is_empty() and Releases.launcher_from_assets(s40v, "6", sums, 7).is_empty(),
		"repli : numéro égal ou plus petit, rien à faire")
	t.check(Releases.launcher_from_assets(s40v, "8", {}, 7).is_empty() and Releases.launcher_from_assets(s40v, "huit", sums, 7).is_empty()
		and Releases.launcher_from_assets(s40v, "99999999", sums, 7).is_empty() and Releases.launcher_from_assets(snap, "8", sums, 7).is_empty(),
		"repli : somme absente, numéro illisible ou énorme, release sans lanceur joint : refusé")
	# Ancienne stable : le lanceur au nouveau nom est préféré (et sa somme).
	var sums_st := Releases.parse_sums("%s  ClaudeOfDutyZombie-Launcher.exe\n%s  CallOfClaudeZombie-Launcher.exe\n" % ["3".repeat(64), "4".repeat(64)])
	t.check(Releases.launcher_from_assets(stable, "8", sums_st, 7).get("sha256", "") == "3".repeat(64), "stable : lanceur au nouveau nom et sa somme")


## Fichier de contenu `text` et sa somme.
func _put(path: String, text: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return {"sha256": FileAccess.get_sha256(path), "size": text.to_utf8_buffer().size()}


func _install() -> void:
	var root := ProjectSettings.globalize_path(TMP)
	_rmtree(root)
	Store.root = root + "/versions"
	DirAccess.make_dir_recursive_absolute(Store.root)
	var tag := "v0.2.0-snapshot.40"
	# Contenus réels des fichiers (sommes calculées), rangés à part.
	var src := root + "/src"
	var e := _put(src + "/engine.exe", "moteur")
	var c := _put(src + "/core.pck", "coeur du jeu")
	var vf := _put(src + "/vox.pck", "voix françaises")
	var d := _good(tag)
	d.engine.sha256 = e.sha256
	d.engine.size = e.size
	d.packs[0].sha256 = c.sha256
	d.packs[0].size = c.size
	d.packs[1].sha256 = vf.sha256
	d.packs[1].size = vf.size
	var text := JSON.stringify(d)
	var m := Releases.parse_manifest(text, tag)
	var miss := Store.missing_files(m)
	t.check(miss.size() == 3 and miss[0].path == Store.engine_path("4.7.2"), "rien d'installé : moteur + 2 paquets à télécharger")
	t.check(not Store.install_manifest(tag, m, text) and not Store.is_installed(tag), "installation refusée tant que des fichiers manquent")
	# Fichiers « téléchargés » : moteur au bon endroit, paquets rangés par somme.
	DirAccess.make_dir_recursive_absolute(Store.engine_path("4.7.2").get_base_dir())
	DirAccess.copy_absolute(src + "/engine.exe", Store.engine_path("4.7.2"))
	DirAccess.make_dir_recursive_absolute(Store.store_dir())
	DirAccess.copy_absolute(src + "/core.pck", Store.stored_path(c.sha256, "pck"))
	_put(Store.stored_path(vf.sha256, "pck"), "voix ABÎMÉES")
	miss = Store.missing_files(m)
	t.check(miss.size() == 1 and miss[0].sha256 == vf.sha256, "fichier abîmé (somme fausse) : à retélécharger, les autres gardés")
	DirAccess.copy_absolute(src + "/vox.pck", Store.stored_path(vf.sha256, "pck"))
	t.check(Store.missing_files(m).is_empty(), "tout est là : rien à télécharger (mise à jour différentielle)")
	t.check(Store.install_manifest(tag, m, text) and Store.is_installed(tag), "version installée à partir des paquets")
	var dir := Store.root + "/" + tag
	t.check(FileAccess.get_file_as_string(dir + "/" + Store.PACK_NAME) == "coeur du jeu"
		and FileAccess.get_file_as_string(dir + "/" + Store.EXE_NAME) == "moteur"
		and not FileAccess.file_exists(dir + "/" + Store.EXE_NAME + ".part"), "copies du moteur et du core, même nom (chargement automatique)")
	var args := Store.launch_args(tag)
	t.check(args.size() == 2 and args[0] == "--" and args[1] == "--packs=" + Store.stored_path(vf.sha256, "pck"),
		"lancement : paquet des voix passé au jeu (%s)" % " ".join(args))
	t.check(Store.launch_args("v0.1.157").is_empty() and Store.launch_args("../x").is_empty(), "ancienne version / numéro suspect : aucun argument")
	# Deuxième version qui réutilise le même moteur et les mêmes voix : seul le core change.
	var tag2 := "v0.2.0-snapshot.41"
	var c2 := _put(src + "/core2.pck", "coeur du jeu v2")
	var d2 := d.duplicate(true)
	d2.version = tag2
	d2.packs[0].sha256 = c2.sha256
	d2.packs[0].size = c2.size
	d2.packs[0].release = tag2
	var m2 := Releases.parse_manifest(JSON.stringify(d2), tag2)
	var miss2 := Store.missing_files(m2)
	t.check(miss2.size() == 1 and miss2[0].sha256 == c2.sha256 and miss2[0].url == DL + tag2 + "/core-1a2b3c4d.pck",
		"version suivante : seul le core est téléchargé")
	# Suppression : les paquets encore utilisés restent, les autres partent.
	DirAccess.copy_absolute(src + "/core2.pck", Store.stored_path(c2.sha256, "pck"))
	Store.remove(tag)
	var removed := Store.prune_store()
	t.check(removed == 3 and not FileAccess.file_exists(Store.stored_path(c.sha256, "pck")),
		"version supprimée : ses paquets inutilisés effacés (%d)" % removed)
	Store.root = ""
	_rmtree(root)
	t.check(not DirAccess.dir_exists_absolute(root), "dossier temporaire des versions en paquets supprimé")


func _settings() -> void:
	var path := ProjectSettings.globalize_path(TMP + "_settings.cfg")
	Store.settings_path = path
	Store.save_settings({"language": "en", "selected": "v0.2.0", "channel": Releases.SNAPSHOT, "selected_snapshot": "v0.2.0-snapshot.40"})
	var s := Store.load_settings()
	t.check(s.language == "en" and s.channel == Releases.SNAPSHOT and s.selected == "v0.2.0" and s.selected_snapshot == "v0.2.0-snapshot.40",
		"réglages : canal et version de chaque canal mémorisés")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[launcher]\nlanguage=\"fr\"\nchannel=\"beta\"\nselected_snapshot=\"../x\"\n")
	f.close()
	s = Store.load_settings()
	t.check(s.channel == Releases.STABLE and s.selected_snapshot == "latest", "canal ou version suspects : valeurs par défaut")
	DirAccess.remove_absolute(path)
	Store.settings_path = ""


func _update_script() -> void:
	var bat := Store.update_script("C:/Jeux/Claude 100%/ClaudeOfDutyZombie-Launcher.exe", "C:/Jeux/Claude 100%/new.exe",
		"C:/Users/x/AppData/Roaming/L/launcher_update.ok", "C:/Users/x/AppData/Roaming/L/logs/launcher_update.log")
	t.check("set \"CUR=C:\\Jeux\\Claude 100%%\\ClaudeOfDutyZombie-Launcher.exe\"" in bat, "script : chemins Windows, « % » doublé")
	var i_move := bat.find("move /y \"%CUR%\" \"%BAK%\"")
	var i_new := bat.find("move /y \"%NEW%\" \"%CUR%\"")
	var i_start := bat.find("start \"\" \"%CUR%\" --updated")
	var i_ok := bat.find("if exist \"%OK%\" goto done")
	var i_restore := bat.find("move /y \"%BAK%\" \"%CUR%\"")
	t.check(i_move > 0 and i_move < i_new and i_new < i_start and i_start < i_ok and i_ok < i_restore,
		"script : sauvegarde, remplacement, démarrage, attente du signal, retour arrière (dans cet ordre)")
	t.check("--update-failed" in bat and "taskkill /f /im \"ClaudeOfDutyZombie-Launcher.exe\"" in bat and "if %n% lss 45 goto wait" in bat,
		"script : nouveau lanceur arrêté puis ancien relancé si aucun signal en 90 s")
	t.check(bat.count(">>\"%LOG%\"") >= 5 and bat.ends_with("del \"%~f0\"\r\n"), "script : chaque étape journalisée, script effacé à la fin")


func _rmtree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rmtree(dir + "/" + sub)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
