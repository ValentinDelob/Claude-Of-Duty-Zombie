extends AutotestScenario
## Butin perdu (GAME_CONCEPT §4.6, §4.16) : vague de chiens forcée, butin
## ramassé (arme, pièce, échantillons), fenêtre d'évacuation laissée se
## fermer, puis mort de toute l'équipe -> rien n'est ajouté au profil sauf
## l'XP ; l'écran de fin dit ce qui est perdu.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	ProfileStore.reset()
	var p: Player = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	var loot := game.loot
	loot.debug_part_chance = 1.0
	loot.debug_sample_chance = 1.0
	var pd := game.session.local_data()
	game.rounds.paused = false

	# Vague de chiens forcée, vaincue.
	var ok: bool = await H.clear_dog_wave(self, 3)
	at.check(ok, "vague de chiens vaincue, arme au sol")
	if not ok:
		return
	at.check(not loot.my_samples.is_empty() and not loot.my_parts.is_empty(), "échantillons et pièce de la partie")
	# Ramassage par le serveur (comme [F]).
	var d: LootDrop = loot.drops.values()[0]
	loot.srv_pick(d, 1)
	at.check(pd.bag.size() == 1, "arme ramassée")
	# Fenêtre d'évacuation refermée sans évacuation.
	game.evac.time_left = 0.1
	await until(func(): return not game.evac.is_open, 2.0, "fenêtre fermée")

	# Mort de toute l'équipe.
	game.combat.debug_invulnerable = false
	game.kill_player(1)
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 3.0, "fin de partie")
	at.check(ok, "équipe morte : fin de partie")
	if not ok:
		return
	var r := game.last_result
	at.check(not r.evacuated and r.loot.get("kept", true) == false, "résultat : butin perdu")
	at.check(r.loot.get("weapons", []).size() == 1, "arme perdue listée")
	var pr := ProfileStore.load_profile()
	at.check(pr.weapons.is_empty() and pr.parts.is_empty() and pr.samples.is_empty(), "rien ajouté au profil (armes, pièces, échantillons)")
	at.check(pr.xp == r.xp and r.xp > 0, "XP gardée (%d)" % pr.xp)
	at.check(game.hud.loot_report().begins_with(Lang.t("BUTIN PERDU", "LOOT LOST")), "rapport : « %s »" % game.hud.loot_report())
	ProfileStore.reset()
