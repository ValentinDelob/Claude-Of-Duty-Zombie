extends AutotestScenario
## @rendu
## @niveau perf
## OUTIL (hors check : « @niveau perf ») : aperçus des cartes du jeu pour
## l'écran JOUER du hub v2 (Partie.dc.html : l'aperçu est une vue de la carte
## en jeu). Pour chaque carte de Game.MENU_MAPS : partie solo, manche en
## pause, zombies retirés, interface et mains masquées, caméra à la place des
## yeux du joueur au départ, image 1280 × 720 enregistrée dans
## assets/ui/hub/maps/<carte>.png (lue par Hub2PlayPanel.map_picture ; les
## cartes perso gardent leur plan, MapPreview).
## Lancer avec : sh tools/map_shots.sh (fenêtre hors écran, puis import).

const OUT := "res://assets/ui/hub/maps/"

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90 * Game.MENU_MAPS.size()
	if DisplayServer.get_name() == "headless":
		at.fail("map_shots demande le rendu (sh tools/map_shots.sh)")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in Game.MENU_MAPS:
		await _shoot(String(id))


func _shoot(id: String) -> void:
	var p := await H.start_solo_game(self, id)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	# Titre de la carte effacé, lumières et brouillard posés.
	await seconds(4.0)
	await H.clear_zombies(self)
	var cam := Camera3D.new()
	cam.fov = p.camera.fov
	cam.near = p.camera.near
	cam.far = p.camera.far
	game.add_child(cam)
	cam.global_transform = p.camera.global_transform
	# Vers la porte payante la plus proche du départ (maquette : la porte au
	# centre, la station à côté), à hauteur des yeux.
	var eye := p.camera.global_position
	var best: Node3D = null
	for d in game.doors.values():
		if d is Node3D and (best == null or eye.distance_to(d.global_position) < eye.distance_to(best.global_position)):
			best = d
	if best:
		var target := Vector3(best.global_position.x, eye.y - 0.15, best.global_position.z)
		if target.distance_to(eye) > 0.5:
			cam.look_at_from_position(eye, target)
	cam.make_current()
	game.hud.visible = false
	if p.weapons and p.weapons.view:
		p.weapons.view.visible = false
	await seconds(1.0)
	await frames(3)
	var img := at.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + id + ".png")
	var err := img.save_png(path)
	at.check(err == OK, "aperçu de %s : %s (%d × %d)" % [id, path, img.get_width(), img.get_height()])
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
