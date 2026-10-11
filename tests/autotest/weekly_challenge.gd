extends AutotestScenario
## Défi hebdomadaire en partie (GAME_CONCEPT §4.18) : partie solo lancée avec
## une clé de semaine (comme le bouton LANCER LE DÉFI) dont les modificateurs
## sont connus (« Peau de cuir » et « En retard » cherchés parmi les
## semaines) : armes de base imposées malgré la sélection du profil, première
## manche 6, PV des zombies relevés, pas de message de contrat ; évacuation à
## la manche visée -> récompense de la semaine au profil (XP + échantillons,
## une fois), butin de la partie NON gardé, rapport « DÉFI … RÉUSSI ».

var H := AutotestHelpers


## Semaine dont le défi porte les deux modificateurs voulus.
func _find_key(want: Array) -> WeeklyChallenge:
	for y in [2026, 2027, 2028]:
		for w in range(1, WeeklyChallenge.weeks_in(y) + 1):
			var c := WeeklyChallenge.for_week(y, w)
			if c == null:
				continue
			var ok := true
			for id in want:
				ok = ok and c.has_mod(id)
			if ok:
				return c
	return null


func run() -> void:
	timeout_sec = 150
	ProfileStore.reset()
	var ch := _find_key(["tough_zombies", "late_start"])
	at.check(ch != null, "une semaine avec « Peau de cuir » et « En retard »")
	if ch == null:
		return
	print("[weekly] défi %s : %s" % [ch.key, ch.map_id])
	# Profil : une arme d'arsenal et la batte seule au départ (ignorées par le défi).
	var pr0 := PlayerProfile.new()
	pr0.add_weapon(OwnedWeapon.create("galil", 1, OwnedWeapon.Rarity.RARE))
	pr0.set_starting_weapons(["bat"])
	ProfileStore.save_profile(pr0)

	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	Router.start_solo(ch.map_id, ch.key)
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "joueur local en jeu")
	if not ok:
		return
	var game := Game.instance
	game.local_player.bot_controlled = true
	game.combat.debug_invulnerable = true
	at.check(game.challenge != null and game.challenge.key == ch.key, "défi chargé : %s" % ch.key)
	at.check(game.contract_watch == null, "pas de message de contrat pendant le défi")
	at.check((game.station != null) == ch.has_station(), "station selon le défi")
	var pd := game.session.local_data()
	var ids := []
	for w in pd.weapons:
		ids.append(String(w.id))
	at.check(ids == Array(WeeklyChallenge.starting_ids()), "armes de base pour tous : %s" % str(ids))

	# Première manche : 6 (« En retard »), zombies plus résistants.
	ok = await until(func(): return game.rounds.round_n >= 6 and game.rounds.phase == RoundManager.Phase.ACTIVE, 20.0, "première manche")
	if not ok:
		return
	at.check(game.rounds.round_n == ch.start_round(), "première manche : %d" % game.rounds.round_n)
	ok = await until(func(): return game.zombies.alive_count() > 0, 20.0, "un zombie apparaît")
	if not ok:
		return
	var z: Zombie = game.zombies.alive[0]
	var want := ch.zombie_health(RoundRules.zombie_health(game.rounds.round_n))
	at.check(z.max_health == want and want > RoundRules.zombie_health(game.rounds.round_n), "PV relevés : %d (attendu %d)" % [z.max_health, want])

	# Butin de la partie (arme dans l'inventaire), puis évacuation à la manche visée.
	game.session.give_to_bag(1, GameWeapon.make("mp40", 4, 1, [], "loot:99"))
	game.rounds.paused = true
	game.rounds.debug_jump_to(ch.goal_round)
	await frames(2)
	game.srv_end_match(true)
	ok = await until(func(): return game.last_result != null, 5.0, "fin de partie")
	if not ok:
		return
	var r := game.last_result
	var pr := ProfileStore.load_profile()
	at.check(pr.weekly.is_rewarded(ch.key), "récompense de la semaine donnée")
	at.check(pr.weekly.entry(ch.key).evac == ch.goal_round, "meilleur résultat : évacuation manche %d" % ch.goal_round)
	for k in ch.reward_samples:
		at.check(pr.sample_count(k) == int(ch.reward_samples[k]), "échantillons de la récompense : %s" % k)
	at.check(pr.weapons.size() == 1 and pr.versions_of("mp40").is_empty(), "butin de la partie non gardé")
	var wxp := int((r.loot.get("challenge", {}) as Dictionary).get("xp", 0))
	at.check(wxp > 0 and pr.xp == r.xp + wxp, "XP de la partie (%d) + XP du défi (%d) = %d" % [r.xp, wxp, pr.xp])
	at.check(game.hud.loot_report().begins_with(Lang.t("DÉFI S%d RÉUSSI", "W%d CHALLENGE COMPLETE") % ch.week), "rapport : « %s »" % game.hud.loot_report())
	await at.screenshot("report")
	ProfileStore.reset()
