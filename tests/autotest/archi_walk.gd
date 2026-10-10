extends AutotestScenario
## ARCHITECTURE CUBIQUE (docs/VOXEL_ARCHITECTURE_PLAN.md) : ce que vérifiaient
## les scénarios de captures retirés au lot E (voxel_archi_look,
## voxel_stairs_look), sans capture : le joueur monte à pied l'escalier droit
## en marches de cubes jusqu'à la mezzanine (collision en rampe), et bute sur
## le mur libre en biais en escalier de cubes (collision lisse tournée).

const Diag := preload("res://tests/test_map_editor_diagonal.gd")
const Stairs := preload("res://tests/test_stairs.gd")

var H := AutotestHelpers
var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 90
	var p := await _play(Stairs.stairs_map(), "archi_escaliers")
	if p == null:
		return
	at.check(Game.instance.world.find_children("*__stair", "MeshInstance3D", true, false).size() >= 1, "marches en cubes construites")
	p.global_position = Vector3(off + 4.25, 0.05, off + 18.0)
	H.aim_at(p, Vector3(off + 4.25, 3.0, off + 5.0))
	p.input.move = Vector2(0, 1)
	var up: bool = await until(func(): return p.global_position.y > 3.4, 8.0, "le joueur monte l'escalier droit")
	p.input.move = Vector2.ZERO
	at.check(up, "joueur sur la mezzanine (y = %.2f)" % p.global_position.y)
	await _back()
	p = await _play(Diag.diag_map(), "archi_biais")
	if p == null:
		return
	at.check(Game.instance.world.find_children("*__biais", "MeshInstance3D", true, false).size() >= 1, "murs en biais en cubes construits")
	p.global_position = Vector3(off + 9.0, 0.05, off + 9.0)
	H.aim_at(p, Vector3(off + 13.0, 1.6, off + 13.0))
	p.input.move = Vector2(0, 1)
	await seconds(1.6)
	p.input.move = Vector2.ZERO
	var pp := p.global_position
	at.check(pp.x + pp.z - 2.0 * off < 20.0 - 0.25, "le joueur bute sur le mur en biais (x + y = %.2f)" % (pp.x + pp.z - 2.0 * off))
	await _back()


func _play(doc: EditorMap, id: String) -> Player:
	doc.carte["id"] = id
	if doc.save_dir(EditorMap.map_dir(id)) != OK:
		at.fail("carte d'essai non enregistrée : " + id)
		return null
	var p := await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + id)
	if p == null:
		return null
	Game.instance.rounds.paused = true
	Game.instance.combat.debug_invulnerable = true
	p.bot_controlled = true
	await H.clear_zombies(self)
	return p


func _back() -> void:
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
