extends AutotestScenario
## @rendu : captures de la boîte mystère (revue humaine du modèle et du faisceau).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="box_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Boîte mystère vue par le joueur : à 2 m, à 10 m et de loin (couloir), sur
## BUNKER K-7, KINO et DRAFT ARENA (carte de l'éditeur) ; couvercle fermé,
## ouvert pendant le défilement, arme prête, LIQUIDATION, départ (ours).

var H := AutotestHelpers
var game: Game
var p: Player


func run() -> void:
	timeout_sec = 300
	for map_id in ["bunker_k7", "kino", "draft_arena"]:
		await _map_pass(map_id)
		if p == null:
			return
		Router.back_to_menu()
		await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "retour au menu")


func _map_pass(map_id: String) -> void:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	await seconds(0.5)  # collisions des portes coupées (différé) avant les téléports
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null, "%s : boîte mystère" % map_id)
	if box == null:
		return
	await _shot(box, 2.0, 0.6, "%s_2m" % map_id)
	if map_id == "bunker_k7":
		# Gros plans des matières : angle ferré et pochoir, serrure et couvercle.
		await _close(box, Vector3(0.75, 0.45, 0.42), Vector3(1.5, 1.0, 1.1), "bunker_k7_detail_angle")
		await _close(box, Vector3(0.0, 0.7, 0.4), Vector3(-0.4, 1.35, 1.2), "bunker_k7_detail_serrure")
	await _shot(box, 10.0, 0.0, "%s_10m" % map_id)
	await _cost(box, map_id)
	await _shot(box, 40.0, 0.0, "%s_loin" % map_id)
	if map_id != "bunker_k7":
		return
	var pd := game.session.local_data()
	game.session.add_points(1, 20000)
	await _shot(box, 2.4, 0.8, "bunker_k7_avant_achat")
	p.input.interact_pressed = true
	await until(func(): return box.state == MysteryBox.State.ROLLING, 2.0, "défilement")
	await seconds(1.2)  # capture : couvercle ouvert, armes qui défilent
	await at.screenshot("bunker_k7_defilement")
	await _shot(box, 10.0, 0.0, "bunker_k7_defilement_10m")
	await until(func(): return box.state == MysteryBox.State.READY, 6.0, "arme prête")
	await _shot(box, 2.4, 0.8, "bunker_k7_prete")
	p.input.interact_pressed = true
	await until(func(): return box.state == MysteryBox.State.IDLE, 2.0, "arme prise")
	# LIQUIDATION : boîtes temporaires aux autres emplacements.
	box.moves = 1
	var id := game.powerups.debug_drop(PowerupRules.FIRE_SALE, p.global_position)
	await until(func(): return not game.powerups.nodes.has(id), 2.0, "liquidation ramassée")
	await until(func(): return box.fire_sale_boxes.size() > 0, 3.0, "boîtes de liquidation")
	await seconds(0.8)  # capture : boîtes déployées
	if box.fire_sale_boxes.size() > 0:
		await _shot(box.fire_sale_boxes[0], 2.6, 0.8, "bunker_k7_liquidation")
		await _shot(box.fire_sale_boxes[0], 10.0, 0.0, "bunker_k7_liquidation_10m")
	box.set_fire_sale(false)
	await seconds(0.3)  # boîtes temporaires retirées
	# Départ (ours) : la boîte s'envole.
	await _shot(box, 2.6, 0.6, "bunker_k7_avant_ours")
	box.force_result = "skull"
	p.input.interact_pressed = true
	await until(func(): return box.state == MysteryBox.State.MOVING, 6.0, "ours")
	await seconds(1.0)  # capture : ours au-dessus de la boîte
	await at.screenshot("bunker_k7_ours")
	await seconds(1.6)  # capture : la boîte s'envole
	await at.screenshot("bunker_k7_envol")
	at.check(pd != null, "partie en cours")


## Coût de rendu de la boîte vue à 10 m : appels de dessin et primitives de
## l'image, boîte affichée puis masquée (imprimé pour le rapport).
func _cost(box: MysteryBox, map_id: String) -> void:
	var info := func() -> Vector2i:
		await frames(4)
		return Vector2i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var shown: Vector2i = await info.call()
	box.visible = false
	var hidden: Vector2i = await info.call()
	box.visible = true
	print("[box_look] %s : coût de la boîte à 10 m : %d appels de dessin, %d primitives" % [map_id, shown.x - hidden.x, shown.y - hidden.y])


## Gros plan : joueur debout en `eye` (x, z dans le repère de la boîte, +Z
## vers le joueur ; y ignoré), visant `target` (même repère).
func _close(box: MysteryBox, target: Vector3, eye: Vector3, shot_name: String) -> void:
	var xf := box.global_transform
	p.teleport_to(xf * Vector3(eye.x, 0.05, eye.z))
	await seconds(0.3)  # posé après le téléport
	H.aim_at(p, xf * target)
	await seconds(0.3)  # capture : image posée
	await at.screenshot(shot_name)


## Se place à `dist` m de la boîte (au plus loin possible dans l'axe le plus
## dégagé devant elle), décalé de `side` m, et la regarde.
func _shot(box: MysteryBox, dist: float, side: float, shot_name: String) -> void:
	var n: Vector3 = box.spots[box.location].normal
	var fwd := -Vector3(n.x, 0, n.z).normalized()
	var o := box.global_position + Vector3.UP * 1.5
	var space := game.world.get_world_3d().direct_space_state
	var best_dir := fwd
	var best := 0.0
	# Direction la plus dégagée (la plus proche de l'avant à distance égale).
	for k in 25:
		var a := (k - 12) * PI / 28.0
		var d := fwd.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(o + d * 0.9, o + d * (dist + 1.0))
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var free := dist + 1.0 if hit.is_empty() else o.distance_to(hit.position)
		var score := minf(free, dist + 1.0) - absf(a) * 0.5
		if score > best:
			best = score
			best_dir = d
	var q2 := PhysicsRayQueryParameters3D.create(o + best_dir * 0.9, o + best_dir * (dist + 1.0))
	q2.exclude = [p.get_rid()]
	var hit2 := space.intersect_ray(q2)
	var reach := dist if hit2.is_empty() else maxf(1.6, o.distance_to(hit2.position) - 0.8)
	var pos := box.global_position + best_dir * minf(dist, reach) + best_dir.cross(Vector3.UP) * side
	p.teleport_to(pos + Vector3(0, 0.05, 0))
	await seconds(0.3)  # posé après le téléport
	# De loin, la boîte sous le réticule (pas cachée par lui).
	H.aim_at(p, box.global_position + Vector3.UP * (0.6 if dist < 4.0 else (1.2 if dist < 15.0 else 2.4)))
	await seconds(0.4)  # capture : image posée (brume temporelle)
	print("[box_look] %s : %.1f m" % [shot_name, p.global_position.distance_to(box.global_position)])
	await at.screenshot(shot_name)
