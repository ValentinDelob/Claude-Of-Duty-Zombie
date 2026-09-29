extends SceneTree
## Tests du lanceur (sans réseau) :
##   godot --headless --path launcher -s res://tests/test_launcher.gd
## Lecture des releases GitHub, ordre des versions, notes de version (et repli),
## versions installées et téléchargement terminé ; sécurité : domaines et
## adresses autorisés, numéros de version et noms de fichiers sûrs, sommes
## SHA-256 et politique des anciennes versions, BBCode échappé, images bornées,
## réglages piégés ignorés.

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")

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

	# Versions installées : dossier temporaire.
	Store.root = ProjectSettings.globalize_path("user://test_versions")
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

	# Réglages du lanceur : jamais d'objet ni de ressource décodés.
	check(Store.has_constructor("[launcher]\nselected=Object(Node,\"script\":Resource(\"user://x.gd\"))\n"), "réglages piégés détectés")
	check(Store.has_constructor("[launcher]\nlanguage=\"fr\" ; c\nselected=Resource (\"user://x.gd\")\n"), "constructeur après un commentaire détecté")
	check(not Store.has_constructor("[launcher]\nlanguage=\"fr\"\nselected=\"Object(latest)\" ; Object(\n"), "texte ordinaire (même avec « Object( » entre guillemets) accepté")
	print("LAUNCHER: %d échec(s)" % failures)
	quit(1 if failures > 0 else 0)
