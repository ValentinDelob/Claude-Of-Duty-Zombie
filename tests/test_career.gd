extends TestCase

func _blank() -> Dictionary:
	var s := {}
	for f in CareerStats.FIELDS:
		s[f[0]] = 0
	return s


func test_accumulate() -> void:
	var pd := PlayerData.new()
	pd.kills = 40
	pd.headshots = 12
	pd.downs = 2
	pd.revives = 1
	pd.points = 5230
	var s := CareerStats.accumulate(_blank(), pd, 7, true, 900.0)
	assert_eq(s.games, 1)
	assert_eq(s.best_round_solo, 7)
	assert_eq(s.best_round_coop, 0)
	assert_eq(s.rounds, 6, "la manche du GAME OVER ne compte pas")
	assert_eq(s.kills, 40)
	assert_eq(s.best_score, 5230)
	pd.points = 900
	s = CareerStats.accumulate(s, pd, 3, false, 60.0)
	assert_eq(s.games, 2)
	assert_eq(s.best_round_solo, 7, "record solo conservé")
	assert_eq(s.best_round_coop, 3)
	assert_eq(s.kills, 80)
	assert_eq(s.best_score, 5230, "meilleur score conservé")
	assert_eq(s.time, 960)
	assert_eq(CareerStats.format_value("time", 3725), "1 h 02 min")
