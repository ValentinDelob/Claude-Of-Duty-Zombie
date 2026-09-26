extends TestCase
## Règles des bonus (PowerupRules) : seuil x1,14, 4 par manche, sac mélangé,
## clignotement de fin de vie.


func test_first_threshold_is_2000() -> void:
	var t := PowerupRules.DropTracker.new()
	t.on_team_total(2000)
	assert_false(t.drop_pending, "2000 pile ne suffit pas (strictement supérieur)")
	t.on_team_total(2010)
	assert_true(t.drop_pending, "seuil de 2000 franchi")
	assert_near(t.increment, 2280.0, 0.01, "incrément x1,14")
	assert_near(t.score_to_drop, 2010.0 + 2280.0, 0.01, "prochain seuil = total + incrément")


func test_increment_grows_by_1_14() -> void:
	var t := PowerupRules.DropTracker.new()
	var total := 0.0
	var expected := 2000.0
	for k in 5:
		total = t.score_to_drop + 10.0
		t.on_team_total(total)
		expected *= 1.14
		assert_near(t.increment, expected, 0.01, "incrément n°%d" % (k + 1))
		assert_true(t.try_drop(99, true), "bonus dû au kill suivant (%d)" % k)
		t.new_round()


func test_drop_needs_threshold_or_random_roll() -> void:
	var t := PowerupRules.DropTracker.new()
	assert_false(t.try_drop(50, true), "ni seuil ni tirage")
	assert_false(t.try_drop(3, true), "3 > 2 : pas de tirage")
	assert_true(t.try_drop(2, true), "tirage aléatoire (0..2 sur 100)")
	assert_eq(t.drops_this_round, 1)


func test_max_four_per_round() -> void:
	var t := PowerupRules.DropTracker.new()
	var n := 0
	for i in 20:
		if t.try_drop(0, true):
			n += 1
	assert_eq(n, 4, "au plus 4 bonus par manche")
	t.on_team_total(1000000)
	assert_false(t.try_drop(0, true), "même avec le seuil franchi")
	t.new_round()
	assert_true(t.try_drop(99, true), "nouvelle manche : le bonus dû tombe")


func test_pending_drop_waits_for_playable_area() -> void:
	var t := PowerupRules.DropTracker.new()
	t.on_team_total(2500)
	assert_false(t.try_drop(99, false), "hors zone jouable : rien")
	assert_true(t.drop_pending, "le bonus reste dû")
	assert_true(t.try_drop(99, true), "tombe au kill suivant en zone jouable")
	assert_false(t.drop_pending)


func test_bag_plays_each_powerup_once_per_cycle() -> void:
	var bag := PowerupRules.Bag.new(PowerupRules.ALL, 42)
	for cycle in 3:
		var seen := {}
		for i in PowerupRules.ALL.size():
			seen[bag.next_item()] = true
		assert_eq(seen.size(), PowerupRules.ALL.size(), "cycle %d : chaque bonus une fois" % cycle)


func test_bag_is_shuffled() -> void:
	# Sur plusieurs graines, l'ordre ne doit pas toujours être celui déclaré.
	var different := 0
	for sd in 10:
		var bag := PowerupRules.Bag.new(PowerupRules.ALL, sd)
		if bag.items != PowerupRules.ALL:
			different += 1
	assert_true(different >= 8, "ordre mélangé (%d/10)" % different)


func test_bag_skips_invalid_powerups() -> void:
	var bag := PowerupRules.Bag.new(PowerupRules.ALL, 7)
	var no_fire_sale := func(t: String) -> bool: return t != PowerupRules.FIRE_SALE
	for i in 30:
		assert_true(bag.next_valid(no_fire_sale) != PowerupRules.FIRE_SALE, "liquidation exclue")
	var none := func(_t: String) -> bool: return false
	assert_eq(bag.next_valid(none), "", "aucun bonus valide")


func test_drop_lifetime_and_blink() -> void:
	assert_near(PowerupRules.lifetime(), 26.5, 0.001, "15 s + 40 alternances")
	assert_true(PowerupRules.drop_visible(0.0))
	assert_true(PowerupRules.drop_visible(14.9))
	assert_false(PowerupRules.drop_visible(15.2), "première alternance : caché")
	assert_true(PowerupRules.drop_visible(15.7), "seconde : visible")
	assert_false(PowerupRules.drop_visible(27.0), "disparu")
	# Le clignotement accélère : plus de changements dans la dernière seconde.
	var changes_early := 0
	var changes_late := 0
	var prev := PowerupRules.drop_visible(15.0)
	for i in range(1, 100):
		var v := PowerupRules.drop_visible(15.0 + i * 0.02)
		if v != prev:
			changes_early += 1
		prev = v
	prev = PowerupRules.drop_visible(24.5)
	for i in range(1, 100):
		var v := PowerupRules.drop_visible(24.5 + i * 0.02)
		if v != prev:
			changes_late += 1
		prev = v
	assert_true(changes_late > changes_early * 2, "clignotement plus rapide à la fin (%d vs %d)" % [changes_late, changes_early])


func test_timed_powerups() -> void:
	assert_true(PowerupRules.is_timed(PowerupRules.INSTA_KILL))
	assert_true(PowerupRules.is_timed(PowerupRules.DOUBLE_POINTS))
	assert_true(PowerupRules.is_timed(PowerupRules.FIRE_SALE))
	assert_false(PowerupRules.is_timed(PowerupRules.NUKE))
	assert_true(PowerupRules.hud_icon_visible(20.0))
	var hidden := 0
	for i in 50:
		if not PowerupRules.hud_icon_visible(4.0 - i * 0.05):
			hidden += 1
	assert_true(hidden > 10, "l'icône clignote dans les dernières secondes")
