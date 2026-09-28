extends AutotestScenario
## LIQUIDATION sur KINO (BO1) : pendant le bonus, une boîte à CHAQUE
## emplacement possible (9 à Kino), toutes à 10 points ; à la fin, les boîtes
## temporaires disparaissent (celle en cours de tirage finit d'abord, puis
## disparaît aussi), la vraie reste à 950. Captures de chaque boîte.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var pw: PowerupSystem
var box: MysteryBox


## Se place devant la boîte `b` et la regarde.
func face(b: MysteryBox) -> void:
	var n: Vector3 = b.spots[b.location].normal
	var fwd := -Vector3(n.x, 0, n.z).normalized()
	p.teleport_to(b.global_position + fwd * 1.6 + Vector3(0, 0.05, 0), atan2(fwd.x, fwd.z))
	await seconds(0.3)
	H.aim_at(p, b.global_position + Vector3.UP * 0.8)
	await seconds(0.3)


func run() -> void:
	timeout_sec = 150
	p = await H.start_solo_game(self, "kino")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	pw = game.powerups
	for id in game.doors:
		game.doors[id].srv_open()
	box = game.interact.get_obj("box")
	at.check(box != null and box.spots.size() == 9, "KINO : 9 emplacements de boîte (%d)" % (box.spots.size() if box else 0))
	box.moves = 1
	pd.points = 5000
	game.session.sync_stats(1)

	# Ramassage de la liquidation.
	await face(box)
	var id := pw.debug_drop(PowerupRules.FIRE_SALE, p.global_position)
	await until(func(): return not pw.nodes.has(id), 2.0, "liquidation ramassée")
	await seconds(0.8)
	at.check(box.fire_sale and box.cost() == 10, "vraie boîte à 10 points")
	at.check(box.fire_sale_boxes.size() == 8, "8 boîtes temporaires (%d)" % box.fire_sale_boxes.size())
	var locs := {box.location: true}
	for b: MysteryBox in box.fire_sale_boxes:
		locs[b.location] = true
	at.check(locs.size() == 9, "une boîte à chaque emplacement (%d)" % locs.size())
	var k := 0
	for b: MysteryBox in box.fire_sale_boxes:
		await face(b)
		at.check(game.hud._prompt.text.contains("[10]"), "boîte temporaire %d : invite « %s »" % [b.location, game.hud._prompt.text])
		if k < 2:
			await at.screenshot("temp_box_%d" % b.location)
		k += 1

	# Achat d'une boîte temporaire (10 points).
	var tb: MysteryBox = box.fire_sale_boxes[0]
	var tb_id := tb.interact_id
	await face(tb)
	var before := pd.points
	p.input.interact_pressed = true
	await seconds(0.4)
	at.check(tb.state == MysteryBox.State.ROLLING and before - pd.points == 10, "boîte temporaire achetée 10 points")
	await seconds(0.6)
	await at.screenshot("temp_box_rolling")

	# Fin du bonus pendant le tirage : les boîtes libres disparaissent, celle
	# en cours reste jusqu'au bout.
	pw.timers[PowerupRules.FIRE_SALE] = 0.2
	await seconds(0.5)
	at.check(not box.fire_sale and box.cost() == MysteryBox.COST, "fin : vraie boîte à 950")
	at.check(box.fire_sale_boxes.size() == 1 and box.fire_sale_boxes[0] == tb, "fin : seule la boîte en cours reste (%d)" % box.fire_sale_boxes.size())
	await until(func(): return tb.state == MysteryBox.State.READY, 6.0, "arme prête")
	var weapon := tb.weapon
	await face(tb)
	p.input.interact_pressed = true
	await seconds(0.4)
	at.check(weapon != "" and (pd.has_weapon(weapon) >= 0 or pd.has_monkeys), "arme prise dans la boîte temporaire (%s)" % weapon)
	await seconds(0.3)
	at.check(box.fire_sale_boxes.is_empty() and game.interact.get_obj(tb_id) == null, "la dernière boîte temporaire disparaît")
	# Les planches des emplacements vides sont revenues.
	var markers_ok := true
	for i in box._markers.size():
		markers_ok = markers_ok and box._markers[i].visible == (i != box.location)
	at.check(markers_ok, "emplacements vides : planches revenues")
	await face(box)
	await at.screenshot("after")
