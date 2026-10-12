extends AutotestScenario
## @rendu : captures du RELIEF des surfaces (revue humaine, ajout en cours).
## @niveau perf : hors check (captures d'un ajout en cours) ; lancer avec
## sh tools/scenario.sh relief_look.
## Sols, murs, plafonds et planches des barricades (SurfaceRelief) : fond du
## menu, BUNKER K-7 (grille : sols en béton, carrelage, parquet ; murs peints,
## faïence ; fenêtres barricadées), TEST LEVELS (carte en maillage), porte à
## zombies d'une carte de l'éditeur (SMALLEST_DOOR). Caméra libre, sans HUD.

const SW := preload("res://tests/autotest/smallest_window.gd")
## [nom, position de la caméra, point visé] (BUNKER K-7, monde).
const BUNKER_VIEWS := [
	["labo_sol", Vector3(36.5, 1.6, 24.0), Vector3(39.5, 0.0, 24.5)],
	["labo_sol_pres", Vector3(41.0, 1.0, 23.0), Vector3(42.5, 0.0, 24.5)],
	["garde_sol_pres", Vector3(8.0, 1.0, 21.0), Vector3(9.5, 0.0, 22.5)],
	["labo_large", Vector3(35.5, 1.5, 31.0), Vector3(52.5, 1.2, 18.5)],
	["labo_plafond", Vector3(40.5, 1.6, 24.5), Vector3(43.0, 3.2, 24.5)],
	["labo_mur", Vector3(43.5, 1.5, 29.6), Vector3(44.0, 0.7, 32.0)],
	["garde_mur", Vector3(5.5, 1.6, 21.5), Vector3(2.0, 0.7, 20.0)],
	["garde_sol", Vector3(10.5, 1.6, 26.5), Vector3(12.0, 0.0, 23.0)],
	["dortoir", Vector3(9.5, 1.6, 9.5), Vector3(9.5, 0.2, 6.0)],
	["couloir", Vector3(20.5, 1.6, 24.5), Vector3(30.5, 0.6, 24.5)],
	["generateur", Vector3(55.5, 1.6, 22.5), Vector3(61.0, 0.5, 26.0)],
]

var H := AutotestHelpers
var game: Game
var p: Player
var cam: Camera3D
## Suffixe des captures (« avant » / « apres » : AUTOTEST_TAG).
var tag := "x"


func run() -> void:
	timeout_sec = 400
	tag = OS.get_environment("RELIEF_TAG") if OS.get_environment("RELIEF_TAG") != "" else "x"
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 8.0, "menu principal")
	await _menu_shot()
	# RELIEF_ONLY=menu : seulement le fond du menu ; =bunker : menu et BUNKER K-7.
	var only := OS.get_environment("RELIEF_ONLY")
	if only == "menu":
		return
	await _bunker()
	if only == "bunker":
		return
	await _mesh_map("test_levels")
	await _mesh_map("draft_arena")
	var dir := SW.install_fixture("smallest_door", "res://tests/fixtures/maps/smallest_door")
	if dir != "":
		await _mesh_map(EditorMapDef.CUSTOM_PREFIX + "smallest_door")
		SW.remove_dir(EditorMap.maps_root())


## Fond 3D du menu titre, sans l'interface.
func _menu_shot() -> void:
	var menu := tree().current_scene
	var hidden := []
	for n in menu.get_children():
		if n is MenuBackdrop or not ("visible" in n) or not n.visible:
			continue
		n.visible = false
		hidden.append(n)
	await seconds(1.5)
	await at.screenshot("menu_" + tag)
	for n in hidden:
		n.visible = true


func _start(map_id: String) -> bool:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return false
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	if game.interact.get_obj("power") != null:
		(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	cam = null
	await seconds(4.0)  # titre de la carte effacé, courant rétabli
	return true


func _shot(from: Vector3, to: Vector3, shot_name: String) -> void:
	p.teleport_to(from - Vector3(0, 1.55, 0) + (from - to).normalized() * Vector3(1, 0, 1) * 0.6)
	await seconds(0.2)
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 70.0
		cam.near = 0.05
		game.add_child(cam)
	cam.make_current()
	game.hud.visible = false
	cam.look_at_from_position(from, to)
	await seconds(0.5)
	await at.screenshot("%s_%s" % [shot_name, tag])


func _bunker() -> void:
	if not await _start("bunker_k7"):
		return
	for v in BUNKER_VIEWS:
		await _shot(v[1], v[2], "bunker_" + String(v[0]))
	# Une flaque de près (premier sommet de l'eau du relief).
	for mi: MeshInstance3D in game.world.find_children("Relief_puddle*", "MeshInstance3D", true, false):
		var c: Vector3 = mi.mesh.get_faces()[0]
		await _shot(c + Vector3(1.2, 1.1, 1.2), c, "bunker_flaque")
		break
	# Fenêtres barricadées : une de la salle de garde, une du laboratoire.
	var done := {}
	for b: Barricade in game.barricades.windows:
		if done.has(b.zone) or not b.zone in ["a", "c"]:
			continue
		done[b.zone] = true
		await _window(b, "bunker_fenetre_" + b.zone)
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


func _window(b: Barricade, shot_name: String) -> void:
	var s := b.global_transform.basis.x
	s.y = 0.0
	var at_p := b.global_position + Vector3.UP * 1.5
	await _shot(b.global_position + b.inward * 2.2 + s.normalized() * 0.5 + Vector3.UP * 1.6, at_p, shot_name + "_face")
	await _shot(b.global_position + b.inward * 1.0 + s.normalized() * 0.3 + Vector3.UP * 1.6, at_p, shot_name + "_pres")
	b.srv_set_mask(b.full_mask() & 0b010101)
	await seconds(0.8)
	await _shot(b.global_position + b.inward * 2.2 + Vector3.UP * 1.6, at_p, shot_name + "_moitie")
	b.srv_set_mask(b.full_mask())
	await seconds(0.6)


func _mesh_map(map_id: String) -> void:
	if not await _start(map_id):
		return
	var tagname := map_id.replace(":", "_")
	var o := p.global_position
	var yaws := [0.0, PI * 0.5, PI, PI * 1.5]
	for i in yaws.size():
		var d := Vector3(-sin(yaws[i]), 0, -cos(yaws[i]))
		await _shot(o + Vector3.UP * 1.6, o + d * 4.0 + Vector3.UP * 0.4, "%s_vue%d" % [tagname, i])
	for i in mini(game.barricades.windows.size(), 2):
		await _window(game.barricades.windows[i], "%s_barricade%d" % [tagname, i])
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
