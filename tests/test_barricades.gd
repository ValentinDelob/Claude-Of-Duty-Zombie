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
	# Ancien test : « les coureurs arrachent plus vite » (1,5 s contre 1,9 s).
	# Règle demandée par le joueur : une planche toutes les 2,5 s en moyenne
	# pour tout zombie (l'animation d'arrachage de BO1 ne dépend pas de la
	# vitesse de course).
	assert_near(BarricadeRules.tear_interval(3), BarricadeRules.tear_interval(0), 0.0001, "même cadence pour coureurs et marcheurs")
	assert_near(BarricadeRules.tear_interval(0), 2.5, 0.0001, "2,5 s par planche en moyenne")
	assert_true(BarricadeRules.tear_interval(0) * BarricadeRules.PLANKS >= 10.0, "BO1 : une dizaine de secondes pour ouvrir une fenêtre")


## Cycle d'un zombie à sa place, simulé image par image (60 i/s) : une
## planche toutes les 2,5 s en moyenne, écart ±0,3 s, pause de folie d'au
## moins 0,9 s entre deux planches, la planche cède pendant le geste.
func test_tear_cycle_timing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dt := 1.0 / 60.0
	var frenzy := false
	var t := 0.0
	var pause := 0.0
	var now := 0.0
	var rips: Array[float] = []
	var frenzy_since_rip := 0.0
	var min_frenzy := INF
	var torn_in_frenzy := false
	while rips.size() < 200:
		var st := BarricadeRules.tear_tick(frenzy, t, pause, dt, rng.randf())
		now += dt
		if st.w > 0.5:
			torn_in_frenzy = torn_in_frenzy or frenzy
			if not rips.is_empty():
				min_frenzy = minf(min_frenzy, frenzy_since_rip)
			rips.append(now)
			frenzy_since_rip = 0.0
		frenzy = st.x > 0.5
		t = st.y
		pause = st.z
		if frenzy:
			frenzy_since_rip += dt
	assert_near(rips[0], BarricadeRules.TEAR_PULL * BarricadeRules.TEAR_RIP, 0.02, "première planche : pendant le premier geste (%.2f s)" % rips[0])
	var lo := INF
	var hi := 0.0
	for i in range(1, rips.size()):
		lo = minf(lo, rips[i] - rips[i - 1])
		hi = maxf(hi, rips[i] - rips[i - 1])
	var mean := (rips[rips.size() - 1] - rips[0]) / (rips.size() - 1)
	assert_near(mean, 2.5, 0.05, "2,5 s par planche en moyenne (%.3f s)" % mean)
	assert_true(lo >= 2.2 - dt and hi <= 2.8 + dt, "écart ±0,3 s (%.2f à %.2f s)" % [lo, hi])
	assert_true(hi - lo > 0.3, "pas toujours la même durée : les zombies ne sont pas en cadence")
	assert_true(min_frenzy >= BarricadeRules.TEAR_PAUSE_MIN - dt, "pause de folie d'au moins %.1f s entre deux planches (%.2f s)" % [BarricadeRules.TEAR_PAUSE_MIN, min_frenzy])
	assert_false(torn_in_frenzy, "la planche cède pendant le geste, jamais pendant la pause")


## Une pause très longue (attente à une fenêtre ouverte) ne fait pas sauter
## de planche une fois la fenêtre réparée : le geste suivant repart de zéro.
func test_tear_cycle_after_long_wait() -> void:
	var st := BarricadeRules.tear_tick(true, 30.0, 0.0, 1.0 / 60.0, 0.5)
	assert_eq(st.x, 0.0, "fin de la pause")
	assert_true(st.y <= 1.0 / 60.0 + 0.0001, "geste repris au début (%.3f s)" % st.y)


## BO1 (attack_spots) : 3 places par fenêtre, au plus 3 zombies qui attendent.
func test_window_queue_cap() -> void:
	assert_eq(BarricadeRules.WINDOW_QUEUE_MAX, 3)
	assert_eq(Barricade.SLOT_OFFSETS.size(), BarricadeRules.WINDOW_QUEUE_MAX, "une place par zombie qui attend")
	assert_false(BarricadeRules.queue_full(0))
	assert_false(BarricadeRules.queue_full(2))
	assert_true(BarricadeRules.queue_full(3), "3 zombies : file pleine")
	assert_true(BarricadeRules.queue_full(4))
	# Places côte à côte sans que les capsules se touchent.
	for i in Barricade.SLOT_OFFSETS.size():
		for j in range(i + 1, Barricade.SLOT_OFFSETS.size()):
			assert_true(absf(Barricade.SLOT_OFFSETS[i] - Barricade.SLOT_OFFSETS[j]) >= 2.0 * Zombie.RADIUS, "places %d et %d écartées" % [i, j])


## Pose de folie : valeurs finies, bras levés puis abattus (les coups), et
## deux zombies de phases différentes ne bougent pas ensemble.
func test_frenzy_pose() -> void:
	var a := []
	a.resize(ZombieAnim.FRENZY_VALUES)
	var b := a.duplicate()
	var arm_lo := INF
	var arm_hi := -INF
	var differ := false
	for i in 120:
		var t := i / 60.0
		ZombieAnim.frenzy_pose(a, t, 0.0, 0.1, 0.3)
		ZombieAnim.frenzy_pose(b, t, 2.0, 0.1, 0.3)
		for v in a:
			assert_true(is_finite(v) and absf(v) < 3.2, "angle fini et raisonnable (%s)" % str(v))
		arm_lo = minf(arm_lo, a[0])
		arm_hi = maxf(arm_hi, a[0])
		differ = differ or absf(a[0] - b[0]) > 0.3
	assert_true(arm_hi < -1.2 and arm_lo < -2.2, "bras levé au-dessus de la tête puis abattu vers les planches (%.2f à %.2f)" % [arm_lo, arm_hi])
	assert_true(differ, "phase propre à chaque zombie")


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
