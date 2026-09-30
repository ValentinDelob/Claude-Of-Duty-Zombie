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
