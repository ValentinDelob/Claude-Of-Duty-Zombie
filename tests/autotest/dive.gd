extends AutotestScenario
## Plongeon (dolphin dive de BO1) : accroupi en plein sprint = saut rasant
## vers l'avant (~3 m), atterrissage à plat ventre, relevé ; position allongée
## (touche accroupie maintenue à l'arrêt), reptation lente ; signal serveur
## player_dived_landed (crochet de l'atout PhD) ; pose du soldat vue de côté.

var H := AutotestHelpers
var p: Player
var _landings: Array = []
var _cam: Camera3D


func eye() -> float:
	return p.head.position.y


## Sprint vers +X depuis le début de l'allée, puis plongeon.
func sprint_and_dive(hold_crouch: bool) -> Vector3:
	p.input.crouch = false
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 7), 0.05), -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.3)  # le joueur se pose après la téléportation
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await seconds(0.45)  # élan
	at.check(p.sprinting, "sprint avant le plongeon")
	var from := p.global_position
	p.input.crouch = true
	await until(func(): return p.diving, 0.5, "plongeon déclenché")
	if not hold_crouch:
		await seconds(0.05)  # simple pression de la touche
		p.input.crouch = false
	return from


## Soldat visible, vu de côté par une caméra de test (pose réseau des coéquipiers).
func third_person(on: bool) -> void:
	p.visual.visible = on
	if on:
		_cam = Camera3D.new()
		Game.instance.add_child(_cam)
		_cam.fov = 60.0
		_cam.current = true
		tree().physics_frame.connect(_animate_visual)
	else:
		tree().physics_frame.disconnect(_animate_visual)
		_cam.queue_free()
		p.camera.current = true


func _animate_visual() -> void:
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	p.visual.animate(1.0 / 60.0, speed, p.pitch, p._compute_flags(), false, false)
	_cam.global_position = p.global_position + Vector3(0.0, 1.3, 3.2)
	_cam.look_at(p.global_position + Vector3(0, 0.4, 0), Vector3.UP)


func run() -> void:
	timeout_sec = 90
	p = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.player_dived_landed.connect(func(pid: int, pos: Vector3, h: float): _landings.append([pid, pos, h]))

	# 1. Plongeon en sprint, touche maintenue : reste à plat ventre.
	var from := await sprint_and_dive(true)
	at.check(not p.sprinting and p.velocity.y > 1.0, "saut rasant vers l'avant (vy %.1f)" % p.velocity.y)
	await seconds(0.12)  # capture : en l'air
	await at.screenshot("dive_air")
	var ok: bool = await until(func(): return not p.diving, 1.5, "atterrissage")
	var landed_at := p.global_position
	var dist := Vector2(landed_at.x - from.x, landed_at.z - from.z).length()
	at.check(ok and p.prone, "atterrissage à plat ventre")
	at.check(dist > 2.0 and dist < 4.0, "plongeon de %.2f m" % dist)
	await until(func(): return _landings.size() >= 1, 1.0, "signal player_dived_landed")
	at.check(_landings.size() == 1 and _landings[0][0] == 1, "serveur : player_dived_landed reçu (%d)" % _landings.size())
	if not _landings.is_empty():
		at.check(_landings[0][1].distance_to(landed_at) < 1.0 and _landings[0][2] > 0.1 and _landings[0][2] < 1.0,
			"position et hauteur du plongeon (%.2f m)" % _landings[0][2])
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	await seconds(0.8)  # fenêtre fixe : reste allongé tant que la touche est tenue
	at.check(p.prone and eye() < 0.6, "allongé tant que la touche est maintenue (yeux à %.2f m)" % eye())
	await at.screenshot("prone_view")
	# Reptation lente, pas de saut ni de sprint.
	var crawl_from := p.global_position
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await seconds(1.0)  # durée mesurée
	var crawled := p.global_position.distance_to(crawl_from)
	at.check(p.prone and not p.sprinting and crawled > 0.5 and crawled < 1.4, "reptation lente (%.2f m en 1 s)" % crawled)
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	# Relâcher : on se relève.
	p.input.crouch = false
	await until(func(): return not p.prone and not p.crouching and eye() > 1.5, 2.0, "relevé")
	at.check(not p.prone and not p.crouching and eye() > 1.5, "relevé (yeux à %.2f m)" % eye())

	# 2. Plongeon avec simple pression : relevé automatique après l'atterrissage.
	await sprint_and_dive(false)
	ok = await until(func(): return p.prone, 1.5, "à plat ventre")
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	await seconds(0.25)  # fenêtre fixe : encore à plat ventre juste après
	at.check(p.prone, "brève glissade à plat ventre")
	ok = await until(func(): return not p.prone, 1.5, "relevé automatique")
	await until(func(): return eye() > 1.4, 2.0, "caméra à hauteur debout")
	at.check(ok and eye() > 1.4, "se relève seul (yeux à %.2f m)" % eye())
	at.check(_landings.size() == 2, "2e plongeon signalé au serveur")

	# 3. Accroupi en marchant : pas de plongeon.
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 7), 0.05), -PI * 0.5)
	p.input.move = Vector2(0, 1)
	await seconds(0.4)  # marche
	p.input.crouch = true
	await seconds(0.3)  # fenêtre fixe : aucun plongeon ne doit partir
	at.check(not p.diving and p.crouching and not p.prone, "accroupi en marchant : pas de plongeon")
	# 4. Maintien à l'arrêt : accroupi, puis allongé après ~0,6 s.
	p.input.move = Vector2.ZERO
	await seconds(0.35)  # durée mesurée : pas encore allongé
	at.check(p.crouching and not p.prone, "accroupi à l'arrêt")
	await seconds(0.7)  # durée mesurée : allongé après ~0,6 s
	at.check(p.prone, "allongé après maintien de la touche")
	p.input.jump = true
	await seconds(0.1)  # touche tenue
	at.check(p.global_position.y < 0.2, "pas de saut depuis la position allongée")
	p.input.crouch = false
	await until(func(): return not p.prone and eye() > 1.5, 2.0, "debout")
	at.check(not p.prone and eye() > 1.5, "debout")

	# 5. Pose du soldat (vue des coéquipiers) : plongeon puis allongé.
	third_person(true)
	await sprint_and_dive(true)
	await seconds(0.15)  # capture
	await at.screenshot("dive_pose")
	await until(func(): return not p.diving, 1.5, "atterrissage")
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	await seconds(0.7)  # capture : pose allongée
	await at.screenshot("prone_pose")
	p.input.crouch = false
	await seconds(1.0)  # capture : pose debout
	await at.screenshot("stand_pose")
	third_person(false)
