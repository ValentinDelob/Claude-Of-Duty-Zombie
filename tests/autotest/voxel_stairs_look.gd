extends AutotestScenario
## @rendu : ESCALIERS, RAMPES ET GARDE-CORPS EN CUBES (lot D,
## docs/VOXEL_ARCHITECTURE_PLAN.md § 2.3) en jeu : chaque type d'escalier de
## la carte d'essai (tests/test_stairs.gd), avec garde-corps, côtés fermés,
## virage à gauche et sortie sur le côté ; escalier tourné de 30°
## (tests/test_map_editor_freeform.gd) ; test_levels (architecture du .glb,
## lot E) et sa description construite par le jeu (MeshMapGeometry : mêmes
## règles que lot D, pour comparer). Le joueur monte l'escalier droit.
## @niveau perf : hors check (captures d'un ajout en cours).
## Captures : tests/_out/shots/voxel_stairs_look_*.png.

const Stairs := preload("res://tests/test_stairs.gd")
const TopWall := preload("res://tests/test_stairs_top_wall.gd")
const Free := preload("res://tests/test_map_editor_freeform.gd")

var H := AutotestHelpers
var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 420
	await stairs_map()
	await rotated_map()
	await levels_map()


## Vue : joueur en (x, z) de l'éditeur (au sol `y`), regard vers `tg`.
func view(p: Player, name: String, at2: Vector2, tg: Vector3, y := 0.0) -> void:
	p.global_position = Vector3(off + at2.x, y + 0.05, off + at2.y)
	H.aim_at(p, tg + Vector3(off, 0, off))
	await seconds(0.6)
	await at.screenshot(name)


func start(doc: EditorMap, id: String) -> Player:
	doc.carte["id"] = id
	var v := MapRaster.build(doc).v
	v.analyze()
	for m in v.errors() + v.warnings():
		print("[voxel_stairs_look] %s : %s" % [m.level, m.fr])
	at.check(v.errors().is_empty(), "%s : carte valide" % id)
	var dir := EditorMap.map_dir(id)
	if doc.save_dir(dir) != OK:
		at.fail("carte d'essai non enregistrée dans " + dir)
		return null
	var p := await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + id)
	if p == null:
		return null
	Game.instance.rounds.paused = true
	Game.instance.combat.debug_invulnerable = true
	p.bot_controlled = true
	await H.clear_zombies(self)
	await seconds(2.0)
	return p


func stairs_map() -> void:
	var doc := Stairs.stairs_map()
	TopWall.side_bay(doc).merge({"garde_corps": true})
	for o in doc.objets:
		if o.get("type") != "escalier":
			continue
		match MapCatalog.stair_kind(o):
			"palier", "demi_tour", "colimacon", "rampe", "quart":
				o["garde_corps"] = true
			"service":
				o["cotes"] = "fermes"
	var p := await start(doc, "escaliers_cubes")
	if p == null:
		return
	var tris := 0
	for mi: MeshInstance3D in Game.instance.world.find_children("*__stair", "MeshInstance3D", true, false) \
			+ Game.instance.world.find_children("*__rail", "MeshInstance3D", true, false):
		tris += mi.mesh.get_faces().size() / 3
	print("[voxel_stairs_look] carte des escaliers : %d triangles d'escaliers et de garde-corps" % tris)
	# Le joueur monte l'escalier droit à pied jusqu'à la mezzanine (3,5 m).
	p.global_position = Vector3(off + 4.25, 0.05, off + 18.0)
	H.aim_at(p, Vector3(off + 4.25, 3.0, off + 5.0))
	p.input.move = Vector2(0, 1)
	var up: bool = await until(func(): return p.global_position.y > 3.4, 8.0, "le joueur monte l'escalier droit")
	p.input.move = Vector2.ZERO
	at.check(up, "joueur sur la mezzanine (y = %.2f)" % p.global_position.y)
	var lay := Stairs.layout_of()
	for i in Stairs.KINDS.size():
		var kind: String = Stairs.KINDS[i]
		var r: Array = lay[kind][0]
		var cx := (float(r[0]) + float(r[2])) * 0.5
		var cz := (float(r[1]) + float(r[3])) * 0.5
		# Trois quarts face, depuis le sud-est, et profil depuis l'est.
		await view(p, kind, Vector2(float(r[2]) + 2.5, float(r[3]) + 3.0), Vector3(cx, 1.4, cz))
		await view(p, kind + "_profil", Vector2(float(r[2]) + 3.0, cz), Vector3(cx, 1.6, cz))
	await view(p, "colimacon_dessus", Vector2(2.0 + Stairs.BAY * 6 + 4.0, 9.0), Vector3(2.0 + Stairs.BAY * 6 + 3.25, 0.5, 13.75), 3.5)
	await view(p, "palier_garde_corps", Vector2(2.0 + Stairs.BAY + 6.0, 5.0), Vector3(2.0 + Stairs.BAY + 2.25, 3.5, 9.0), 3.5)
	var x := 2.0 + Stairs.BAY * Stairs.KINDS.size() + 1.0
	await view(p, "sortie_cote", Vector2(x + 6.0, 10.0), Vector3(x + 2.25, 2.0, 2.0))
	await view(p, "mezzanine_garde_corps", Vector2(6.5, 6.0), Vector3(2.0, 3.6, 9.0), 3.5)
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


func rotated_map() -> void:
	var doc := Free.stairs_map()
	doc.find("e1")["garde_corps"] = true
	var p := await start(doc, "escalier_tourne_cubes")
	if p == null:
		return
	await view(p, "tourne_30", Vector2(13.0, 13.5), Vector3(8.0, 1.2, 8.0))
	await view(p, "tourne_30_pres", Vector2(10.5, 10.5), Vector3(8.0, 0.8, 8.5))
	await view(p, "tourne_30_dessus", Vector2(12.0, 3.0), Vector3(8.5, 2.5, 8.0), 3.5)
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


func levels_map() -> void:
	var p := await H.start_solo_game(self, "test_levels")
	if p == null:
		return
	Game.instance.rounds.paused = true
	Game.instance.combat.debug_invulnerable = true
	p.bot_controlled = true
	await H.clear_zombies(self)
	await seconds(2.0)
	# Lampe de prise de vue (la copie construite par le jeu n'a pas les
	# lampes de la carte) : la même pour les deux, au-dessus du joueur.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 14.0
	lamp.light_energy = 2.5
	Game.instance.world.add_child(lamp)
	# Carte du .glb (lot E) : escalier, garde-corps de la mezzanine, pente.
	var shot := func(name: String, pos: Vector3, tg: Vector3) -> void:
		lamp.global_position = pos + Vector3(0, 2.5, 0)
		p.global_position = pos
		H.aim_at(p, tg)
		await seconds(0.6)
		await at.screenshot(name)
	await shot.call("test_levels_glb", Vector3(15.0, 0.05, 21.0), Vector3(11.2, 1.5, 15.0))
	await shot.call("test_levels_glb_rail", Vector3(18.0, 3.05, 10.5), Vector3(13.0, 3.6, 14.0))
	await shot.call("test_levels_glb_pente", Vector3(16.0, 0.05, 23.0), Vector3(16.0, -1.4, 30.0))
	# La même description construite par le jeu (règles du lot D), à côté.
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/test_levels/layout.json"))
	var holder := Node3D.new()
	holder.position = Vector3(0, 0, 60)
	Game.instance.world.add_child(holder)
	var pb := MapPreviewBuilder.new(L)
	pb.build_architecture(holder)
	await seconds(0.3)
	await shot.call("test_levels_cubes", Vector3(15.0, 0.05, 81.0), Vector3(11.2, 1.5, 75.0))
	await shot.call("test_levels_cubes_rail", Vector3(18.0, 3.05, 70.5), Vector3(13.0, 3.6, 74.0))
	await shot.call("test_levels_cubes_pente", Vector3(16.0, 0.05, 83.0), Vector3(16.0, -1.4, 90.0))
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
