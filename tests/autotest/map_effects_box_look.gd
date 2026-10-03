extends AutotestScenario
## @rendu : captures des effets DANS LEUR BOÎTE (revue humaine) : chaque effet
## du catalogue construit par le jeu (MapEffects), sa boîte orange (son
## VOLUME, MapCatalog.effect_volume : celle que dessinent l'aperçu 3D et les
## élévations de l'éditeur, tests/test_map_effect_volume.gd) ; tout ce qu'il
## affiche doit y rester.
## @niveau perf : hors check par défaut (captures d'une correction en cours) ;
## lancer avec sh tools/scenario.sh map_effects_box_look.
## Captures : tests/_out/shots/map_effects_box_look_<effet>[_min].png, et deux
## planches : map_effects_box_look_planche_defaut.png (zone par défaut),
## map_effects_box_look_planche_min.png (zone minimale).

const ROOM_H := 3.2
const COL := Color(1.0, 0.85, 0.3)
## Planche : vignettes de 480 × 270, 6 colonnes.
const THUMB := Vector2i(480, 270)
const COLS := 6

var root: Node3D
var cam: Camera3D
var box: MeshInstance3D


func run() -> void:
	timeout_sec = 600
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	root = Node3D.new()
	root.name = "EffectsBoxLook"
	tree().change_scene_to_node(root)
	await frames(3)
	_stage()
	for pass_name in ["defaut", "min"]:
		var sheet := Image.create(THUMB.x * COLS, THUMB.y * ceili(MapCatalog.EFFECTS.size() / float(COLS)), false, Image.FORMAT_RGB8)
		var i := 0
		for fid in MapCatalog.EFFECTS:
			if _only() != "" and not _only().split(",").has(fid):
				continue
			var img := await _shoot(fid, pass_name == "min")
			if img != null:
				img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, THUMB), Vector2i((i % COLS) * THUMB.x, (i / COLS) * THUMB.y))
			i += 1
		var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
		DirAccess.make_dir_recursive_absolute(dir)
		sheet.save_png("%s/map_effects_box_look_planche_%s.png" % [dir, pass_name])
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


## Décor neutre : sol, mur du fond (z = 0, les effets muraux y sont collés),
## lumière faible, ciel sombre, caméra, boîte.
func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.055, 0.065)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.52, 0.56)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.6, 0.0)
	sun.light_energy = 1.0
	root.add_child(sun)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	mat.roughness = 1.0
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	fl.material_override = mat
	root.add_child(fl)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, ROOM_H, 0.2)
	wall.mesh = bm
	wall.material_override = mat
	wall.position = Vector3(0, ROOM_H * 0.5, -0.1)
	root.add_child(wall)
	cam = Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()
	box = MeshInstance3D.new()
	box.mesh = ImmediateMesh.new()
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.vertex_color_use_as_albedo = true
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.no_depth_test = true
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material_override = bmat
	root.add_child(box)


## Effet `fid` (zone par défaut ou minimale) posé comme en jeu, sa boîte,
## mesure des particules vivantes, capture. Rend l'image.
func _shoot(fid: String, small: bool) -> Image:
	var d: Dictionary = MapCatalog.EFFECTS[fid]
	var mount := String(d.mount)
	var ground := float(d.get("y", 0.0))
	if mount == "plafond":
		ground = ROOM_H - 0.02
	var opts := {"room_h": ROOM_H, "ground": ground, "intensity": 1.0}
	if small:
		var z := MapCatalog.effect_default_zone(fid)
		for key in MapCatalog.effect_dims(fid):
			var b := MapCatalog.effect_zone_bounds(fid, key)
			match String(key):
				"l":
					z.x = b[0]
				"p":
					z.y = b[0]
				"h":
					z.z = b[0]
		opts["zone"] = [z.x, z.y, z.z]
	var e := MapEffects.build(fid, opts)
	# Origine : posée à `ground` au-dessus du sol ; murale : sur le mur (z = 0).
	e.position = Vector3(0, ground, 0)
	root.add_child(e)
	var vol := e.volume
	_draw_box(AABB(vol.position + e.position, vol.size) if not OS.get_cmdline_user_args().has("--sans-boite") else AABB())
	# Caméra de trois quarts, à distance selon la taille du volume.
	var c := vol.get_center() + e.position
	var r := maxf(vol.size.length() * 0.5, 0.6)
	var from := c + Vector3(0.55, 0.3, 1.0).normalized() * r * 2.2
	cam.look_at_from_position(from, c)
	# Effet bien pris (préchauffage, quelques salves) avant la capture. La boîte
	# des particules vivantes lue sur la carte graphique (capture_aabb) compte
	# aussi les particules inactives : inutilisable ; le contenu est vérifié
	# par le calcul (tests/test_map_effect_volume.gd) et par ces captures.
	for n in 30:
		if n % 10 == 2 and e.burst_every != Vector2.ZERO:
			e._burst()
		await seconds(0.1)
	if e.burst_every != Vector2.ZERO:
		e._burst()
		await seconds(0.55)
	var tag := fid + ("_min" if small else "")
	await at.screenshot(tag)
	var img := tree().root.get_viewport().get_texture().get_image()
	e.queue_free()
	await frames(2)
	return img


## Boîte orange (traits et faces transparentes), comme le surlignage de
## l'aperçu 3D de l'éditeur.
func _draw_box(b: AABB) -> void:
	var im := box.mesh as ImmediateMesh
	im.clear_surfaces()
	var p := [b.position, b.position + Vector3(b.size.x, 0, 0), b.position + Vector3(b.size.x, 0, b.size.z), b.position + Vector3(0, 0, b.size.z)]
	var h := Vector3(0, b.size.y, 0)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(COL)
	for i in 4:
		var a: Vector3 = p[i]
		var c: Vector3 = p[(i + 1) % 4]
		for y in [Vector3.ZERO, h]:
			im.surface_add_vertex(a + y)
			im.surface_add_vertex(c + y)
		im.surface_add_vertex(a)
		im.surface_add_vertex(a + h)
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color(COL, 0.0))
	for i in 4:
		var a: Vector3 = p[i]
		var c: Vector3 = p[(i + 1) % 4]
		for v in [a, c, c + h, a, c + h, a + h]:
			im.surface_add_vertex(v)
	im.surface_end()


## « --effets=a,b » : seulement ces effets (mise au point) ; « --sans-boite ».
func _only() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--effets="):
			return a.substr(9)
	return ""
