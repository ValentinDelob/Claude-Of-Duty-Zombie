extends AutotestScenario
## @rendu : captures des portes à zombies (revue humaine du modèle).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="zombie_door_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Fenêtre d'avant (SMALLEST), porte simple et porte double (copies de
## SMALLEST, tests/fixtures/maps/) vues de la salle à 2,5 m, de biais, de
## près, puis à moitié arrachées, sans planches, et depuis la cour dehors.

const MAPS := ["smallest", "smallest_door", "smallest_double_door"]
const SW := preload("res://tests/autotest/smallest_window.gd")

var H := AutotestHelpers
var game: Game
var p: Player
var cam: Camera3D


func run() -> void:
	timeout_sec = 300
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	for map_id in MAPS:
		var dir := SW.install_fixture(map_id, "res://tests/fixtures/maps/" + map_id)
		at.check(dir != "", "%s copiée (%s)" % [map_id, dir])
		if dir == "":
			return
		p = await H.start_solo_game(self, EditorMapDef.CUSTOM_PREFIX + map_id)
		if p == null:
			return
		game = Game.instance
		game.rounds.paused = true
		game.combat.debug_invulnerable = true
		await H.clear_zombies(self)
		cam = null
		await seconds(4.0)  # titre de la carte effacé
		var b: Barricade = game.barricades.windows[0]
		await _view(b, 2.5, 0.0, 1.2, map_id + "_face")
		await _view(b, 2.2, 1.4, 1.1, map_id + "_biais")
		await _view(b, 1.2, 0.35, 1.0, map_id + "_pres")
		b.srv_set_mask(b.full_mask() & 0b0101010101)
		await seconds(0.8)  # planches tombées
		await _view(b, 2.5, 0.3, 1.2, map_id + "_moitie")
		b.srv_set_mask(0)
		await seconds(0.8)
		await _view(b, 2.5, -0.3, 1.2, map_id + "_ouverte")
		b.srv_set_mask(b.full_mask())
		await seconds(0.6)
		await _view(b, -2.2, 0.4, 1.2, map_id + "_dehors")
		Router.back_to_menu()
		await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	SW.remove_dir(EditorMap.maps_root())


## Joueur à `dist` m de l'entrée (négatif : dehors), décalé de `side` m le
## long du mur, qui vise le milieu de l'ouverture à `h` m.
## Caméra à hauteur d'yeux (sans HUD ni arme), joueur posé juste derrière.
func _view(b: Barricade, dist: float, side: float, h: float, shot_name: String) -> void:
	var s := b.global_transform.basis.x
	s.y = 0.0
	var pos := b.global_position + b.inward * dist + s.normalized() * side
	p.teleport_to(pos + b.inward * signf(dist) * 0.8 + Vector3(0, 0.05, 0))
	await seconds(0.3)  # posé après le téléport
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 62.0
		game.add_child(cam)
	cam.make_current()
	game.hud.visible = false
	cam.look_at_from_position(pos + Vector3.UP * 1.6, b.global_position + Vector3.UP * h)
	await seconds(0.4)  # capture : image posée
	await at.screenshot(shot_name)
