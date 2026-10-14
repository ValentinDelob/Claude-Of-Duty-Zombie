extends AutotestScenario
## @rendu : captures du DEHORS des fenêtres barricadées (WindowOutside ;
## revue humaine, ajout en cours, comparées à docs/art/gemini_target.webp).
## @niveau perf : hors check ; lancer avec sh tools/scenario.sh window_look.
## BUNKER K-7 (salle de garde, laboratoire, générateur : murs de 1 m), porte
## à zombies simple et double (cartes de l'éditeur). Vues de face, de près,
## planches à moitié arrachées, fenêtre ouverte ; plusieurs instants (les
## silhouettes passent). WINDOW_TAG : suffixe des captures (avant / après).
## WINDOW_ONLY=bunker : BUNKER K-7 seulement.

const SW := preload("res://tests/autotest/smallest_window.gd")

var H := AutotestHelpers
var game: Game
var p: Player
var cam: Camera3D
var tag := "x"


func run() -> void:
	timeout_sec = 400
	tag = OS.get_environment("WINDOW_TAG") if OS.get_environment("WINDOW_TAG") != "" else "x"
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 8.0, "menu principal")
	await _bunker()
	if OS.get_environment("WINDOW_ONLY") == "bunker":
		return
	for id in ["smallest_door", "smallest_double_door"]:
		var dir := SW.install_fixture(id, "res://tests/fixtures/maps/" + id)
		if dir != "":
			await _mesh_map(EditorMapDef.CUSTOM_PREFIX + id)
		SW.remove_dir(EditorMap.maps_root())


func _start(map_id: String) -> bool:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return false
	game = Game.instance
	game.rounds.paused = true
	# Manche « en cours » pour l'activité des silhouettes (sans apparition).
	game.rounds.phase = RoundManager.Phase.ACTIVE
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	if game.interact.get_obj("power") != null:
		(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	cam = null
	await seconds(4.0)
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


## Dehors de la fenêtre (WindowOutside), ou null (capture « avant »).
func _out(b: Barricade) -> Node3D:
	return b.get("outside") as Node3D


func _bunker() -> void:
	if not await _start("bunker_k7"):
		return
	var outs := 0
	for b: Barricade in game.barricades.windows:
		var o := _out(b)
		if o and o.get("card"):
			outs += 1
	if _out(game.barricades.windows[0]) != null:
		at.check(outs == game.barricades.windows.size(), "dehors posé derrière chaque fenêtre (%d / %d)" % [outs, game.barricades.windows.size()])
	var done := {}
	for b: Barricade in game.barricades.windows:
		if done.has(b.zone) or not b.zone in ["a", "c", "e"]:
			continue
		done[b.zone] = true
		await _window(b, "bunker_" + b.zone)
	# Vue large de la salle de garde (fenêtres dans le décor).
	await _shot(Vector3(9.0, 1.7, 26.0), Vector3(5.5, 1.4, 30.5), "bunker_garde_large")
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


func _window(b: Barricade, shot_name: String) -> void:
	var s := b.global_transform.basis.x
	s.y = 0.0
	s = s.normalized()
	var at_p := b.global_position + Vector3.UP * 1.5
	for k in 3:
		await _shot(b.global_position + b.inward * 3.2 + s * 0.6 + Vector3.UP * 1.65, at_p + Vector3.DOWN * 0.3, "%s_face%d" % [shot_name, k])
		await seconds(2.5)
	await _shot(b.global_position + b.inward * 1.3 + s * 0.2 + Vector3.UP * 1.6, at_p, shot_name + "_pres")
	b.srv_set_mask(b.full_mask() & 0b010101)
	await seconds(0.9)
	await _shot(b.global_position + b.inward * 2.6 + Vector3.UP * 1.7, at_p + Vector3.DOWN * 0.5, shot_name + "_moitie")
	await _shot(b.global_position + b.inward * 4.5 - s * 1.2 + Vector3.UP * 1.7, b.global_position + b.inward * 1.5, shot_name + "_raies")
	b.srv_set_mask(0)
	await seconds(1.5)
	await _shot(b.global_position + b.inward * 2.6 + Vector3.UP * 1.7, at_p, shot_name + "_ouverte")
	# Fond de la poche de près, silhouettes forcées (réglage du shader).
	var o := _out(b)
	var c := b.global_position - b.inward * 2.4 + Vector3.UP * 1.65
	if o and o.get("card"):
		o.set("activity_override", 1.0)
		c = (o.get("card") as Node3D).global_position
	for k in 3:
		await seconds(1.6)
		await _shot(c + b.inward * 2.4 + Vector3.UP * 0.05, c, "%s_vitre%d" % [shot_name, k])
	if o:
		o.set("activity_override", -1.0)
	b.srv_set_mask(b.full_mask())
	await seconds(0.6)


func _mesh_map(map_id: String) -> void:
	if not await _start(map_id):
		return
	var tagname := map_id.replace(":", "_")
	for i in mini(game.barricades.windows.size(), 2):
		var b: Barricade = game.barricades.windows[i]
		if _out(b) != null:
			at.check(_out(b).get("card") != null, "%s : dehors de l'entrée %d" % [tagname, i])
		await _window(b, "%s_%d" % [tagname, i])
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
