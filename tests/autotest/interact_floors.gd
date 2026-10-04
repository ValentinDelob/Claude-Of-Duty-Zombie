extends AutotestScenario
## Objets utilisables seulement depuis leur étage (InteractionSystem.same_level),
## sans rendu, sur DRAFT ARENA (2 étages ; boîte sur la passerelle de
## l'étage 1, au-dessus de l'entrepôt) : chaque objet de la carte a son sol à
## l'altitude d'un étage ; boîte amenée sur la passerelle : joueur dessous,
## pas d'invite et achat refusé par le serveur (demande envoyée quand même) ;
## sur la passerelle, devant elle : invite et achat.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p := await H.start_solo_game(self, "draft_arena")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	await seconds(0.5)
	# Sol de chaque objet : 0 ou 3,5 m (étages de DRAFT ARENA).
	var bad := []
	for obj: Interactable in game.interact.objects.values():
		var ly := obj.level_y()
		if minf(absf(ly), absf(ly - 3.5)) > 0.25:
			bad.append("%s (%.2f)" % [obj.interact_id, ly])
	at.check(bad.is_empty(), "sol de chaque objet à l'altitude de son étage %s" % str(bad))
	var box: MysteryBox = game.interact.get_obj("box")
	var up := -1
	for i in box.spots.size():
		if (box.spots[i].pos as Vector3).y > 2.0:
			up = i
	at.check(up >= 0, "emplacement de boîte à l'étage 1")
	if up < 0:
		return
	box._move_to(up)
	box.broadcast_state()
	game.session.add_points(p.peer_id, 20000)
	var pd := game.session.local_data()
	var front := -(box.spots[up].normal as Vector3)
	var c := box.global_position
	# Dessous, à l'étage 0 de l'entrepôt.
	p.teleport_to(Vector3(c.x, 0.05, c.z) + front * 0.4)
	await seconds(0.4)
	H.aim_at(p, box.interact_point())
	await frames(4)
	at.check(p.global_position.y < 0.5, "joueur à l'étage 0 (y = %.2f)" % p.global_position.y)
	at.check(game.interact.focused != box, "pas d'invite sous la boîte")
	var before := pd.points
	game.interact.srv_interact.rpc_id(1, "box")
	await seconds(0.3)
	at.check(box.state == MysteryBox.State.IDLE and pd.points == before, "achat refusé par le serveur sous la boîte")
	# Sur la passerelle, devant elle.
	p.teleport_to(c + front * 1.3 + Vector3.UP * 0.05)
	await seconds(0.4)
	H.aim_at(p, box.interact_point())
	await frames(4)
	at.check(game.interact.focused == box, "invite devant la boîte, à son étage")
	game.interact.srv_interact.rpc_id(1, "box")
	await until(func(): return box.state == MysteryBox.State.ROLLING, 2.0, "achat à son étage")
	at.check(pd.points == before - MysteryBox.COST, "950 points payés à son étage")
