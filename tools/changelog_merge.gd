extends SceneTree
## Notes de version pour les joueurs (affichées par le lanceur, docs/LAUNCHER.md) :
## au moment du commit, les notes de la prochaine version, écrites dans
## changelogs/next/next.json (+ captures .jpg/.png du même dossier), rejoignent
## changelogs/changelogs.json sous le numéro de la version qui va être publiée.
##   godot --headless --path . -s res://tools/changelog_merge.gd -- v0.1.120
## Écrit aussi build/player_notes.md (notes de la page de release GitHub).
## Sans changelogs/next/next.json : ne fait rien.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage : -- <version>")
		quit(2)
		return
	var tag: String = args[0]
	var root := ProjectSettings.globalize_path("res://changelogs")
	var next_dir := root + "/next"
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
	var cl = JSON.parse_string(FileAccess.get_file_as_string(root + "/changelogs.json"))
	if not cl is Dictionary:
		cl = {"versions": {}}
	var images: Array = []
	var files := DirAccess.get_files_at(next_dir)
	files.sort()
	for f in files:
		if f.get_extension().to_lower() in ["jpg", "jpeg", "png"]:
			DirAccess.make_dir_recursive_absolute(root + "/img/" + tag)
			DirAccess.rename_absolute(next_dir + "/" + f, root + "/img/" + tag + "/" + f)
			images.append(tag + "/" + f)
	cl.versions[tag] = {"date": Time.get_date_string_from_system(), "title": e.title, "items": e.items, "images": images}
	var out := FileAccess.open(root + "/changelogs.json", FileAccess.WRITE)
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
