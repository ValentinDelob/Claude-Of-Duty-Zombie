extends SceneTree
## Carte dessinée -> description de carte en maillage (docs/MAP_AUTHORING.md).
##
##   godot --headless --path . -s res://tools/maps/draw2layout.gd -- <carte.txt>
##     lit le dessin (carte.txt + une image par étage), écrit le rapport du
##     validateur à côté du dessin (rapport.txt, rapport_etageN.png : dessin
##     agrandi, problèmes entourés) et, s'il n'y a AUCUNE erreur,
##     assets/maps/<id>/layout.json. Code de sortie 1 si la carte est refusée.
##   godot --headless --path . -s res://tools/maps/draw2layout.gd -- --vierge <image.png> <largeur> <hauteur>
##     image blanche (modèle de dessin).
## D'ordinaire : sh tools/maps/build_map.sh <carte.txt> (conversion, Blender, import).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage : -- <carte.txt>  |  -- --vierge <image.png> <largeur> <hauteur>")
		quit(2)
		return
	if args[0] == "--vierge" and args.size() >= 4:
		var img := Image.create(args[2].to_int(), args[3].to_int(), false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		img.save_png(args[1])
		print("[carte] image vierge %s × %s -> %s" % [args[2], args[3], args[1]])
		quit(0)
		return
	var t0 := Time.get_ticks_msec()
	var md := MapDrawing.load_file(args[0])
	var report := md.report_text()
	print(report)
	if md.base_dir != "" and DirAccess.dir_exists_absolute(md.base_dir):
		var f := FileAccess.open(md.base_dir.path_join("rapport.txt"), FileAccess.WRITE)
		f.store_string(report)
		f.close()
		var imgs := md.report_images()
		for i in imgs.size():
			if imgs[i] != null:
				imgs[i].save_png(md.base_dir.path_join("rapport_etage%d.png" % i))
	if not md.ok():
		print("[carte] REFUSÉE : corrigez les erreurs (positions en cases du dessin, voir rapport_etage*.png)")
		quit(1)
		return
	var layout := MapDrawingExport.build(md)
	var out_dir := ProjectSettings.globalize_path("res://assets/maps/%s" % md.id)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var out := FileAccess.open(out_dir.path_join("layout.json"), FileAccess.WRITE)
	out.store_string(dump(layout))
	out.close()
	print("[carte] %s : %d salles, %d blocs, %d portes, %d fenêtres -> %s (%d ms)" % [md.id, layout.rooms.size(), layout.blocks.size(),
		layout.markers.doors.size(), layout.markers.windows.size(), out_dir.path_join("layout.json"), Time.get_ticks_msec() - t0])
	quit(0)


## JSON lisible dans un diff git : une entrée (salle, bloc, marqueur…) par ligne.
static func dump(v: Variant, depth := 0) -> String:
	var pad := " ".repeat(depth + 1)
	if v is Dictionary and depth < 2:
		var parts := PackedStringArray()
		for k in v:
			parts.append("%s%s: %s" % [pad, JSON.stringify(String(k)), dump(v[k], depth + 1)])
		return "{\n%s\n%s}" % [",\n".join(parts), " ".repeat(depth)] if not parts.is_empty() else "{}"
	if v is Array and depth < 2 and not v.is_empty() and (v[0] is Dictionary or v[0] is Array):
		var parts := PackedStringArray()
		for e in v:
			parts.append(pad + JSON.stringify(e, "", false))
		return "[\n%s\n%s]" % [",\n".join(parts), " ".repeat(depth)]
	return JSON.stringify(v, "", false)
