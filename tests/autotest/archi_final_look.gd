extends AutotestScenario
## @rendu : ARCHITECTURE CUBIQUE, lot E (docs/VOXEL_ARCHITECTURE_PLAN.md) :
## captures finales : murs en biais et escalier tourné de près sous une lampe
## proche à ombres (ombres des marches), test_levels construite par le jeu
## (escalier, garde-corps, pente en terrasses), BUNKER K-7 et DRAFT ARENA.
## @niveau perf : hors check (captures d'un ajout en cours).
## Captures : tests/_out/shots/archi_final_look_*.png.

const Diag := preload("res://tests/test_map_editor_diagonal.gd")
const Free := preload("res://tests/test_map_editor_freeform.gd")
const Stairs := preload("res://tests/test_stairs.gd")

var H := AutotestHelpers
var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 600
	await _custom(Diag.diag_map(), "lot_e_biais", [
		# [nom, lampe (éditeur, hauteur), joueur, point visé]
		["biais_lampe", Vector3(9.3, 2.2, 9.3), Vector2(8.6, 9.6), Vector3(10.1, 1.0, 10.1)],
		["biais_lampe_rasant", Vector3(9.6, 1.8, 9.0), Vector2(8.3, 11.2), Vector3(11.5, 1.2, 8.5)],
		["biais_porte", Vector3(15.0, 2.2, 15.0), Vector2(14.3, 14.3), Vector3(15.6, 1.2, 16.6)],
	])
	var rot := Free.stairs_map()
	rot.find("e1")["garde_corps"] = true
	await _custom(rot, "lot_e_tourne", [
		["tourne_lampe", Vector3(9.8, 2.0, 9.8), Vector2(10.5, 10.5), Vector3(8.0, 0.8, 8.5)],
		["tourne_loin", Vector3(9.8, 2.0, 9.8), Vector2(13.0, 13.5), Vector3(8.0, 1.2, 8.0)],
		["tourne_marches", Vector3(9.5, 1.6, 12.5), Vector2(6.5, 14.5), Vector3(8.0, 0.8, 8.5)],
	])
	var stairs := Stairs.stairs_map()
	for o in stairs.objets:
		if o.get("type") == "escalier":
			o["garde_corps"] = true
	await _custom(stairs, "lot_e_escaliers", [
		["escaliers", Vector3(9.0, 2.6, 16.0), Vector2(12.0, 19.0), Vector3(6.0, 1.0, 12.0)],
	])
	await _levels()
	await _builtin("bunker_k7")
	await _builtin("draft_arena")


func _lamp(pos: Vector3) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.omni_range = 8.0
	lamp.light_energy = 2.5
	lamp.omni_attenuation = 1.3
	lamp.set_meta("lamp_index", 0)
	RenderQuality.apply_lamp(lamp, RenderQuality.current())
	lamp.shadow_enabled = true
	Game.instance.world.add_child(lamp)
	lamp.global_position = pos
	return lamp


func _start(id: String) -> Player:
	var p := await H.start_solo_game(self, id)
	if p == null:
		return null
	Game.instance.rounds.paused = true
	Game.instance.combat.debug_invulnerable = true
	p.bot_controlled = true
	await H.clear_zombies(self)
	await seconds(1.5)
	return p


func _back() -> void:
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")


func _custom(doc: EditorMap, id: String, views: Array) -> void:
	doc.carte["id"] = id
	var dir := EditorMap.map_dir(id)
	if doc.save_dir(dir) != OK:
		at.fail("carte d'essai non enregistrée dans " + dir)
		return
	var p := await _start(EditorMapDef.CUSTOM_PREFIX + id)
	if p == null:
		return
	var lamp: OmniLight3D = null
	for vw: Array in views:
		if lamp != null:
			lamp.queue_free()
		var lp: Vector3 = vw[1]
		lamp = _lamp(Vector3(off + lp.x, lp.y, off + lp.z))
		var at2: Vector2 = vw[2]
		p.global_position = Vector3(off + at2.x, 0.05, off + at2.y)
		H.aim_at(p, vw[3] + Vector3(off, 0, off))
		await seconds(0.6)
		await at.screenshot(String(vw[0]))
	await _back()


func _levels() -> void:
	var p := await _start("test_levels")
	if p == null:
		return
	var lamp := _lamp(Vector3.ZERO)
	for vw in [["test_levels", Vector3(15.0, 0.05, 21.0), Vector3(11.2, 1.5, 15.0)],
			["test_levels_rail", Vector3(18.0, 3.05, 10.5), Vector3(13.0, 3.6, 14.0)],
			["test_levels_pente", Vector3(16.0, 0.05, 23.0), Vector3(16.0, -1.4, 30.0)]]:
		lamp.global_position = vw[1] + Vector3(0, 2.5, 0)
		p.global_position = vw[1]
		H.aim_at(p, vw[2])
		await seconds(0.6)
		await at.screenshot(String(vw[0]))
	await _back()


## Carte du jeu : vue du départ, puis trois quarts de tour.
func _builtin(id: String) -> void:
	var p := await _start(id)
	if p == null:
		return
	var start := p.global_position
	for k in 4:
		p.global_position = start
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI / 2.0)
		H.aim_at(p, start + dir * 6.0 + Vector3(0, 1.3, 0))
		await seconds(0.6)
		await at.screenshot("%s_%d" % [id, k])
	await _back()
