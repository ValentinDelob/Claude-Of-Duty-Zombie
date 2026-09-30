extends SceneTree
## Notes de version pour les joueurs (affichées par le lanceur, docs/LAUNCHER.md) :
## au moment du commit, les notes de la prochaine version, écrites dans
## changelogs/next/next.json (+ captures .jpg/.png du même dossier), rejoignent
## changelogs/changelogs.json sous le numéro de la version qui va être publiée.
##   godot --headless --path . -s res://tools/changelog_merge.gd -- v0.1.120
## Écrit aussi build/player_notes.md (notes de la page de release GitHub).
## Sans changelogs/next/next.json : ne fait rien.

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--promote="):
			var stable := ""
			for b in OS.get_cmdline_user_args():
				if b.begins_with("--stable="):
					stable = b.substr(9)
			quit(_promote(a.substr(10), stable))
			return
	_merge()


func _merge() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage : -- <version>")
		quit(2)
		return
	var tag: String = args[0]
	var root_dir := ProjectSettings.globalize_path("res://changelogs")
	var next_dir := root_dir + "/next"
	var next := next_dir + "/next.json"
	if not FileAccess.file_exists(next):
		print("[changelog] pas de notes pour %s (changelogs/next/next.json absent)" % tag)
		quit(0)
		return
	var e = JSON.parse_string(FileAccess.get_file_as_string(next))
	if not e is Dictionary or not _both(e.get("title", {})) or (e.get("items", []) as Array).is_empty() \
			or not (e.items as Array).all(func(it): return _both(it)):
		printerr("[changelog] next.json invalide : title {fr, en} et items [{fr, en}, ...] obligatoires")
		quit(1)
		return
	var cl = JSON.parse_string(FileAccess.get_file_as_string(root_dir + "/changelogs.json"))
	if not cl is Dictionary:
		cl = {"versions": {}}
	var images: Array = []
	var files := DirAccess.get_files_at(next_dir)
	files.sort()
	for f in files:
		if f.get_extension().to_lower() in ["jpg", "jpeg", "png"]:
			DirAccess.make_dir_recursive_absolute(root_dir + "/img/" + tag)
			DirAccess.rename_absolute(next_dir + "/" + f, root_dir + "/img/" + tag + "/" + f)
			images.append(tag + "/" + f)
	cl.versions[tag] = {"date": Time.get_date_string_from_system(), "title": e.title, "items": e.items, "images": images,
		"channel": "snapshot" if "-snapshot." in tag else "stable"}
	var out := FileAccess.open(root_dir + "/changelogs.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(cl, " ") + "\n")
	out.close()
	DirAccess.remove_absolute(next)
	for f in DirAccess.get_files_at(next_dir):
		DirAccess.remove_absolute(next_dir + "/" + f)
	DirAccess.remove_absolute(next_dir)
	# Notes de la page de release : français puis anglais.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var md := FileAccess.open("res://build/player_notes.md", FileAccess.WRITE)
	md.store_line("<!-- %s -->" % tag)
	for lang in ["fr", "en"]:
		md.store_line("## " + String(e.title[lang]))
		for it in e.items:
			md.store_line("- " + String(it[lang]))
		md.store_line("")
	md.close()
	print("[changelog] notes de %s ajoutées (%d puces, %d captures)" % [tag, e.items.size(), images.size()])
	quit(0)


func _both(v) -> bool:
	return v is Dictionary and String(v.get("fr", "")) != "" and String(v.get("en", "")) != ""


## Promotion (tools/promote.sh) : les notes des snapshots publiées depuis la
## stable précédente, jusqu'à `snap` compris, rassemblées sous `stable`
## (canal stable) ; build/player_notes.md pour la page de la release.
func _promote(snap: String, stable: String) -> int:
	var path := ProjectSettings.globalize_path("res://changelogs/changelogs.json")
	var cl: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not cl is Dictionary or not cl.get("versions") is Dictionary or stable == "":
		printerr("[changelog] changelogs.json illisible ou numéro stable manquant")
		return 1
	var versions: Dictionary = cl.versions
	# Stable précédente : la plus récente sans « -snapshot. » avant `stable`.
	var prev := ""
	for tag: String in versions:
		if not "-snapshot." in tag and _newer(stable, tag) and (prev == "" or _newer(tag, prev)):
			prev = tag
	var picked: Array = []
	for tag: String in versions:
		if "-snapshot." in tag and not _newer(tag, snap) and (prev == "" or _newer(tag, prev)):
			picked.append(tag)
	picked.sort_custom(func(a, b): return _newer(b, a))
	var items: Array = []
	var images: Array = []
	for tag in picked:
		items.append_array(versions[tag].get("items", []))
		images.append_array(versions[tag].get("images", []))
	var n := items.size()
	versions[stable] = {"date": Time.get_date_string_from_system(), "channel": "stable", "from": snap,
		"title": {"fr": "Version stable %s" % stable, "en": "Stable version %s" % stable},
		"items": items if n > 0 else [{"fr": "Même contenu que %s, déjà testé en snapshot." % snap, "en": "Same content as %s, already tested as a snapshot." % snap}],
		"images": images.slice(0, 12)}
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(cl, " ") + "\n")
	out.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var md := FileAccess.open("res://build/player_notes.md", FileAccess.WRITE)
	md.store_line("<!-- %s -->" % stable)
	for lang in ["fr", "en"]:
		md.store_line("## " + String(versions[stable].title[lang]))
		for it in versions[stable].items:
			md.store_line("- " + String(it.get(lang, "")))
		md.store_line("")
	md.close()
	print("[changelog] notes de %s : %d snapshot(s) rassemblée(s) (%d puces)" % [stable, picked.size(), n])
	return 0


## Ordre des versions (comme le lanceur) : nombres, puis stable après ses snapshots.
static func _newer(a: String, b: String) -> bool:
	var ka := a.trim_prefix("v").get_slice("-", 0).split(".")
	var kb := b.trim_prefix("v").get_slice("-", 0).split(".")
	for i in maxi(ka.size(), kb.size()):
		var x := int(ka[i]) if i < ka.size() else 0
		var y := int(kb[i]) if i < kb.size() else 0
		if x != y:
			return x > y
	var sa := int(a.get_slice("-snapshot.", 1)) if "-snapshot." in a else -1
	var sb := int(b.get_slice("-snapshot.", 1)) if "-snapshot." in b else -1
	if sa == sb:
		return false
	if sa < 0:
		return true
	if sb < 0:
		return false
	return sa > sb
