extends AutotestScenario
## @rendu : captures de la caisse au hasard posée au sol (format 15), revue humaine.
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="map_box_floor_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Éditeur : caisse au sol tournée de 45° (emprise, avant fléché, anneau) à
## côté d'une caisse murale (ignorée en jeu : une seule par carte, celle
## marquée « depart ») ; en jeu : la caisse au milieu de la salle, de face,
## de biais et de dos, puis ouverte (défilement) et l'objet prêt.

const Play := preload("res://tests/autotest/map_box_floor_play.gd")
const DecorFree := preload("res://tests/test_map_decor_free.gd")
const OFF := MapGeom.WORLD_OFFSET

var ed: MapEditor
var p: Player


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	var doc := DecorFree.two_rooms()
	for o in doc.objets:
		if String(o.get("type", "")) == "boite":
			o.erase("depart")
	var fb := DecorFree._obj(doc, {"type": "boite", "position": [Play.CENTER.x, Play.CENTER.y], "rot": 45, "depart": true})
	ed.new_map(true)
	ed._reset(doc)
	await frames(2)
	ed.canvas.zoom = 34.0
	ed.canvas.origin = Vector2(30, 60)
	ed.select(String(fb.id))
	await seconds(0.4)
	await at.screenshot("editeur_dessus")
	# TESTER.
	if not ed.test_map():
		at.fail("TESTER refusé : %s" % str(ed.validator.errors().map(func(m): return m.fr) if ed.validator else []))
		return
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée"):
		return
	var game := Game.instance
	p = game.local_player
	p.bot_controlled = true
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	var box: MysteryBox = game.interact.get_obj("box")
	await seconds(0.5)
	var front := box.global_transform.basis.z
	var side := front.cross(Vector3.UP)
	await _shot(box, front, 2.6, "jeu_face")
	await _shot(box, (front + side).normalized(), 3.2, "jeu_biais")
	await _shot(box, -front, 2.6, "jeu_dos")
	await _shot(box, front, 7.0, "jeu_loin")
	game.session.add_points(p.peer_id, 20000)
	await _shot(box, front, 1.4, "jeu_invite")
	box.force_result = "decoy"
	p.input.interact_pressed = true
	await until(func(): return box.state == MysteryBox.State.ROLLING, 3.0, "défilement")
	await seconds(1.4)
	await _shot(box, front, 2.4, "jeu_ouverte")
	await until(func(): return box.state == MysteryBox.State.READY, 8.0, "objet prêt")
	await _shot(box, front, 2.0, "jeu_objet_pret")
	await _shot(box, side, 2.2, "jeu_objet_pret_cote")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")


func _shot(box: MysteryBox, dir: Vector3, dist: float, shot_name: String) -> void:
	var c := box.global_position
	p.teleport_to(c + dir.normalized() * dist + Vector3.UP * 0.05)
	await seconds(0.3)
	AutotestHelpers.aim_at(p, c + Vector3.UP * 0.6)
	await seconds(0.3)
	await at.screenshot(shot_name)
