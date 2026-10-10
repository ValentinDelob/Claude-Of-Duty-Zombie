extends TestCase
## Fenêtres barricadées : règles de réparation et disposition sur la carte.
## Reposer une planche ne rapporte pas de ferraille (GAME_CONCEPT §4.8) :
## vérifié par le scénario tests/autotest/barricades.gd.


## BO1 : deux planches arrachées suffisent pour que le zombie passe le bras
## par le trou et attrape le joueur (porte double : planches de son battant).
func test_reach_through_after_two_planks() -> void:
	var door := BarricadeRules.full_mask_for(BarricadeRules.DOOR)
	assert_false(BarricadeRules.can_reach_through(door, 6, 1, 0), "porte intacte : pas de bras")
	door &= ~(1 << BarricadeRules.plank_to_tear(door, 6))
	assert_false(BarricadeRules.can_reach_through(door, 6, 1, 0), "une seule planche arrachée")
	door &= ~(1 << BarricadeRules.plank_to_tear(door, 6))
	assert_true(BarricadeRules.can_reach_through(door, 6, 1, 0), "deux planches arrachées : le bras passe")
	assert_true(BarricadeRules.can_reach_through(0, 6, 1, 0), "porte ouverte")
	assert_true(BarricadeRules.can_reach_through(BarricadeRules.FULL_MASK & ~0b110000, 6, 1, 0), "fenêtre : pareil")
	# Porte double : deux planches du battant gauche (paires) arrachées.
	var dbl := BarricadeRules.full_mask_for(BarricadeRules.DOUBLE_DOOR) & ~((1 << 8) | (1 << 6))
	assert_true(BarricadeRules.can_reach_through(dbl, 10, 2, 0), "battant gauche ouvert de deux planches")
	assert_false(BarricadeRules.can_reach_through(dbl, 10, 2, 1), "battant droit encore intact")


func test_repair_speed() -> void:
	assert_near(BarricadeRules.repair_interval(), BarricadeRules.REPAIR_TIME)
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


# --------------------------------------------------------------------------
# Portée de la réparation (BO1 : collé aux planches, de l'intérieur)
# --------------------------------------------------------------------------

## Entrée construite comme par BarricadeSystem, dans l'arbre de test.
func _opening(kind: String, pos: Vector3, inward: Vector3) -> Barricade:
	var o := BarricadeLayout.Opening.new()
	o.pos = pos
	o.inward_dir = inward
	o.kind = kind
	o.width = BarricadeRules.width(kind)
	o.height = 2.6
	var b := Barricade.new()
	b.setup(o)
	host.add_child(b)
	return b


## Marge réseau du serveur : proportionnelle à la vitesse et à la latence,
## nulle pour un joueur immobile, bornée (REPAIR_NET_SLACK_MAX).
func test_repair_net_slack() -> void:
	var cap := Barricade.REPAIR_NET_SLACK_MAX
	assert_eq(Player.lag_slack(0.0, 0.15, cap), 0.0, "immobile : aucune marge")
	assert_near(Player.lag_slack(4.0, 0.05, cap), 4.0 * (0.05 + 1.0 / Player.NET_SEND_RATE), 0.001, "marche : vitesse × (RTT + envoi)")
	assert_eq(Player.lag_slack(7.0, 0.5, cap), cap, "bornée")
	assert_near(Player.move_speed(Vector3.ZERO, Vector3(0.2, 5.0, 0.0), 0.05), 4.0, 0.001, "vitesse horizontale entre deux états")
	assert_eq(Player.move_speed(Vector3.ZERO, Vector3(5.0, 0, 0), 0.05), 0.0, "saut voulu : pas une vitesse")
	assert_eq(Player.move_speed(Vector3.ZERO, Vector3(1, 0, 0), 0.0), 0.0, "intervalle nul")
	# Joueur qui avance : sa référence (en retard) est un peu au-delà de la
	# portée ; avec la marge elle passe, à 1,5 m immobile jamais.
	var w := Vector3.ZERO
	var n := Vector3(0, 0, 1)
	var lagging := Vector3(0, 0, 0.5 + Barricade.REPAIR_REACH + 0.2)
	assert_false(Barricade.can_repair_from(lagging, w, n), "référence en retard : hors portée stricte")
	assert_true(Barricade.can_repair_from(lagging, w, n, 0.5, 0.5 + Player.lag_slack(4.0, 0.05, cap)), "avec la marge de latence : acceptée")
	assert_false(Barricade.can_repair_from(Vector3(0, 0, 0.5 + 1.5), w, n, 0.5, 0.5 + cap), "à 1,5 m, même avec la marge maximale : refusée")


## Règle pure : fenêtre au milieu d'un mur en (0 ; 0 ; 0), intérieur vers +z,
## face intérieure de la barrière à 0,5 m.
func test_repair_range_rule() -> void:
	var w := Vector3.ZERO
	var n := Vector3(0, 0, 1)
	var contact := 0.5 + Player.RADIUS
	assert_true(Barricade.can_repair_from(Vector3(0, 0, contact), w, n), "collé à la barrière : réparable")
	assert_true(Barricade.can_repair_from(Vector3(0, 0, 0.5 + Barricade.REPAIR_REACH - 0.01), w, n), "bord de la portée")
	assert_false(Barricade.can_repair_from(Vector3(0, 0, 0.5 + 1.5), w, n), "à 1,5 m de la barrière : refusé")
	assert_false(Barricade.can_repair_from(Vector3(0, 0, 0.5 + Barricade.REPAIR_REACH + 0.05), w, n), "juste au-delà de la portée : refusé")
	# Ancienne portée : 2,4 m autour d'un point à 0,55 m devant l'ouverture.
	assert_false(Barricade.can_repair_from(Vector3(0, 0, 2.5), w, n), "réparable de 2,5 m avant : plus maintenant")
	assert_false(Barricade.can_repair_from(Vector3(0, 0, -contact), w, n), "de l'autre côté (dehors) : refusé")
	assert_false(Barricade.can_repair_from(Vector3(0, 0, 0.1), w, n), "dans le mur : refusé")
	# Le long du mur : derrière le mur voisin (au-delà du bord + un rayon), non.
	assert_true(Barricade.can_repair_from(Vector3(0.5 + 0.3, 0, contact), w, n), "épaule encore devant l'ouverture")
	assert_false(Barricade.can_repair_from(Vector3(1.4, 0, contact), w, n), "devant le mur voisin : refusé")
	# À travers un mur perpendiculaire collé au bord de l'ouverture (0,5 m
	# d'épaisseur) : le joueur de la pièce voisine est à 0,5 + RADIUS du bord.
	assert_false(Barricade.can_repair_from(Vector3(0.5 + 0.5 + Player.RADIUS, 0, contact), w, n), "à travers le mur voisin : refusé")
	# Autre étage.
	assert_false(Barricade.can_repair_from(Vector3(0, 3.0, contact), w, n), "étage du dessus : refusé")
	assert_false(Barricade.can_repair_from(Vector3(0, -3.0, contact), w, n), "étage du dessous : refusé")
	assert_true(Barricade.can_repair_from(Vector3(0, 0.4, contact), w, n), "petite marche : réparable")
	# Mur de biais : même règle, dans le repère de l'ouverture.
	var d := Vector3(1, 0, 1).normalized()
	var s := Vector3(d.z, 0, -d.x)
	assert_true(Barricade.can_repair_from(w + d * contact + s * 0.3, w, d), "mur en biais : collé")
	assert_false(Barricade.can_repair_from(w + d * 2.0, w, d), "mur en biais : trop loin")


## Instances : fenêtre, porte simple, porte double de 2 m (mesure depuis le
## segment de l'ouverture : réparable sur toute sa largeur), murs tournés.
func test_repair_range_by_kind() -> void:
	var win := _opening(BarricadeRules.WINDOW, Vector3(4, 0, 2), Vector3(-1, 0, 0))
	var door := _opening(BarricadeRules.DOOR, Vector3(-3, 0, 5), Vector3(0, 0, -1))
	var dbl := _opening(BarricadeRules.DOUBLE_DOOR, Vector3(0, 0, 0), Vector3(0, 0, 1))
	for b: Barricade in [win, door, dbl]:
		var name_k := b.kind
		var side := Vector3(b.inward.z, 0, -b.inward.x)
		var face := b.global_position + b.inward * b.barrier_face()
		assert_true(b.in_repair_range(b.repair_spot()), "%s : place de réparation" % name_k)
		assert_true(b.in_repair_range(face + b.inward * Player.RADIUS), "%s : collé" % name_k)
		assert_false(b.in_repair_range(face + b.inward * 1.5), "%s : 1,5 m de la barrière, refusé" % name_k)
		assert_false(b.in_repair_range(b.global_position - b.inward * (b.barrier_face() + Player.RADIUS)), "%s : dehors, refusé" % name_k)
		# Sur toute la largeur de l'ouverture.
		var half := b.width * 0.5
		for k in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			assert_true(b.in_repair_range(face + b.inward * 0.5 + side * half * k), "%s : réparable à %.0f %% de la largeur" % [name_k, k * 100.0])
		assert_false(b.in_repair_range(face + b.inward * 0.5 + side * (half + 0.6)), "%s : devant le mur voisin, refusé" % name_k)
		# Visée : vers l'ouverture oui, dos tourné non.
		assert_true(b.faces_opening(-b.inward), "%s : face à l'ouverture" % name_k)
		assert_true(b.faces_opening((-b.inward + side * 2.0).normalized()), "%s : de biais (bout d'une large ouverture)" % name_k)
		assert_false(b.faces_opening(side), "%s : le long du mur, pas d'invite" % name_k)
		assert_false(b.faces_opening(b.inward), "%s : dos tourné, pas d'invite" % name_k)
		assert_true(b.faces_opening(Vector3.DOWN), "%s : regard vers le sol (planches basses)" % name_k)
	assert_near(win.barrier_face(), 0.5, 0.001, "barrière de fenêtre : 1 m")
	assert_near(door.barrier_face(), MapGeom.WALL_HALF, 0.001, "barrière de porte : l'épaisseur du mur")
	assert_true(dbl.in_repair_range(Vector3(-1.0, 0, 0.25 + Player.RADIUS)), "porte double : bout gauche, collé")
	assert_true(dbl.in_repair_range(Vector3(1.0, 0, 0.25 + Player.RADIUS)), "porte double : bout droit, collé")
	for b: Barricade in [win, door, dbl]:
		b.free()
