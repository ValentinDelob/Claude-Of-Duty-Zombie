extends TestCase
## Fenêtres barricadées : règles de points de réparation et disposition sur la carte.


func test_repair_points_and_round_cap() -> void:
	assert_eq(BarricadeRules.repair_points(0), 10, "+10 par planche")
	assert_eq(BarricadeRules.repair_points(0, 2), 20, "double points")
	assert_eq(BarricadeRules.repair_points(490), 10)
	assert_eq(BarricadeRules.repair_points(495), 5, "le plafond tronque le dernier gain")
	assert_eq(BarricadeRules.repair_points(490, 2), 10, "double points tronqué au plafond")
	assert_eq(BarricadeRules.repair_points(500), 0, "plafond de 500 points par manche")
	assert_eq(BarricadeRules.repair_points(620), 0)
	# 50 planches rapportent exactement le plafond, pas plus.
	var earned := 0
	for i in 60:
		earned += BarricadeRules.repair_points(earned)
	assert_eq(earned, BarricadeRules.ROUND_CAP)


func test_repair_speed() -> void:
	assert_near(BarricadeRules.repair_interval(1.0), BarricadeRules.REPAIR_TIME)
	assert_near(BarricadeRules.repair_interval(0.5), BarricadeRules.REPAIR_TIME * 0.5, 0.001, "RAPID FIZZ : 2x plus vite")
	assert_true(BarricadeRules.tear_interval(3) < BarricadeRules.tear_interval(0), "les coureurs arrachent plus vite")
	assert_true(BarricadeRules.tear_interval(0) * BarricadeRules.PLANKS >= 10.0, "BO1 : une dizaine de secondes pour ouvrir une fenêtre")


func test_plank_order() -> void:
	var m := BarricadeRules.FULL_MASK
	assert_eq(BarricadeRules.PLANKS, 6)
	assert_eq(BarricadeRules.count(m), 6)
	assert_eq(BarricadeRules.plank_to_repair(m), -1, "fenêtre complète")
	var i := BarricadeRules.plank_to_tear(m)
	assert_eq(i, 5)
	m &= ~(1 << i)
	assert_eq(BarricadeRules.count(m), 5)
	assert_eq(BarricadeRules.plank_to_repair(m), 5)
	assert_eq(BarricadeRules.plank_to_tear(0), -1, "plus rien à arracher")
	assert_eq(BarricadeRules.plank_to_repair(0), 0)


func test_bunker_windows() -> void:
	var def: MapDef = load("res://scripts/game/map/maps/bunker_k7.gd").new()
	var data := MapData.parse(def.rows)
	var windows := BarricadeLayout.analyze(data)
	assert_eq(windows.size(), data.markers.get("W", []).size(), "toutes les fenêtres sont valides")
	var per_zone := {}
	for w: BarricadeLayout.Opening in windows:
		per_zone[w.zone] = per_zone.get(w.zone, 0) + 1
		assert_true(w.spawns.size() >= 1, "fenêtre %s : une apparition dans sa poche" % w.cell)
		assert_true(data.is_floor(w.cell + w.inward) and data.is_floor(w.cell - w.inward), "fenêtre %s entre deux sols" % w.cell)
		assert_true(w.pocket.size() <= BarricadeLayout.POCKET_MAX, "poche fermée")
		for c in w.pocket:
			assert_eq(data.zone_at(c), w.zone, "poche %s dans la zone de sa fenêtre" % c)
	assert_true(per_zone.get("a", 0) >= 3, "au moins 3 fenêtres dans la salle de départ (%d)" % per_zone.get("a", 0))
	for z in ["a", "b", "c", "d", "e", "f"]:
		assert_true(per_zone.get(z, 0) >= 1, "zone %s : au moins une fenêtre" % z)
	assert_eq(per_zone.get("p", 0), 0, "pas de fenêtre dans la salle du rituel")


func test_pockets_only_reachable_through_windows() -> void:
	var def: MapDef = load("res://scripts/game/map/maps/bunker_k7.gd").new()
	var data := MapData.parse(def.rows)
	var nav := NavGrid.new(data)
	nav.set_blocked(MapDef.blocking_cells(data, def), true)
	var windows := BarricadeLayout.analyze(data)
	# Toutes portes ouvertes : aucune poche n'est accessible à pied (fenêtres bloquées).
	var doors := []
	for id in def.doors:
		doors.append_array(data.markers.get(id, []))
	nav.set_blocked(doors, false)
	var start := MapData.cell_to_world(data.markers["P"][0])
	for w: BarricadeLayout.Opening in windows:
		var sp := MapData.cell_to_world(w.spawns[0])
		assert_true(nav.find_path(start, sp).is_empty(), "poche de la fenêtre %s isolée" % w.cell)
		assert_false(nav.find_path(start, MapData.cell_to_world(w.cell + w.inward)).is_empty(), "intérieur de la fenêtre %s accessible" % w.cell)
