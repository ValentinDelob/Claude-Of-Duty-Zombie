extends AutotestScenario
## Fenêtres barricadées (BUNKER K-7, salle de garde) : un zombie apparu dehors
## arrache les 6 planches une par une puis enjambe la fenêtre ; le joueur
## répare en maintenant [F] (+10 par planche, double points, plafond de 500 par
## manche) ; coup à travers la fenêtre ; captures intacte / à moitié / détruite,
## vues de l'intérieur et de l'extérieur.

var H := AutotestHelpers
var game: Game
var p: Player
var w: Barricade


func _window_at(c: Vector2i) -> Barricade:
	for b in game.barricades.windows:
		if b.cell == c:
			return b
	return null


## Vue depuis l'intérieur (dist m devant la fenêtre) ou l'extérieur (dans la poche).
func _view(inside: bool, dist := 2.2) -> void:
	var side := w.inward if inside else -w.inward
	p.teleport_to(w.global_position + side * dist + Vector3(0, 0.05, 0))
	H.aim_at(p, w.global_position + Vector3.UP * 1.45)
	await seconds(0.45)


func _hold_repair() -> void:
	p.teleport_to(w.global_position + w.inward * 1.25 + Vector3(0, 0.05, 0))
	H.aim_at(p, w.global_position + Vector3.UP * 1.4)
	await seconds(0.2)
	p.input.interact = true
	p.input.interact_pressed = true


func _release() -> void:
	p.input.interact = false
	await seconds(0.2)


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	await seconds(2.0)  # fin du fondu de chargement
	var pd := game.session.local_data()
	var per_zone := {}
	for b in game.barricades.windows:
		per_zone[b.zone] = per_zone.get(b.zone, 0) + 1
	at.check(game.barricades.windows.size() >= 12, "%d fenêtres barricadées sur la carte" % game.barricades.windows.size())
	at.check(per_zone.get("a", 0) >= 3, "salle de garde : %d fenêtres" % per_zone.get("a", 0))
	w = _window_at(Vector2i(6, 31))
	at.check(w != null and w.planks() == 6, "fenêtre sud de la salle de garde : 6 planches")
	if w == null:
		return
	at.check(game.nav and not (game.nav as NavGrid).is_walkable(w.cell), "cellule de fenêtre bloquée pour l'A*")

	# 1. Fenêtre intacte, des deux côtés.
	await _view(true)
	await at.screenshot("intact_inside")
	at.check(game.interact.focused != w, "fenêtre intacte : pas d'invite")
	await _view(false, 1.6)
	await at.screenshot("intact_outside")

	# Le joueur ne passe pas par la fenêtre, même ouverte.
	w.srv_set_mask(0)
	p.teleport_to(w.global_position + w.inward * 1.6 + Vector3(0, 0.05, 0), atan2(w.inward.x, w.inward.z))
	p.input.move = Vector2(0, 1)
	await seconds(1.2)
	p.input.move = Vector2.ZERO
	at.check(w.is_inside(p.global_position), "fenêtre ouverte : le joueur ne peut pas sortir")
	w.srv_set_mask(BarricadeRules.FULL_MASK)
	await seconds(0.5)

	# 2. Un zombie apparaît dehors, arrache les planches et entre.
	p.teleport_to(w.global_position + w.inward * 2.4 + Vector3(0, 0.05, 0))
	H.aim_at(p, w.global_position + Vector3.UP * 1.3)
	var spawn := MapData.cell_to_world(w.spawn_cells[0])
	var zid := game.zombies.spawn(spawn, 0, 150)
	var z := game.zombies.get_zombie(zid)
	at.check(z.state == Zombie.State.BARRIER and z.barricade == w, "zombie de fenêtre : pas d'émergence, il vise sa fenêtre")
	var t0 := GameClock.msec()
	var ok: bool = await until(func(): return w.planks() == 3, 20.0, "3 planches arrachées")
	var escaped := false
	if ok:
		H.aim_at(p, w.global_position + Vector3.UP * 1.3)
		await at.screenshot("half_inside")
	ok = await until(func():
		if w.is_inside(z.global_position) and z.state == Zombie.State.BARRIER:
			escaped = true
		return w.planks() == 0, 15.0, "toutes les planches arrachées")
	var tear_s := (GameClock.msec() - t0) / 1000.0
	at.check(ok and tear_s >= 9.0, "le zombie arrache les 6 planches une par une, au rythme de BO1 (%.1f s)" % tear_s)
	at.check(not escaped, "tant qu'il reste une planche, le zombie reste dehors")
	ok = await until(func(): return z.state == Zombie.State.VAULT, 3.0, "enjambement")
	at.check(ok, "le zombie enjambe la fenêtre")
	await seconds(0.45)
	await at.screenshot("vault")
	ok = await until(func(): return z.state == Zombie.State.CHASE and w.is_inside(z.global_position), 4.0, "zombie entré")
	at.check(ok, "le zombie est entré dans la salle et poursuit le joueur")
	ok = await until(func(): return z.global_position.distance_to(p.global_position) < 1.8, 8.0, "zombie au contact")
	at.check(ok, "il rejoint le joueur")
	game.zombies.kill(zid, false, Vector3.FORWARD)
	await seconds(0.3)

	# 3. Réparation : +10 par planche (maintien de [F]).
	await _view(true)
	await at.screenshot("broken_inside")
	await _view(false, 1.6)
	await at.screenshot("broken_outside")
	var pts0 := pd.points
	var team0 := game.points.team_earned
	await _hold_repair()
	at.check(game.interact.focused == w and game.hud._prompt.text == Lang.t("Maintenir [F] pour reconstruire la barricade", "Hold [F] to rebuild the barrier"), "invite : « %s »" % game.hud._prompt.text)
	ok = await until(func(): return w.planks() >= 3, 4.0, "3 planches reposées")
	await at.screenshot("repairing")
	ok = await until(func(): return w.planks() == 6, 5.0, "fenêtre reconstruite")
	at.check(ok, "maintenir [F] reconstruit la fenêtre planche par planche")
	await seconds(0.5)
	at.check(pd.points - pts0 == 60, "+10 points par planche reposée (+%d)" % (pd.points - pts0))
	at.check(game.points.team_earned - team0 == 60, "points de réparation comptés pour l'apparition des bonus (+%d)" % (game.points.team_earned - team0))
	await _release()
	await at.screenshot("repaired_inside")

	# Relâcher [F] arrête la réparation.
	w.srv_set_mask(0)
	await _hold_repair()
	await seconds(0.9)
	await _release()
	var after_release := w.planks()
	await seconds(1.2)
	at.check(after_release >= 1 and w.planks() == after_release, "relâcher [F] arrête la réparation (%d planche(s))" % w.planks())

	# 4. Double points puis plafond de 500 par manche.
	w.srv_set_mask(0)
	game.barricades.repair_earned.clear()
	game.points.multiplier = 2
	pts0 = pd.points
	await _hold_repair()
	await until(func(): return w.planks() == 2, 3.0, "2 planches")
	await seconds(0.2)
	await _release()
	at.check(pd.points - pts0 == 40, "double points : +20 par planche (+%d)" % (pd.points - pts0))
	game.points.multiplier = 1
	w.srv_set_mask(0)
	game.barricades.repair_earned[1] = BarricadeRules.ROUND_CAP - 10
	pts0 = pd.points
	await _hold_repair()
	await until(func(): return w.planks() == 4, 5.0, "4 planches")
	await seconds(0.2)
	await _release()
	at.check(pd.points - pts0 == 10, "plafond de réparation : 500 points par manche (+%d)" % (pd.points - pts0))
	game.rounds.round_started.emit(game.rounds.round_n + 1)
	at.check(game.barricades.repair_earned.is_empty(), "plafond remis à zéro à la manche suivante")

	# 5. Coup à travers la fenêtre (planches presque toutes arrachées).
	w.srv_set_mask(0b000011)
	game.combat.debug_invulnerable = false
	pd.health = pd.max_health
	p.teleport_to(w.global_position + w.inward * 0.95 + Vector3(0, 0.05, 0))
	var zid2 := game.zombies.spawn(spawn, 1, 150)
	var z2 := game.zombies.get_zombie(zid2)
	ok = await until(func(): return pd.health < pd.max_health, 10.0, "coup à travers la fenêtre")
	at.check(ok, "un zombie frappe à travers la fenêtre le joueur collé contre elle (%d PV)" % pd.health)
	game.combat.debug_invulnerable = true
	at.check(z2.barricade == w and not w.is_inside(z2.global_position), "le zombie est resté dehors pour frapper")
	game.zombies.despawn(zid2)
	w.srv_set_mask(0b000111)
	await _view(false, 1.6)
	await seconds(0.3)
	await at.screenshot("half_outside")

	# 6. Bonus CHARPENTIER : Game.repair_all_barricades().
	for b in game.barricades.windows:
		b.srv_set_mask(0)
	game.repair_all_barricades()
	var all_full := true
	for b in game.barricades.windows:
		all_full = all_full and b.planks() == 6
	at.check(all_full, "repair_all_barricades() reconstruit toutes les fenêtres")
	await _view(true)
	await seconds(0.5)
	await at.screenshot("carpenter")
