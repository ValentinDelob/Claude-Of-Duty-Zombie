extends AutotestScenario
## Énergie (GAME_CONCEPT §4.14, PlayerEnergy) : course jusqu'à l'épuisement
## (~4 s), puis course refusée, saut plus bas, couteau plus lent, recharge
## plus lente, fin de l'épuisement à 50 et course de nouveau possible.

var H := AutotestHelpers
var p: Player
## Plus haute position atteinte depuis la dernière remise à zéro.
var _peak := -INF
## Énergie juste après le décollage / le départ du coup (avant toute recharge).
var _energy_after := 0.0


func run() -> void:
	timeout_sec = 60
	p = await H.start_solo_game(self)
	if p == null:
		return
	Game.instance.rounds.paused = true
	await H.clear_zombies(self)
	p.untargetable = true
	p.teleport_to(Vector3(3.0, 0.05, 3.4), -PI * 0.5)
	p.pitch = 0.0
	tree().physics_frame.connect(_tick)
	await seconds(0.3)

	# Référence, énergie pleine : hauteur d'un saut, durée d'un coup.
	var jump_full := await _jump_height()
	var e := p.energy
	at.check(absf(_energy_after - (e.max_value - PlayerEnergy.JUMP_COST)) < 0.5, "le saut coûte %d (%.1f)" % [PlayerEnergy.JUMP_COST, _energy_after])
	e.value = e.max_value
	var knife_full := await _knife_time()
	var cost := KnifeDB.energy_cost(p.weapons.knife_id)
	at.check(absf(_energy_after - (e.max_value - cost)) < 0.5, "le coup de couteau coûte %.0f (%.1f)" % [cost, _energy_after])

	# Course jusqu'à l'épuisement, touche gardée.
	e.value = e.max_value
	e.exhausted = false
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await until(func(): return p.sprinting, 1.0, "départ de la course")
	var t0 := GameClock.now()
	await until(func(): return not p.sprinting, 6.0, "fin de la course")
	var run_time := GameClock.now() - t0
	at.check(run_time > 3.6 and run_time < 4.4, "course pleine d'environ 4 s (%.2f s)" % run_time)
	at.check(e.exhausted and e.value <= 0.0, "épuisé, énergie nulle (%.1f)" % e.value)

	# Course refusée : nouvel appui, rien.
	p.input.sprint = false
	await frames(3)
	p.input.sprint = true
	await seconds(0.3)
	at.check(not p.sprinting, "épuisé : la course est refusée")
	p.input.sprint = false
	p.input.move = Vector2.ZERO
	await until(func(): return p.is_on_floor() and Vector2(p.velocity.x, p.velocity.z).length() < 0.1, 2.0, "arrêt")

	# Saut plus bas, couteau plus lent.
	var jump_tired := await _jump_height()
	at.check(jump_tired < jump_full * 0.7, "épuisé : saut plus bas (%.2f m contre %.2f m)" % [jump_tired, jump_full])
	var knife_tired := await _knife_time()
	var k := knife_tired / knife_full
	at.check(k > 1.7 and k < 2.3, "épuisé : coup deux fois plus lent (%.2f s contre %.2f s)" % [knife_tired, knife_full])
	at.check(e.exhausted, "toujours épuisé après le saut et le coup")

	# Recharge plus lente (30 / s), mesurée après le délai.
	await seconds(PlayerEnergy.REGEN_DELAY + 0.1)
	var v0 := e.value
	var r0 := GameClock.now()
	await until(func(): return GameClock.now() - r0 >= 0.5, 2.0, "mesure de la recharge")
	var rate := (e.value - v0) / (GameClock.now() - r0)
	at.check(rate > 26.0 and rate < 34.0, "épuisé : recharge à 30 / s (%.1f / s)" % rate)

	# Fin de l'épuisement à 50, la course repart.
	await until(func(): return not e.exhausted, 3.0, "fin de l'épuisement")
	at.check(e.value >= PlayerEnergy.RECOVER_AT and e.value < PlayerEnergy.RECOVER_AT + 2.0, "fin de l'épuisement à 50 (%.1f)" % e.value)
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await until(func(): return p.sprinting, 1.0, "reposé : la course repart")
	p.input = PlayerInput.new()
	tree().physics_frame.disconnect(_tick)


## Bande de course bouclée (comme sprint_restart) et sommet des sauts.
func _tick() -> void:
	var gp := p.global_position
	if gp.x > 22.0: gp.x -= 18.0
	elif gp.x < 3.0: gp.x += 18.0
	if gp != p.global_position:
		p.global_position = gp
	_peak = maxf(_peak, p.global_position.y)


## Hauteur d'un saut sur place (m).
func _jump_height() -> float:
	var y0 := p.global_position.y
	_peak = y0
	p.input.jump = true
	await until(func(): return not p.is_on_floor(), 1.0, "décollage")
	_energy_after = p.energy.value
	await until(func(): return p.is_on_floor(), 2.0, "atterrissage")
	return _peak - y0


## Coup de couteau (appui répété jusqu'à ce qu'il parte) : durée pendant
## laquelle le joueur est occupé par le coup (s, temps de jeu).
func _knife_time() -> float:
	var ok: bool = await until(func():
		if p.weapons.is_knifing():
			return true
		p.input.melee = true
		return false, 2.0, "coup de couteau parti")
	_energy_after = p.energy.value
	if not ok:
		return 1.0
	var t0 := GameClock.now()
	await until(func(): return not p.weapons.is_knifing(), 3.0, "fin du coup de couteau")
	return GameClock.now() - t0
