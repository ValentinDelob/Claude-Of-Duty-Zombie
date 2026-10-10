extends AutotestScenario
## Station de construction, partie perdue (GAME_CONCEPT §4.6, §4.11) : une
## arme de l'arsenal construite, récupérée puis améliorée en partie ; toute
## l'équipe meurt : la version de l'arsenal reste dans le profil, INCHANGÉE,
## et rien n'est ajouté (l'XP, elle, est gardée).

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(4))
	var uid := pr.add_weapon(OwnedWeapon.create("mp40", 3, OwnedWeapon.Rarity.RARE))
	ProfileStore.save_profile(pr)
	var p: Player = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var pd := game.session.local_data()
	var st := game.station
	if st == null:
		at.check(false, "station de construction construite")
		return
	game.session.add_points(1, 2000)
	p.teleport_to(st.global_position + st.global_basis.z * 1.7 + Vector3.UP * 0.05)
	await frames(3)
	st.srv_build.rpc_id(1, GameWeapon.from_owned(pr.get_weapon(uid)))
	await until(func(): return st.builds.has(1), 2.0, "construction lancée")
	var n := int(st.builds[1]["round"])
	game.rounds.debug_jump_to(n)
	game.rounds._end_round()
	await until(func(): return bool(st.builds[1].ready), 2.0, "prête")
	st.srv_use(1)
	await until(func(): return pd.bag.size() == 1, 2.0, "récupérée")
	at.check(String(pd.bag[0].uid) == uid, "exemplaire de l'arsenal dans l'inventaire")
	# Amélioration en partie, puis toute l'équipe meurt.
	pd.bag[0].level = 5
	pd.bag.append(GameWeapon.make("m14", 6, OwnedWeapon.Rarity.EPIC, [], "loot:6"))
	game.session.sync_inventory(1)
	await frames(2)
	game.srv_end_match(false)
	var ok: bool = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 2.0, "fin de partie")
	if not ok:
		return
	at.check(not game.last_result.evacuated, "toute l'équipe morte")
	var after := ProfileStore.load_profile()
	var v := after.get_weapon(uid)
	at.check(v != null and v.level == 3 and v.rarity == OwnedWeapon.Rarity.RARE, "version de l'arsenal gardée et inchangée (niveau %d)" % (v.level if v else -1))
	at.check(after.weapons.size() == 1, "aucune arme ajoutée (%d)" % after.weapons.size())
	at.check(after.xp >= PlayerProfile.xp_for_level(4), "XP gardée")
	ProfileStore.reset()
