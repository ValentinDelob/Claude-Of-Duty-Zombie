extends SceneTree
## Tests du lanceur (sans réseau) :
##   godot --headless --path launcher -s res://tests/test_launcher.gd
## Lecture des releases GitHub, ordre des versions, notes de version (et repli),
## versions installées et téléchargement terminé.

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "ÉCHEC ") + what)
	if not ok:
		failures += 1


func _init() -> void:
	var api := JSON.stringify([
		{"tag_name": "v0.1.99", "name": "v0.1.99 — Merge branch 'x'", "published_at": "2026-09-28T10:00:00Z",
			"assets": [{"name": "CallOfClaudeZombie-v0.1.99.exe", "size": 1000, "browser_download_url": "https://x/99.exe"}]},
		{"tag_name": "v0.1.116", "name": "v0.1.116 — feat: release KINO V2", "published_at": "2026-09-28T20:00:00Z",
			"assets": [{"name": "ClaudeOfDutyZombie-v0.1.116.exe", "size": 2000, "browser_download_url": "https://x/116.exe"},
				{"name": "CallOfClaudeZombie-Launcher.exe", "size": 50, "browser_download_url": "https://x/old.exe"},
				{"name": "ClaudeOfDutyZombie-Launcher.exe", "size": 50, "browser_download_url": "https://x/l.exe"},
				{"name": "launcher_version.txt", "size": 1, "browser_download_url": "https://x/lv.txt"}]},
		{"tag_name": "v0.1.9", "name": "v0.1.9", "published_at": "2026-09-01T00:00:00Z", "assets": []},
		{"tag_name": "v0.1.100", "name": "brouillon", "draft": true, "assets": []},
	])
	var v := Releases.parse_releases(api)
	check(v.size() == 2, "releases jouables seulement (sans exe ni brouillon : ignorées)")
	check(v[0].tag == "v0.1.116" and v[1].tag == "v0.1.99", "plus récente d'abord (ordre numérique, pas alphabétique)")
	check(v[0].launcher_url == "https://x/l.exe" and v[0].launcher_version_url != "", "lanceur (nouveau nom prioritaire) et sa version repérés")
	check(v[1].exe_url == "https://x/99.exe", "anciennes versions (ancien nom du jeu) toujours reconnues")
	check(v[0].date == "2026-09-28" and v[0].exe_size == 2000, "date et taille")
	check(v[0].title == "release KINO V2", "titre sans numéro ni préfixe technique")
	check(Releases.newer("v0.1.116", "v0.1.99") and not Releases.newer("v0.1.99", "v0.1.116"), "comparaison de versions")
	check(Releases.newer("v0.2.0", "v0.1.300"), "version mineure prioritaire")

	var cl := {"versions": {"v0.1.116": {"title": {"fr": "KINO renaît", "en": "KINO reborn"},
		"items": [{"fr": "Une salle", "en": "A room"}], "images": ["v0.1.116/01.jpg"]}}}
	var n := Releases.notes(cl, "v0.1.116", "en")
	check(n.title == "KINO reborn" and n.items == ["A room"] and n.images.size() == 1, "notes en anglais")
	check(Releases.notes(cl, "v0.1.116", "fr").title == "KINO renaît", "notes en français")
	var none := Releases.notes(cl, "v0.1.99", "fr", "Titre GitHub")
	check(none.title == "Titre GitHub" and none.items.is_empty() and not none.found, "sans notes : titre de la release")

	# Notes publiées dans le dépôt : chaque version a un titre et des puces dans les deux langues.
	var f := FileAccess.open("res://../changelogs/changelogs.json", FileAccess.READ)
	if f:
		var real: Dictionary = JSON.parse_string(f.get_as_text())
		var bad: Array = []
		for tag in real.versions:
			var e: Dictionary = real.versions[tag]
			if String(e.title.get("fr", "")) == "" or String(e.title.get("en", "")) == "" or e.items.is_empty():
				bad.append(tag)
			for img in e.get("images", []):
				if not FileAccess.file_exists("res://../changelogs/img/" + String(img)):
					bad.append(img)
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
	check(Store.finish_download("v0.1.2") and Store.is_installed("v0.1.2"), "téléchargement terminé : installée")
	check(Store.installed() == ["v0.1.2"], "liste des versions installées")
	Store.remove("v0.1.2")
	check(not Store.is_installed("v0.1.2"), "version supprimée")
	print("LAUNCHER: %d échec(s)" % failures)
	quit(1 if failures > 0 else 0)
