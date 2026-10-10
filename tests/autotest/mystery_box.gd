extends AutotestScenario
## Caisse au hasard (GAME_CONCEPT §4.12 bis) sur BUNKER K-7 : une seule
## caisse, fixe, sur le quai ; achat en ferraille, défilement, objet tiré par
## le serveur (jamais une arme), pris par l'acheteur seulement : il remplit
## l'emplacement de grenade (4) sans toucher aux armes ; objet non pris
## repris par la caisse au bout de 12 s.

var H := AutotestHelpers
var game: Game
var p: Player
var box: MysteryBox


func face_box() -> void:
	var n: Vector3 = box.spot.normal
	p.teleport_to(box.global_position - n * 1.6 + Vector3(0, 0.05, 0))
	H.aim_at(p, box.global_position + Vector3.UP * 0.8)
	await until(func(): return game.interact.focused == box and game.hud._prompt.text == box.prompt(p.peer_id), 2.0, "caisse visée")


## Appuie sur [F] et attend que la caisse change d'état. `refused` : achat
## censé être refusé (rien à attendre, attente fixe).
func press(refused := false) -> void:
	var s0 := box.state
	p.input.interact_pressed = true
	if refused:
		await seconds(0.3)  # on vérifie ensuite que rien ne s'est passé
	else:
		await until(func(): return box.state != s0, 2.0, "caisse utilisée")


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	for id in game.doors:
		game.doors[id].srv_open()
	box = game.interact.get_obj("box")
	at.check(box != null and game.layout.zone_at(box.global_position) == "f", "une caisse, sur le quai")
	var boxes := game.interact.objects.values().filter(func(o): return o is MysteryBox)
	at.check(boxes.size() == 1, "une seule caisse sur la carte (%d)" % boxes.size())
	pd.points = 500  # trop pauvre pour la caisse
	await face_box()
	at.check(game.hud._prompt.text == Lang.t("[F] Caisse [950]", "[F] Crate [950]"), "invite : %s" % game.hud._prompt.text)
	await press(true)
	at.check(box.state == MysteryBox.State.IDLE and pd.points == 500, "refus sans 950 de ferraille")

	game.session.add_points(1, 20000)
	await until(func(): return pd.points == 20500, 2.0, "ferraille créditée")
	var weapons0 := pd.weapons.duplicate(true)
	await press()
	at.check(box.state == MysteryBox.State.ROLLING and pd.points == 20500 - MysteryBox.COST, "achat : défilement en cours")
	await seconds(2.0)  # capture : au milieu du défilement
	await at.screenshot("rolling")
	await until(func(): return box.state == MysteryBox.State.READY, 4.0, "objet prêt")
	var it := ThrowableRules.crate_item(box.item)
	at.check(not it.is_empty(), "objet tiré dans la liste de la caisse : %s" % box.item)
	await seconds(0.4)  # capture : objet sorti de la caisse
	await at.screenshot("ready")
	at.check(game.hud._prompt.text.contains(MysteryBox.item_name(box.item)), "invite : %s" % game.hud._prompt.text)
	await press()
	at.check(box.state == MysteryBox.State.IDLE and pd.throwable == int(it.kind) and pd.grenades == ThrowableRules.SLOT_MAX,
		"%s pris : emplacement de grenade rempli (%d)" % [it.id, pd.grenades])
	at.check(pd.weapons == weapons0, "armes inchangées : rien n'entre dans l'arsenal")

	# Peluche leurre forcée : remplace les grenades.
	box.force_result = "decoy"
	await press()
	await until(func(): return box.state == MysteryBox.State.READY, MysteryBox.ROLL_TIME + 2.0, "peluche prête")
	await seconds(0.4)  # capture : peluche sortie de la caisse
	await at.screenshot("decoy")
	at.check(game.hud._prompt.text.contains(ThrowableRules.kind_name(ThrowableRules.Kind.DECOY)), "invite : %s" % game.hud._prompt.text)
	await press()
	at.check(pd.throwable == ThrowableRules.Kind.DECOY and pd.grenades == ThrowableRules.SLOT_MAX, "4 peluches leurres")

	# Objet laissé : la caisse le reprend, toujours au même endroit.
	var pos := box.global_position
	box.force_result = "frag"
	await press()
	await until(func(): return box.state == MysteryBox.State.READY, MysteryBox.ROLL_TIME + 2.0, "grenades prêtes")
	await until(func(): return box.state == MysteryBox.State.IDLE, MysteryBox.READY_TIME + 2.0, "objet repris")
	at.check(pd.throwable == ThrowableRules.Kind.DECOY, "objet non pris : emplacement inchangé")
	at.check(box.global_position.is_equal_approx(pos), "caisse fixe")
