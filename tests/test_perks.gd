extends TestCase
## Règles des atouts (PerkDB) : prix, effets de NOVA FLOP (PhD Flopper) et
## DEADEYE DRAM (Deadshot Daiquiri).


func _pd(perks: Array) -> PlayerData:
	var pd := PlayerData.new()
	pd.perks = PackedStringArray(perks)
	return pd


func test_catalogue() -> void:
	assert_eq(PerkDB.PERKS.size(), 7, "7 atouts")
	assert_eq(PerkDB.cost("nova", false), 2000, "NOVA FLOP à 2000 (PhD Flopper)")
	assert_eq(PerkDB.cost("deadeye", false), 1500, "DEADEYE DRAM à 1500 (Deadshot)")
	assert_eq(PerkDB.cost("nova", true), 2000, "même prix en solo")
	assert_true(PerkDB.needs_power("nova") and PerkDB.needs_power("deadeye", true), "courant requis")
	# Couleurs distinctes (icônes, machines).
	var cols := []
	for id in PerkDB.PERKS:
		var c := PerkDB.color(id)
		for o: Color in cols:
			assert_true(Vector3(c.r - o.r, c.g - o.g, c.b - o.b).length() > 0.15, "couleur de %s distincte" % id)
		cols.append(c)
	# Violet franc pour NOVA FLOP.
	var n := PerkDB.color("nova")
	assert_true(n.b > 0.8 and n.r > 0.4 and n.g < 0.3, "NOVA FLOP violet")


func test_nova_self_damage() -> void:
	assert_eq(PerkDB.explosive_self_mult(_pd([])), 1.0)
	assert_eq(PerkDB.explosive_self_mult(_pd(["nova"])), 0.0, "aucun dégât de ses explosions")
	assert_eq(PerkDB.explosive_self_mult(_pd(["deadeye", "titan"])), 1.0)
	assert_eq(PerkDB.explosive_self_mult(null), 1.0)


func test_nova_dive_trigger() -> void:
	var pd := _pd(["nova"])
	# Plongeon en sprint sur sol plat : sommet du saut rasant.
	var flat_dive := Player.DIVE_UP * Player.DIVE_UP / (2.0 * Player.GRAVITY)
	assert_true(PerkDB.nova_triggers(pd, flat_dive), "plongeon en sprint (%.2f m) suffit" % flat_dive)
	assert_false(PerkDB.nova_triggers(pd, 0.05), "pas sans chute")
	assert_false(PerkDB.nova_triggers(_pd([]), 3.0), "sans l'atout : rien")
	assert_false(PerkDB.nova_triggers(null, 3.0))


func test_nova_damage_by_round() -> void:
	# Tue en un coup jusqu'aux manches 10-12 près du point d'impact (BO1).
	var at_15 := ThrowableRules.splash(PerkDB.NOVA_DAMAGE, PerkDB.NOVA_RADIUS, 1.5)
	assert_true(at_15 >= RoundRules.zombie_health(12), "manche 12 à 1,5 m (%d / %d)" % [at_15, RoundRules.zombie_health(12)])
	var edge := ThrowableRules.splash(PerkDB.NOVA_DAMAGE, PerkDB.NOVA_RADIUS, PerkDB.NOVA_RADIUS)
	assert_true(edge >= RoundRules.zombie_health(8), "manche 8 au bord (%d)" % edge)
	var center := ThrowableRules.splash(PerkDB.NOVA_DAMAGE, PerkDB.NOVA_RADIUS, 0.0)
	# PV linéaires (GAME_CONCEPT §4.3) : 1 850 PV en manche 18 (BO1 : 1 850 en 16).
	assert_true(center < RoundRules.zombie_health(18), "plus de un coup en manche 18")


func test_deadeye_modifiers() -> void:
	var d := _pd(["deadeye"])
	assert_true(PerkDB.aim_assist(d) and not PerkDB.aim_assist(_pd(["nova"])))
	assert_true(PerkDB.hip_spread_mult(d) < 0.8, "dispersion en hanche réduite")
	assert_eq(PerkDB.hip_spread_mult(_pd([])), 1.0)
	assert_true(PerkDB.recoil_mult(d) < 1.0, "recul réduit")
	assert_eq(PerkDB.recoil_mult(null), 1.0)


func test_deadeye_pick() -> void:
	var eye := Vector3(0, 1.6, 0)
	var fwd := Vector3(0, 0, -1)
	var heads := [
		Vector3(3.0, 1.7, -10.0),   # ~16,7° : hors du cône
		Vector3(1.0, 1.7, -10.0),   # ~5,8°
		Vector3(-0.5, 1.7, -6.0),   # ~4,9° : le plus proche du centre
		Vector3(0.0, 1.7, 8.0),     # derrière
		Vector3(0.0, 1.6, -60.0),   # trop loin
	]
	assert_eq(PerkDB.deadeye_pick(eye, fwd, heads), 2, "tête la plus proche du centre")
	assert_eq(PerkDB.deadeye_pick(eye, fwd, [heads[0], heads[3], heads[4]]), -1, "rien dans le cône")
	assert_eq(PerkDB.deadeye_pick(eye, fwd, []), -1)


func test_look_angles_match_player() -> void:
	# Mêmes conventions que Player (lacet autour de Y, -Z devant) et que
	# AutotestHelpers.aim_at.
	var eye := Vector3(1, 1.6, 2)
	for target in [Vector3(1, 1.6, -5), Vector3(6, 2.5, 2), Vector3(-3, 0.5, 7)]:
		var a := PerkDB.look_angles(eye, target)
		var b := Basis.from_euler(Vector3(a.y, a.x, 0.0), EULER_ORDER_YXZ)
		var dir: Vector3 = -b.z
		assert_true(dir.angle_to(target - eye) < 0.001, "direction vers %s" % target)
