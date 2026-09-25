extends AutotestScenario
## Arme de base : tir, munitions (client ET serveur), rechargement, cadence
## validée par le serveur, impacts, visée.

var p: Player


func shoot_once() -> void:
	p.input.fire = true
	await seconds(0.03)
	p.input.fire = false
	await seconds(60.0 / 420.0 + 0.02)


func run() -> void:
	p = await AutotestHelpers.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	var wc := p.weapons
	var pd := game.session.local_data()
	at.check(wc != null and wc.current().id == "pistol", "arme de départ : pistolet")
	at.check(pd.current_weapon().mag == 8 and pd.current_weapon().reserve == 64, "munitions serveur initiales 8/64")

	# Face à un mur, à 4 m.
	p.teleport_to(MapData.cell_to_world(Vector2i(5, 7), 0.05), PI * 0.5)  # regarde vers -X
	p.pitch = 0.0
	await seconds(0.8)
	var holes_before: int = game.fx_root._hole_i
	var validated := [0]
	game.combat.shot_validated.connect(func(_pid): validated[0] += 1)
	for i in 3:
		await shoot_once()
	at.check(wc.current().mag == 5, "munitions prédites après 3 tirs (%d)" % wc.current().mag)
	at.check(pd.current_weapon().mag == 5, "munitions serveur après 3 tirs (%d)" % pd.current_weapon().mag)
	at.check(validated[0] == 3, "3 tirs validés par le serveur")
	at.check(game.fx_root._hole_i != holes_before, "impacts posés sur le mur")
	p.input.fire = true
	await seconds(0.02)
	await at.screenshot("fire")
	p.input.fire = false
	await seconds(0.3)

	# Vide le chargeur -> rechargement automatique.
	for i in 6:
		await shoot_once()
	at.check(wc.is_reloading(), "rechargement automatique quand le chargeur est vide")
	await seconds(1.7)
	at.check(wc.current().mag == 8 and wc.current().reserve == 56, "après rechargement (client) : %d/%d" % [wc.current().mag, wc.current().reserve])
	at.check(pd.current_weapon().mag == 8 and pd.current_weapon().reserve == 56, "après rechargement (serveur) : %d/%d" % [pd.current_weapon().mag, pd.current_weapon().reserve])

	# Rechargement manuel partiel.
	await shoot_once()
	await shoot_once()
	p.input.reload = true
	await seconds(1.8)
	at.check(pd.current_weapon().mag == 8 and pd.current_weapon().reserve == 54, "rechargement manuel (serveur) : %d/%d" % [pd.current_weapon().mag, pd.current_weapon().reserve])

	# Triche : 12 tirs envoyés d'un coup -> le serveur doit en refuser.
	var rejected := [0]
	game.combat.shot_rejected.connect(func(_pid, _r): rejected[0] += 1)
	for i in 12:
		game.combat.srv_fire.rpc_id(1, 0, p.camera.global_position, p.aim_direction(), PackedVector3Array(), [])
	at.check(rejected[0] >= 4, "cadence abusive refusée par le serveur (%d refus)" % rejected[0])
	await seconds(0.3)
	at.check(wc.current().mag == pd.current_weapon().mag, "prédiction resynchronisée (%d/%d)" % [wc.current().mag, pd.current_weapon().mag])

	# Visée
	p.input.aim = true
	await seconds(0.5)
	await at.screenshot("ads")
	p.input.aim = false
	await seconds(0.3)
	at.begin_perf()
	p.input.fire = true
	for i in 30:
		p.input.fire = not p.input.fire
		await seconds(0.07)
	p.input.fire = false
	at.end_perf("tir continu")
