extends TestCase
## Règles pures d'une partie (MatchRules) : fin de partie solo / coop,
## saignement, réapparition, point d'apparition par place.


func _pd(id: int, life: PlayerData.Life) -> PlayerData:
	var pd := PlayerData.new(id)
	pd.life = life
	return pd


func _never(_pid: int) -> bool:
	return false


func test_solo_alive_is_not_over() -> void:
	assert_false(MatchRules.is_game_over([_pd(1, PlayerData.Life.ALIVE)], _never))


func test_solo_downed_without_self_revive_is_over() -> void:
	assert_true(MatchRules.is_game_over([_pd(1, PlayerData.Life.DOWNED)], _never),
			"solo à terre sans LAZARUS : fin de partie")


func test_solo_downed_with_self_revive_is_not_over() -> void:
	var lazarus := func(pid: int) -> bool: return pid == 1
	assert_false(MatchRules.is_game_over([_pd(1, PlayerData.Life.DOWNED)], lazarus),
			"auto-réanimation programmée : la partie continue")


func test_coop_one_standing_is_not_over() -> void:
	var data := [_pd(1, PlayerData.Life.DEAD), _pd(2, PlayerData.Life.DOWNED), _pd(3, PlayerData.Life.ALIVE)]
	assert_false(MatchRules.is_game_over(data, _never))


func test_coop_everyone_dead_or_downed_is_over() -> void:
	var data := [_pd(1, PlayerData.Life.DEAD), _pd(2, PlayerData.Life.DOWNED)]
	assert_true(MatchRules.is_game_over(data, _never), "plus personne debout : GAME OVER")


func test_no_player_is_over() -> void:
	assert_true(MatchRules.is_game_over([], _never), "dernier joueur parti")


func test_bleed_out_ends_solo_and_coop() -> void:
	var a := _pd(1, PlayerData.Life.DOWNED)
	MatchRules.bleed_out(a)
	assert_eq(a.life, PlayerData.Life.DEAD)
	assert_true(MatchRules.is_game_over([a], _never))
	var b := _pd(2, PlayerData.Life.ALIVE)
	assert_false(MatchRules.is_game_over([a, b], _never), "un coéquipier debout : on continue")


func test_total_kills() -> void:
	var a := _pd(1, PlayerData.Life.DEAD)
	a.kills = 12
	var b := _pd(2, PlayerData.Life.DEAD)
	b.kills = 30
	assert_eq(MatchRules.total_kills([a, b]), 42)
	assert_eq(MatchRules.total_kills([]), 0)


func test_only_dead_players_respawn() -> void:
	assert_true(MatchRules.should_respawn(_pd(1, PlayerData.Life.DEAD)))
	assert_false(MatchRules.should_respawn(_pd(1, PlayerData.Life.DOWNED)), "à terre : pas de réapparition")
	assert_false(MatchRules.should_respawn(_pd(1, PlayerData.Life.ALIVE)))


func test_respawn_keeps_everything() -> void:
	# Mort après être tombé à terre : les armes mises de côté reviennent
	# (GAME_CONCEPT §4.6), avec leurs munitions.
	var pd := _pd(1, PlayerData.Life.DEAD)
	pd.points = 4321
	pd.kills = 7
	pd.max_health = 250
	pd.health = 0
	pd.grenades = 3
	pd.monkeys = 2
	var mp40 := WeaponDB.new_instance("mp40")
	mp40.mag = 5
	mp40.reserve = 17
	pd.saved_weapons = [mp40, WeaponDB.new_instance("ray")]
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]  # pistolet prêté à terre
	pd.slot = 1
	pd.knife = "bowie"
	MatchRules.respawn(pd)
	assert_eq(pd.life, PlayerData.Life.ALIVE)
	assert_eq(pd.health, 250, "santé pleine")
	assert_eq(pd.weapons.size(), 2, "armes d'avant la mort")
	assert_eq(pd.weapons[0].id, "mp40")
	assert_eq(pd.weapons[0].mag, 5, "munitions gardées")
	assert_eq(pd.weapons[0].reserve, 17)
	assert_eq(pd.weapons[1].id, "ray")
	assert_true(pd.saved_weapons.is_empty())
	assert_eq(pd.slot, 1)
	assert_eq(pd.knife, "bowie", "couteau gardé")
	assert_eq(pd.grenades, 3, "grenades gardées")
	assert_eq(pd.monkeys, 2)
	assert_eq(pd.points, 4321, "ferraille gardée")
	assert_eq(pd.kills, 7)


func test_respawn_without_saved_weapons_keeps_inventory() -> void:
	# Mort sans passer à terre : l'inventaire actuel reste ; vide : pistolet.
	var pd := _pd(1, PlayerData.Life.DEAD)
	pd.weapons = [WeaponDB.new_instance("mp40")]
	MatchRules.respawn(pd)
	assert_eq(pd.weapons.size(), 1)
	assert_eq(pd.weapons[0].id, "mp40")
	var empty := _pd(2, PlayerData.Life.DEAD)
	empty.weapons = []
	MatchRules.respawn(empty)
	assert_eq(empty.weapons.size(), 1)
	assert_eq(empty.weapons[0].id, WeaponDB.STARTING_WEAPON, "inventaire vide : pistolet de départ")


func test_spawn_slots() -> void:
	var three: Array[Vector3] = [Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)]
	assert_eq(MatchRules.spawn_for_slot(three, 0), Vector3(1, 0, 0))
	assert_eq(MatchRules.spawn_for_slot(three, 2), Vector3(3, 0, 0))
	assert_eq(MatchRules.spawn_for_slot(three, 3), Vector3(1, 0, 0), "places en trop : partagées")
	assert_eq(MatchRules.spawn_for_slot(three, -1), Vector3(3, 0, 0), "modulo positif")


func test_spawn_without_spawn_points() -> void:
	var none: Array[Vector3] = []
	assert_eq(MatchRules.spawn_for_slot(none, 0), MatchRules.FALLBACK_SPAWN, "carte sans point : repli")
	assert_eq(MatchRules.spawn_for_slot(none, 5), MatchRules.FALLBACK_SPAWN)
	assert_eq(Game.spawn_for_slot(none, 1), Game.FALLBACK_SPAWN, "alias de Game")


func test_match_rounds_survived_for_xp() -> void:
	var r := MatchResult.new()
	r.round_reached = 5
	assert_eq(Game.match_rounds_survived(r), 4, "équipe morte : la manche en cours ne compte pas")
	r.evacuated = true
	assert_eq(Game.match_rounds_survived(r), 5, "évacuation : la manche vaincue compte")
	r.evacuated = false
	r.round_reached = 0
	assert_eq(Game.match_rounds_survived(r), 0)
