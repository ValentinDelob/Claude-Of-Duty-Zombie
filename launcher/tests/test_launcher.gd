extends SceneTree
## Tests du lanceur (sans réseau) :
##   godot --headless --path launcher -s res://tests/test_launcher.gd
## Lecture des releases GitHub, ordre des versions, notes de version (et repli),
## versions installées et téléchargement terminé ; sécurité : domaines et
## adresses autorisés, numéros de version et noms de fichiers sûrs, sommes
## SHA-256 et politique des anciennes versions, BBCode échappé, images bornées,
## réglages piégés ignorés ; réponses de l'API mal formées, releases en
## préversion (canal snapshot), fichiers joints et adresses piégés, versions à 3 et 4 nombres,
## SHA256SUMS.txt abîmé ; textes du lanceur en français et en anglais ; journaux
## et rapports de plantage (tests/test_crash_log.gd). Fichiers écrits dans
## tests/_out seulement (jamais dans le dossier du joueur, user://).

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")
const Texts := preload("res://scripts/texts.gd")
const CrashLogTests := preload("res://tests/test_crash_log.gd")
const ChannelTests := preload("res://tests/test_channels.gd")

const DL := "https://github.com/ValentinDelob/Claude-Of-Duty-Zombie/releases/download/"

var failures := 0


func check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "ÉCHEC ") + what)
	if not ok:
		failures += 1


func _asset(tag: String, n: String, size := 1) -> Dictionary:
	return {"name": n, "size": size, "browser_download_url": DL + tag + "/" + n}


func _init() -> void:
	var api := JSON.stringify([
		{"tag_name": "v0.1.99", "name": "v0.1.99 — Merge branch 'x'", "published_at": "2026-09-28T10:00:00Z",
			"assets": [_asset("v0.1.99", "CallOfClaudeZombie-v0.1.99.exe", 1000)]},
		{"tag_name": "v0.1.116", "name": "v0.1.116 — feat: release KINO V2", "published_at": "2026-09-28T20:00:00Z",
			"assets": [_asset("v0.1.116", "ClaudeOfDutyZombie-v0.1.116.exe", 2000),
				_asset("v0.1.116", "CallOfClaudeZombie-Launcher.exe", 50),
				_asset("v0.1.116", "ClaudeOfDutyZombie-Launcher.exe", 50),
				_asset("v0.1.116", "launcher_version.txt"),
				_asset("v0.1.116", "SHA256SUMS.txt")]},
		{"tag_name": "v0.1.9", "name": "v0.1.9", "published_at": "2026-09-01T00:00:00Z", "assets": []},
		{"tag_name": "v0.1.100", "name": "brouillon", "draft": true, "assets": []},
		# Pièges : numéro de version-chemin, exécutable hors de GitHub ou d'un autre dépôt.
		{"tag_name": "../../evil", "name": "x", "assets": [_asset("../../evil", "ClaudeOfDutyZombie-v9.exe")]},
		{"tag_name": "v0.1.200", "name": "x", "assets": [
			{"name": "ClaudeOfDutyZombie-v0.1.200.exe", "size": 1, "browser_download_url": "https://evil.example/v.exe"}]},
		{"tag_name": "v0.1.201", "name": "x", "assets": [
			{"name": "ClaudeOfDutyZombie-v0.1.201.exe", "size": 1, "browser_download_url": "https://github.com/evil/repo/releases/download/v0.1.201/ClaudeOfDutyZombie-v0.1.201.exe"}]},
		{"tag_name": "v0.1.202", "name": "x", "assets": [
			{"name": "ClaudeOfDutyZombie-v0.1.202.exe", "size": 1, "browser_download_url": "http://github.com/ValentinDelob/Claude-Of-Duty-Zombie/releases/download/v0.1.202/ClaudeOfDutyZombie-v0.1.202.exe"}]},
		"pas un objet",
	])
	var v := Releases.parse_releases(api)
	check(v.size() == 2, "releases jouables seulement (sans exe, brouillon, piégées : ignorées) : %d" % v.size())
	check(v[0].tag == "v0.1.116" and v[1].tag == "v0.1.99", "plus récente d'abord (ordre numérique, pas alphabétique)")
	check(v[0].launcher_url == DL + "v0.1.116/ClaudeOfDutyZombie-Launcher.exe" and v[0].launcher_version_url != "", "lanceur (nouveau nom prioritaire) et sa version repérés")
	check(v[1].exe_url == DL + "v0.1.99/CallOfClaudeZombie-v0.1.99.exe", "anciennes versions (ancien nom du jeu) toujours reconnues")
	check(v[0].date == "2026-09-28" and v[0].exe_size == 2000, "date et taille")
	check(v[0].title == "release KINO V2", "titre sans numéro ni préfixe technique")
	check(v[0].sums_url != "" and v[1].sums_url == "" and v[0].exe_name == "ClaudeOfDutyZombie-v0.1.116.exe", "SHA256SUMS.txt et nom de l'exécutable repérés")
	check(Releases.newer("v0.1.116", "v0.1.99") and not Releases.newer("v0.1.99", "v0.1.116"), "comparaison de versions")
	check(Releases.newer("v0.2.0", "v0.1.300"), "version mineure prioritaire")

	# Adresses : HTTPS, domaines GitHub seulement (redirections comprises).
	check(Releases.is_allowed_url("https://api.github.com/repos/x") and Releases.is_allowed_url("https://release-assets.githubusercontent.com/a?b=1")
		and Releases.is_allowed_url("https://raw.githubusercontent.com/x/y"), "domaines GitHub autorisés")
	var bad_urls := ["http://github.com/x", "https://github.com.evil.com/x", "https://evilgithub.com/x",
		"https://github.com@evil.com/x", "https://evil.com#@github.com", "https://github.com:8443/x",
		"ftp://github.com/x", "https://gith\\ub.com/x", "https://github.com/a b", "file:///C:/x.exe", ""]
	var accepted := bad_urls.filter(func(u): return Releases.is_allowed_url(u))
	check(accepted.is_empty(), "adresses piégées refusées %s" % [accepted])
	check(Releases.header(PackedStringArray(["Server: x", "location: https://github.com/y"]), "Location") == "https://github.com/y", "en-tête Location lu")

	# Numéros de version et noms devenant des chemins.
	check(Releases.is_safe_tag("v0.1.116") and Releases.is_safe_tag("v1.2") and not Releases.is_safe_tag("v0.1.116/../x")
		and not Releases.is_safe_tag("..") and not Releases.is_safe_tag("v0.1.1\\x") and not Releases.is_safe_tag(""), "numéros de version sûrs")
	check(Releases.is_safe_image_name("v0.1.116/01.jpg") and not Releases.is_safe_image_name("../../launcher.cfg")
		and not Releases.is_safe_image_name("v0.1/../../x.png") and not Releases.is_safe_image_name("/etc/x.png")
		and not Releases.is_safe_image_name("a.tscn") and not Releases.is_safe_image_name("C:/x.png"), "noms de captures sûrs")

	# Sommes SHA-256 et politique des versions sans sommes.
	var hx := "a".repeat(64)
	var sums := Releases.parse_sums("%s  ClaudeOfDutyZombie-v0.1.116.exe\r\n%s *ClaudeOfDutyZombie-Launcher.exe\nnimporte quoi\n%s  ../x.exe\n" % [hx, "B".repeat(64), hx])
	check(sums.get("ClaudeOfDutyZombie-v0.1.116.exe") == hx and sums.get("ClaudeOfDutyZombie-Launcher.exe") == "b".repeat(64)
		and sums.size() == 3, "SHA256SUMS.txt lu (format sha256sum, binaire compris) %s" % [sums.keys()])
	check(Releases.integrity(v, "v0.1.116") == Releases.VERIFIED, "release avec sommes : vérifiée")
	check(Releases.integrity(v, "v0.1.99") == Releases.LEGACY, "release plus ancienne que les sommes : ancienne (taille vérifiée)")
	var newer_unsigned := v.duplicate(true)
	newer_unsigned.push_front({"tag": "v0.1.130", "sums_url": ""})
	check(Releases.integrity(newer_unsigned, "v0.1.130") == Releases.REFUSED, "release récente sans sommes : refusée")
	check(Releases.integrity([{"tag": "v0.1.5", "sums_url": ""}], "v0.1.5") == Releases.LEGACY, "aucune release avec sommes : anciennes versions acceptées")

	# Notes : BBCode neutralisé, captures au nom suspect ignorées.
	var cl := {"versions": {"v0.1.116": {"title": {"fr": "KINO renaît", "en": "KINO reborn"},
		"items": [{"fr": "Une salle", "en": "A room"}], "images": ["v0.1.116/01.jpg", "../../launcher.cfg"]}}}
	var n := Releases.notes(cl, "v0.1.116", "en")
	check(n.title == "KINO reborn" and n.items == ["A room"] and n.images == ["v0.1.116/01.jpg"], "notes en anglais (capture piégée ignorée)")
	check(Releases.notes(cl, "v0.1.116", "fr").title == "KINO renaît", "notes en français")
	var none := Releases.notes(cl, "v0.1.99", "fr", "Titre GitHub")
	check(none.title == "Titre GitHub" and none.items.is_empty() and not none.found, "sans notes : titre de la release")
	check(Releases.notes({"versions": "x"}, "v0.1.1", "fr").items.is_empty(), "notes mal formées : aucune erreur")
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = Releases.escape_bbcode("[url=https://evil]clic[/url] [img]user://x.png[/img]")
	check(rtl.get_parsed_text() == "[url=https://evil]clic[/url] [img]user://x.png[/img]", "BBCode des notes affiché tel quel : %s" % rtl.get_parsed_text())
	rtl.free()

	# Images : format lu dans les octets, dimensions bornées avant décodage.
	var img := Image.create(8, 4, false, Image.FORMAT_RGB8)
	var png := img.save_png_to_buffer()
	var jpg := img.save_jpg_to_buffer()
	check(Releases.image_size(png) == Vector2i(8, 4) and Releases.image_size(jpg) == Vector2i(8, 4), "dimensions PNG / JPEG lues dans l'en-tête")
	check(Releases.image_ok(png) and Releases.image_ok(jpg), "petites captures acceptées")
	var huge := png.duplicate()
	# Largeur annoncée : 50 000 px (entier big endian de l'en-tête IHDR).
	huge[16] = 0x00
	huge[17] = 0x00
	huge[18] = 0xC3
	huge[19] = 0x50
	check(not Releases.image_ok(huge), "image géante refusée avant décodage")
	check(not Releases.image_ok("<html>".to_utf8_buffer()), "fichier qui n'est pas une image refusé")

	# Notes publiées dans le dépôt : chaque version a un titre et des puces dans les deux langues.
	var f := FileAccess.open("res://../changelogs/changelogs.json", FileAccess.READ)
	if f:
		var real: Dictionary = JSON.parse_string(f.get_as_text())
		var bad: Array = []
		for tag in real.versions:
			var e: Dictionary = real.versions[tag]
			if String(e.title.get("fr", "")) == "" or String(e.title.get("en", "")) == "" or e.items.is_empty():
				bad.append(tag)
			for im in e.get("images", []):
				if not FileAccess.file_exists("res://../changelogs/img/" + String(im)) or not Releases.is_safe_image_name(String(im)):
					bad.append(im)
		check(bad.is_empty(), "changelogs.json : %d versions complètes, captures présentes %s" % [real.versions.size(), bad])

	# Versions installées : dossier temporaire (hors du dossier du joueur).
	Store.root = ProjectSettings.globalize_path("res://tests/_out/launcher_versions_test")
	for t in ["v0.1.1", "v0.1.2"]:
		Store.remove(t)
	check(Store.installed().is_empty(), "aucune version installée au départ")
	Store.prepare_dir("v0.1.2")
	var part := FileAccess.open(Store.part_path("v0.1.2"), FileAccess.WRITE)
	part.store_string("exe")
	part.close()
	check(not Store.is_installed("v0.1.2"), "téléchargement en cours : pas encore installée")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("exe".to_utf8_buffer())
	var good := ctx.finish().hex_encode()
	check(Store.verify_file(Store.part_path("v0.1.2"), good, 3), "fichier conforme : taille et SHA-256")
	check(not Store.verify_file(Store.part_path("v0.1.2"), "0".repeat(64), 3), "SHA-256 différente : refusé")
	check(not Store.verify_file(Store.part_path("v0.1.2"), good, 4), "taille différente (téléchargement incomplet) : refusé")
	check(Store.finish_download("v0.1.2") and Store.is_installed("v0.1.2"), "téléchargement terminé : installée")
	check(Store.installed() == ["v0.1.2"], "liste des versions installées")
	check(Store.exe_path("../..") == "" and Store.part_path("..") == "" and not Store.is_installed("../v0.1.2"), "numéro de version-chemin : aucun chemin")
	Store.remove("..")
	check(DirAccess.dir_exists_absolute(Store.root), "suppression d'un numéro-chemin : rien d'effacé")
	Store.remove("v0.1.2")
	check(not Store.is_installed("v0.1.2"), "version supprimée")
	DirAccess.remove_absolute(Store.root)
	check(not DirAccess.dir_exists_absolute(Store.root), "dossier temporaire des versions supprimé")
	Store.root = ""

	# Réglages du lanceur : jamais d'objet ni de ressource décodés.
	check(Store.has_constructor("[launcher]\nselected=Object(Node,\"script\":Resource(\"user://x.gd\"))\n"), "réglages piégés détectés")
	check(Store.has_constructor("[launcher]\nlanguage=\"fr\" ; c\nselected=Resource (\"user://x.gd\")\n"), "constructeur après un commentaire détecté")
	check(not Store.has_constructor("[launcher]\nlanguage=\"fr\"\nselected=\"Object(latest)\" ; Object(\n"), "texte ordinaire (même avec « Object( » entre guillemets) accepté")
	_settings()
	_api_edge_cases()
	_tags_and_versions()
	_sums_edge_cases()
	_texts()
	CrashLogTests.new().run(self)
	ChannelTests.new().run(self)
	print("LAUNCHER: %d échec(s)" % failures)
	quit(1 if failures > 0 else 0)


## Réglages : lecture seule. Store.SETTINGS est une constante (user://launcher.cfg,
## le vrai fichier du joueur) : save_settings n'est jamais appelé ici.
func _settings() -> void:
	var s := Store.load_settings()
	check(s.get("language") in ["fr", "en"] and (s.get("selected") == "latest" or Releases.is_safe_tag(String(s.get("selected")))),
		"réglages lus : langue et version choisie toujours valides %s" % [s])


## Réponses de l'API mal formées : aucune erreur, rien de jouable inventé.
func _api_edge_cases() -> void:
	for text in ["{\"message\": \"API rate limit exceeded\"}", "[]", "\"texte\"", "42", "null", "[1, null, [], \"x\", true]"]:
		check(Releases.parse_releases(text).is_empty(), "API mal formée : aucune version (%s)" % text)
	# Champs null ou d'un autre type (GitHub : « "name": null » sans titre) :
	# la release est lue quand même, les autres ne disparaissent pas.
	var ok_exe := "ClaudeOfDutyZombie-v0.1.7.exe"
	var typed := JSON.stringify([
		{"tag_name": "v0.1.7", "name": null, "published_at": null, "assets": [
			{"name": ok_exe, "browser_download_url": "https://github.com/" + Releases.REPO + "/releases/download/v0.1.7/" + ok_exe, "size": null}]},
		{"tag_name": 42, "name": ["x"], "assets": []},
		{"tag_name": "v0.1.6", "name": {"a": 1}, "assets": [
			{"name": 5, "browser_download_url": null, "size": "gros"}]},
	])
	var got := Releases.parse_releases(typed)
	check(got.size() == 1 and got[0].tag == "v0.1.7" and got[0].title == "" and got[0].exe_size == 0,
		"champs null ou mal typés : release lue quand même, aucune erreur (%d)" % got.size())
	check(not Releases.is_safe_tag("v0.1.5\n") and not Releases.is_safe_asset_name("x.exe\n")
		and not Releases.is_safe_image_name("v0.1.5/01.jpg\n"), "saut de ligne final refusé (tag, fichier, capture)")
	var tag := "v0.1.5"
	var exe := "ClaudeOfDutyZombie-v0.1.5.exe"
	var good := _asset(tag, exe, 10)
	var base := {"tag_name": tag, "name": "v0.1.5", "published_at": "2026-09-01T00:00:00Z"}
	var cases := {
		"brouillon": {"draft": true, "assets": [good]},
		"fichiers pas en liste": {"assets": {"0": good}},
		"fichiers absents": {},
		"fichier pas un objet": {"assets": ["https://github.com/x.exe", 3]},
		"adresse d'un autre dépôt": {"assets": [_named(exe, "https://github.com/ValentinDelob/Autre/releases/download/v0.1.5/" + exe)]},
		"adresse d'une autre version": {"assets": [_named(exe, DL + "v0.1.4/" + exe)]},
		"adresse http": {"assets": [_named(exe, DL.replace("https://", "http://") + tag + "/" + exe)]},
		"adresse avec identifiant": {"assets": [_named(exe, DL.replace("https://", "https://user:pw@") + tag + "/" + exe)]},
		"adresse avec port": {"assets": [_named(exe, DL.replace("github.com", "github.com:443") + tag + "/" + exe)]},
		"adresse avec barre inverse": {"assets": [_named(exe, DL + tag + "/..\\" + exe)]},
		"adresse avec espace": {"assets": [_named(exe, DL + tag + "/ " + exe)]},
		"adresse vide": {"assets": [_named(exe, "")]},
		"nom-chemin": {"assets": [_named("../" + exe, DL + tag + "/" + exe)]},
		"nom avec barre inverse": {"assets": [_named("x\\" + exe, DL + tag + "/" + exe)]},
		"nom caché": {"assets": [_named("." + exe, DL + tag + "/" + exe)]},
		"nom trop long": {"assets": [_named("ClaudeOfDutyZombie-v" + "1".repeat(100) + ".exe", DL + tag + "/x.exe")]},
		"pas un exécutable": {"assets": [_asset(tag, "ClaudeOfDutyZombie-v0.1.5.zip")]},
		"lanceur seul": {"assets": [_asset(tag, "ClaudeOfDutyZombie-Launcher.exe"), _asset(tag, "SHA256SUMS.txt")]},
		"numéro de version-chemin": {"tag_name": "v0.1.5/..", "assets": [good]},
		"numéro de version à 5 nombres": {"tag_name": "v0.1.5.1.1", "assets": [_asset("v0.1.5.1.1", "ClaudeOfDutyZombie-v0.1.5.1.1.exe")]},
	}
	var accepted: Array = []
	for what in cases:
		var r := base.duplicate()
		r.merge(cases[what], true)
		if not Releases.parse_releases(JSON.stringify([r])).is_empty():
			accepted.append(what)
	check(accepted.is_empty(), "releases piégées ou non jouables ignorées (%d cas) %s" % [cases.size(), accepted])
	# Une release piégée n'empêche pas les autres ; valeurs bornées.
	var mixed := [
		{"tag_name": tag, "name": "x".repeat(1000), "published_at": "2026-09-01T00:00:00Z", "assets": [
			"pas un objet", _asset(tag, exe, -5), _named("../evil.exe", DL + tag + "/evil.exe"),
			_named("ClaudeOfDutyZombie-Launcher.exe", "https://evil.example/l.exe")]},
		{"tag_name": "v0.1.6", "prerelease": true, "assets": [_asset("v0.1.6", "ClaudeOfDutyZombie-v0.1.6.exe")]},
		{"tag_name": "v0.1.4.2", "assets": [_asset("v0.1.4.2", "ClaudeOfDutyZombie-v0.1.4.2.exe", 7)]},
	]
	var v := Releases.parse_releases(JSON.stringify(mixed))
	check(v.size() == 3 and v[0].tag == "v0.1.6" and v[0].channel == Releases.SNAPSHOT and v[1].tag == tag and v[1].channel == Releases.STABLE and v[2].tag == "v0.1.4.2",
		"releases valides gardées à côté des piégées (préversion = canal snapshot) %s" % [v.map(func(e): return e.tag)])
	if v.size() == 2:
		check(v[0].exe_size == 0 and v[0].launcher_url == "" and v[0].exe_name == exe, "taille négative ramenée à 0, lanceur hors dépôt ignoré")
		check(v[0].title.length() == 300 and v[1].date == "", "titre borné (300 caractères), date absente vide")
		check(v[1].exe_url == DL + "v0.1.4.2/ClaudeOfDutyZombie-v0.1.4.2.exe", "numéro de version à 4 nombres accepté")
	var upper := [{"tag_name": tag, "assets": [_named(exe, DL.replace("ValentinDelob/Claude-Of-Duty-Zombie", "valentindelob/claude-of-duty-zombie") + tag + "/" + exe)]}]
	check(Releases.parse_releases(JSON.stringify(upper)).size() == 1, "nom du dépôt sans distinction de casse (comme GitHub)")
	check(not Releases.is_asset_url(DL + tag + "/" + exe, "v0.1.4") and Releases.is_asset_url(DL + tag + "/" + exe, tag), "fichier joint : de cette version seulement")


func _named(n: String, url: String) -> Dictionary:
	return {"name": n, "size": 1, "browser_download_url": url}


func _tags_and_versions() -> void:
	var good := ["v0.1", "v0.1.116", "v1.2.3.4", "v999999.0"]
	var bad := ["v1", "v1.2.3.4.5", "V1.2", "1.2.3", "v1.2-beta", "v1.2.", "v.1.2", "v1..2", "v1234567.1", " v1.2", "v1.2 ", "v1.2/x", "v+1.2", "v-1.2", ""]
	check(good.all(func(x): return Releases.is_safe_tag(x)) and bad.filter(func(x): return Releases.is_safe_tag(x)).is_empty(),
		"numéros de version : 2 à 4 nombres seulement %s" % [bad.filter(func(x): return Releases.is_safe_tag(x))])
	check(Releases.version_key("v0.1.116") == [0, 1, 116] and Releases.version_key("v1.2.3.4") == [1, 2, 3, 4] and Releases.version_key("vx.2") == [0, 2],
		"parties numériques d'une version")
	check(Releases.newer("v0.1.2.1", "v0.1.2") and not Releases.newer("v0.1.2", "v0.1.2.1"), "4 nombres : plus récente que la même à 3 nombres")
	check(not Releases.newer("v0.1.2.0", "v0.1.2") and not Releases.newer("v0.1.2", "v0.1.2.0") and not Releases.newer("v0.1.2", "v0.1.2"), "v0.1.2.0 = v0.1.2 (aucune plus récente)")
	check(Releases.newer("v1.0", "v0.9.9.9") and Releases.newer("v0.1.10", "v0.1.9.9") and Releases.newer("v0.10", "v0.9.99"), "ordre numérique à 2, 3 et 4 nombres")
	var tags := ["v0.1.9", "v0.1.10.1", "v0.2", "v0.1.10", "v0.1.100", "v0.1.9.9"]
	tags.sort_custom(func(a, b): return Releases.newer(a, b))
	check(tags == ["v0.2", "v0.1.100", "v0.1.10.1", "v0.1.10", "v0.1.9.9", "v0.1.9"], "tri des versions %s" % [tags])
	var names_bad := ["../x.exe", "a/b.exe", "a\\b.exe", ".x.exe", "x y.exe", "x.exe;rm", "", "é.exe", "a".repeat(101)]
	check(Releases.is_safe_asset_name("SHA256SUMS.txt") and Releases.is_safe_asset_name("a".repeat(100))
		and names_bad.filter(func(x): return Releases.is_safe_asset_name(x)).is_empty(), "noms de fichiers joints sûrs %s" % [names_bad.filter(func(x): return Releases.is_safe_asset_name(x))])


func _sums_edge_cases() -> void:
	var hx := "0123456789abcdef".repeat(4)
	var up := hx.to_upper()
	var text := "\n".join(PackedStringArray([
		"%s  Majuscules.exe" % up,
		"%s\tTabulation.exe" % hx,
		"%s  dossier/Sous.exe" % hx,
		"  %s  Espaces.exe  \r" % hx,
		"%s  Court.exe" % hx.left(63),
		"%s  Long.exe" % (hx + "0"),
		"%sg  Lettre.exe" % hx.left(63),
		"%s  Deux mots.exe" % hx,
		"%s" % hx,
		"%s  x\\Inverse.exe" % hx,
		"%s  .cache" % hx,
		"# commentaire",
		"",
	]))
	var sums := Releases.parse_sums(text)
	var keys := sums.keys()
	keys.sort()
	check(keys == ["Espaces.exe", "Inverse.exe", "Majuscules.exe", "Sous.exe", "Tabulation.exe"], "SHA256SUMS.txt : lignes invalides ignorées, chemins réduits au nom du fichier %s" % [keys])
	check(sums.get("Majuscules.exe") == hx, "SHA256SUMS.txt : chiffres hexadécimaux en majuscules ramenés en minuscules")
	var many := PackedStringArray()
	for i in 250:
		many.append("%s  f%d.exe" % [hx, i])
	var s2 := Releases.parse_sums("\n".join(many))
	check(s2.size() == 200 and s2.has("f199.exe") and not s2.has("f200.exe"), "SHA256SUMS.txt : 200 lignes lues au plus (%d)" % s2.size())
	check(Releases.parse_sums("").is_empty() and Releases.parse_sums("\n\n\n").is_empty(), "SHA256SUMS.txt vide")
	var dup := Releases.parse_sums("%s  a.exe\n%s  a.exe" % ["1".repeat(64), "2".repeat(64)])
	check(dup.size() == 1 and dup["a.exe"] == "2".repeat(64), "SHA256SUMS.txt : nom en double, dernière ligne gardée")


## Textes du lanceur : chaque texte en français et en anglais (mêmes
## emplacements %s / %d), et chaque texte utilisé par main.gd existe.
func _texts() -> void:
	var bad: Array = []
	var re := RegEx.create_from_string("%[sd%]")
	for key in Texts.T:
		var e: Dictionary = Texts.T[key]
		var fr := String(e.get("fr", ""))
		var en := String(e.get("en", ""))
		if fr.strip_edges() == "" or en.strip_edges() == "" or e.size() != 2:
			bad.append(key)
		elif re.search_all(fr).map(func(m): return m.get_string()) != re.search_all(en).map(func(m): return m.get_string()):
			bad.append(key + " (%)")
		elif Texts.t(key, "fr") != fr or Texts.t(key, "en") != en:
			bad.append(key + " (t)")
	check(bad.is_empty() and Texts.T.size() >= 20, "textes du lanceur : %d, tous en français et en anglais %s" % [Texts.T.size(), bad])
	check(Texts.t("play", "de") == Texts.t("play", "fr") and Texts.t("inconnu", "en") == "inconnu", "texte : langue inconnue -> français, clé inconnue -> clé")
	check(Texts.date("2026-09-28", "fr") == "28/09/2026" and Texts.date("2026-09-28", "en") == "2026-09-28" and Texts.date("", "fr") == ""
		and Texts.date("2026-09", "en") == "2026-09", "dates selon la langue (mal formée : telle quelle)")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var used := {}
	var key_re := RegEx.create_from_string("\"([a-z_]+)\"")
	for line in src.split("\n"):
		if line.contains("Texts.t(") or line.contains("_fail_download("):
			for m in key_re.search_all(line):
				used[m.get_string(1)] = true
	var missing := used.keys().filter(func(k): return not Texts.T.has(k))
	check(used.size() >= 15 and missing.is_empty(), "textes utilisés par main.gd : %d, tous définis %s" % [used.size(), missing])
