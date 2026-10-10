extends AutotestScenario
## XP de partie (GAME_CONCEPT §4.15, docs/XP_RULES.md) dans le vrai jeu :
## éliminations comptées par type (marcheur, sprinteur, rampant, chien) et
## selon la manche, « +N XP » et compteur discrets au HUD, manche survécue
## comptée à sa fin ; défaite : l'XP est gardée (sans bonus d'évacuation),
## ajoutée UNE fois au profil, rapport de l'écran de fin (détail, niveau,
## barre de progression).

var H := AutotestHelpers


func _kill(game: Game, z: Zombie) -> void:
	game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)


func run() -> void:
	timeout_sec = 90
	ProfileStore.reset()
	# Profil juste sous le niveau 2 : la partie fait monter d'un niveau.
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(2) - 20
	ProfileStore.save_profile(pr)
	var p := await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	# Aucune vague spéciale prévue : la manche 10 reste normale.
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	var xp := game.xp
	var zm := game.zombies
	var front := p.global_position + Vector3(0, 0, -4)

	# 1. Marcheur, manche 1 : +4 XP, au HUD.
	var walker := await H.dummy_zombie(self, front)
	_kill(game, walker)
	var ok: bool = await until(func(): return XpRules.total(xp.my_ledger) == XpRules.kill_xp(XpRules.WALKER, 1), 2.0, "XP du marcheur")
	at.check(ok and int(xp.my_ledger.kills.get(XpRules.WALKER, 0)) == 1, "marcheur compté (%s)" % xp.my_ledger)
	at.check(xp.pop_shown() == XpSystem.pop_text(4), "« +4 XP » sous le viseur : « %s »" % xp.pop_shown())
	at.check(xp.counter_shown() == XpSystem.counter_text(4), "compteur de partie : « %s »" % xp.counter_shown())
	await at.screenshot("xp_pop")

	# 2. Manche 10 : sprinteur, rampant et chien, bonus de manche.
	game.rounds.debug_jump_to(10)
	await H.clear_zombies(self)
	var zid := zm.spawn(front, RoundRules.SPRINT, 150)
	var sprinter := zm.get_zombie(zid)
	sprinter.speed_mult = 0.0
	await H.emerged(self, [sprinter])
	_kill(game, sprinter)
	var crawler := await H.dummy_zombie(self, front + Vector3(1, 0, 0))
	crawler.crawl_t = 0.0  # jambes arrachées (ZombieGibs) : rampant
	_kill(game, crawler)
	var dog_id := zm.spawn(front + Vector3(-1, 0, 0), 3, 400, ZombieManager.KIND_DOG)
	_kill(game, zm.get_zombie(dog_id))
	var want := XpRules.kill_xp(XpRules.WALKER, 1) + XpRules.kill_xp(XpRules.SPRINTER, 10) \
			+ XpRules.kill_xp(XpRules.CRAWLER, 10) + XpRules.kill_xp(XpRules.DOG, 10)
	ok = await until(func(): return XpRules.total(xp.my_ledger) == want, 2.0, "XP des trois éliminations")
	at.check(ok, "sprinteur, rampant et chien à la manche 10 : %d XP (%s)" % [XpRules.total(xp.my_ledger), xp.my_ledger.kill_xp])
	for t in [XpRules.SPRINTER, XpRules.CRAWLER, XpRules.DOG]:
		at.check(int(xp.my_ledger.kills.get(t, 0)) == 1, "type compté : %s" % t)
	at.check(XpRules.kill_xp(XpRules.SPRINTER, 10) > XpRules.kill_xp(XpRules.WALKER, 1), "plus loin, plus d'XP")

	# 3. Fin de la manche 10 : manche survécue.
	await H.clear_zombies(self)
	game.rounds.to_spawn = 0
	game.rounds.paused = false
	ok = await until(func(): return int(xp.my_ledger.rounds) == 1, 3.0, "manche survécue comptée")
	at.check(ok and int(xp.my_ledger.round_xp) == XpRules.round_xp(10), "manche 10 survécue : +%d XP" % xp.my_ledger.round_xp)
	game.rounds.paused = true
	want += XpRules.round_xp(10)

	# 4. Défaite : l'XP est gardée, une seule fois, sans bonus d'évacuation.
	game.combat.debug_invulnerable = false
	game.combat.damage_player(1, 500, p.global_position)
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 5.0, "GAME OVER")
	if not ok:
		return
	var r := game.last_result
	at.check(not r.evacuated and r.xp == want and int(r.xp_ledger.evac_bonus) == 0, "défaite : %d XP gardée, pas de bonus" % r.xp)
	var saved := ProfileStore.load_profile().xp
	at.check(saved == pr.xp + want and r.profile_xp == saved, "profil : %d XP (avant %d)" % [saved, pr.xp])
	at.check(r.level_before == 1 and r.level_after == 2, "niveau 1 -> 2 (%d -> %d)" % [r.level_before, r.level_after])
	var shown := game.hud.xp_report_text()
	at.check(shown.contains(r.xp_title()) and shown.contains(r.xp_level_text()) and shown.contains(r.xp_progress_text()),
			"rapport d'XP à l'écran : %s" % shown)
	at.check(shown.contains(Lang.t("Sprinteurs", "Sprinters")) and shown.contains(Lang.t("Rampants", "Crawlers"))
			and shown.contains(Lang.t("Chiens", "Dogs")), "détail par type à l'écran")
	at.check(game.hud._xp_bar.visible and game.hud._xp_bar.value == r.xp_progress().x, "barre vers le niveau 3")
	at.check(xp.counter_shown() == "" and xp.pop_shown() == "", "compteur de partie masqué à la fin")
	# Une seule application : un départ ou une seconde fin ne rajoute rien.
	game.keep_match_xp()
	at.check(game._record_xp(r.xp_ledger).is_empty(), "seconde application refusée")
	at.check(ProfileStore.load_profile().xp == saved, "XP ajoutée une seule fois")
	await at.screenshot("xp_report")
	ProfileStore.reset()
