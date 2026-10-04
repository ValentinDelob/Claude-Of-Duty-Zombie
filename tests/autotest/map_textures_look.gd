extends AutotestScenario
## @rendu : captures des textures de la carte (format 15, MapTextureLib) dans
## l'aperçu 3D de l'éditeur (fenêtre hors écran).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="map_textures_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Deux salles : A au sol carrelé (damier importé, motif de 1,2 m), murs en
## briques importées (motif de 2 m) ; zone B aux murs de la même brique teintée
## en vert, plafond en planches. Images fabriquées ici (Image), importées par
## MapTextureTools.import_bytes comme le ferait « Importer une texture… ».
## Captures : tests/_out/shots/map_textures_look_*.png et l'image seule de
## l'aperçu : tests/_out/map_textures_apercu.png.

const DecorFree := preload("res://tests/test_map_decor_free.gd")

var ed: MapEditor


## Carreaux de 30 cm (4 × 4 dans l'image) : blanc cassé et bleu, joints gris.
static func tiles_png() -> PackedByteArray:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			@warning_ignore("integer_division")
			var c := Color(0.82, 0.8, 0.74) if ((x / 64) + (y / 64)) % 2 == 0 else Color(0.18, 0.3, 0.55)
			if x % 64 < 3 or y % 64 < 3:
				c = Color(0.35, 0.35, 0.33)
			img.set_pixel(x, y, c)
	return img.save_png_to_buffer()


## Briques (8 rangées de 4) en JPEG.
static func bricks_jpg() -> PackedByteArray:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		@warning_ignore("integer_division")
		var row := y / 16
		for x in w:
			var c := Color(0.55, 0.22, 0.14).lerp(Color(0.42, 0.16, 0.1), fposmod(sin(x * 0.37 + row * 3.1) * 0.5 + 0.5, 1.0))
			if y % 16 < 2 or (x + (row % 2) * 32) % 64 < 3:
				c = Color(0.7, 0.68, 0.62)
			img.set_pixel(x, y, c)
	return img.save_jpg_to_buffer(0.92)


## Planches (bandes horizontales) en PNG.
static func planks_png() -> PackedByteArray:
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			@warning_ignore("integer_division")
			var band := y / 16
			var c := Color(0.45, 0.3, 0.17) * (0.8 + 0.2 * fposmod(band * 0.37, 1.0))
			if y % 16 < 1:
				c = Color(0.12, 0.08, 0.05)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img.save_png_to_buffer()


static func textured_map() -> EditorMap:
	var doc := DecorFree.two_rooms()
	MapTextureTools.import_bytes(doc, tiles_png(), {"id": "carreaux", "nom": "Carreaux", "taille": 1.2, "rugosite": 0.4})
	MapTextureTools.import_bytes(doc, bricks_jpg(), {"id": "briques", "nom": "Briques", "taille": 2.0})
	MapTextureTools.import_bytes(doc, planks_png(), {"id": "planches", "nom": "Planches", "taille": 1.5})
	doc.pieces[0]["surface_sol"] = "map:carreaux"
	doc.pieces[0]["surface_murs"] = "map:briques"
	doc.pieces[0]["surface_plafond"] = "map:planches"
	doc.pieces[1].erase("surface_murs")
	doc.zones[1]["murs"] = "map:briques"
	return doc


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	ed._reset(textured_map())
	await frames(3)
	var pv := ed.preview
	var w := pv.world
	pv.pause_unfocused = false
	pv.set_render_scale(1.0)
	pv.set_shown(true)
	if not await until(func(): return w.builds > 0 and w.idle() and not w.is_stale(), 30.0, "aperçu construit"):
		return
	var mats := {}
	for n in w.groups.arch.find_children("tex-*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m != null and m.shader == MapTextureLib.SHADER:
			mats[String(n.name).get_slice("__", 0)] = true
	at.check(mats.has("tex-carreaux") and mats.has("tex-briques") and mats.has("tex-planches"), "aperçu : les trois textures importées (%s)" % str(mats.keys()))
	# Vue dans la salle A, à hauteur d'homme, vers le nord-est (sol, murs, porte vers B).
	var off := MapGeom.WORLD_OFFSET
	w.rig.mode = MapPreviewCamera.Mode.FLY
	w.rig.fly_pos = Vector3(1.5 + off, 1.7, 9.0 + off)
	w.rig.yaw = -0.75
	w.rig.pitch = -0.18
	w.rig._apply()
	await seconds(1.0)
	await at.screenshot("apercu_salle")
	var img := w.viewport.get_texture().get_image()
	if img != null and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://tests/_out/map_textures_apercu.png"))
		print("[map_textures_look] aperçu : tests/_out/map_textures_apercu.png")
	# Vue en coupe (plafonds masqués) : les deux salles.
	pv.set_option("ceil", true)
	w.frame_map()
	w.rig.yaw = 0.5
	w.rig.pitch = -0.8
	w.rig._apply()
	await seconds(0.8)
	await at.screenshot("apercu_coupe")
	var img2 := w.viewport.get_texture().get_image()
	if img2 != null and not img2.is_empty():
		img2.save_png(ProjectSettings.globalize_path("res://tests/_out/map_textures_apercu_coupe.png"))
	pv.set_option("ceil", false)
	# Panneau Propriétés de la salle A : liste de la texture du sol ouverte
	# (surfaces du jeu, « Textures de la carte », Importer, Gérer), puis ⚙.
	ed.select(String(ed.doc.pieces[0].id))
	ed.panels.show_tab("props")
	ed.panels.refresh_now()
	await frames(3)
	var opts := ed.panels._props.find_children("*", "OptionButton", true, false).filter(func(o):
		for i in o.item_count:
			if str(o.get_item_metadata(i)) == "#importer":
				return true
		return false)
	at.check(opts.size() == 3, "trois choix de texture (sol, murs, plafond)")
	if opts.size() == 3:
		(opts[0] as OptionButton).show_popup()
		var pop := (opts[0] as OptionButton).get_popup()
		await frames(2)
		pop.scroll_to_item(pop.item_count - 1)
		await seconds(0.4)
		await at.screenshot("panneau_choix")
		pop.hide()
	ed.texture_tools.edit_dialog("carreaux")
	await seconds(0.4)
	await at.screenshot("reglages")
