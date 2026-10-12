extends TestCase
## Butin au sol, présentation (docs/ART_DIRECTION.md « Butin ») : arc de
## l'objet qui jaillit d'un corps (LootArc), habillage selon la rareté
## (LootFx), sons, fiche de l'objet regardé (LootCard), objets jaillis
## reçus du réseau (LootSystem.valid_pop).

var _lang := "fr"


func before_each() -> void:
	_lang = Settings.language
	Settings.language = "fr"


func after_each() -> void:
	Settings.language = _lang


# --------------------------------------------------------------------------
# Arc (LootArc)
# --------------------------------------------------------------------------

func test_arc_starts_and_ends_at_given_points() -> void:
	var a := Vector3(2, 0.7, -1)
	var b := Vector3(3, 0.0, -0.4)
	var p := LootArc.plan(a, b, 42)
	assert_true(LootArc.position(p, 0.0).is_equal_approx(a), "départ : le corps")
	assert_true(LootArc.position(p, float(p.settle)).is_equal_approx(b), "arrivée : le point du serveur")
	assert_true(LootArc.position(p, 100.0).is_equal_approx(b), "reste posé")
	assert_true(float(p.settle) > 0.4 and float(p.settle) < 1.6, "durée lisible : %.2f s" % float(p.settle))


func test_arc_is_deterministic() -> void:
	var a := Vector3(0, 0.7, 0)
	var b := Vector3(1, 0, 0)
	var p1 := LootArc.plan(a, b, 7)
	var p2 := LootArc.plan(a, b, 7)
	for t in [0.05, 0.2, 0.37, 0.6, 0.9]:
		assert_true(LootArc.position(p1, t).is_equal_approx(LootArc.position(p2, t)), "même arc sur chaque machine (t=%.2f)" % t)
		assert_near(LootArc.spin(p1, t), LootArc.spin(p2, t), 0.0001)
	var p3 := LootArc.plan(a, b, 8)
	assert_true(float(p3.apex) != float(p1.apex) or float(p3.phase) != float(p1.phase), "graine différente : arc différent")


func test_arc_jumps_up_then_bounces() -> void:
	var a := Vector3(0, 0.7, 0)
	var b := Vector3(1.2, 0, 0)
	var p := LootArc.plan(a, b, 3)
	# Monte au-dessus du départ (impulsion), jamais sous le sol.
	var top := LootArc.position(p, float(p.t_up))
	assert_near(top.y, a.y + float(p.apex), 0.001, "sommet")
	assert_true(top.y > a.y + 0.4, "impulsion vers le haut")
	var lands := LootArc.landings(p)
	assert_eq(lands.size(), 3, "vol + deux rebonds")
	assert_true(lands[0] < lands[1] and lands[1] < lands[2], "contacts dans l'ordre")
	assert_near(LootArc.position(p, lands[0]).y, b.y, 0.002, "premier contact au sol")
	# Rebonds : plus bas l'un que l'autre.
	var b1: Array = p.b1
	var b2: Array = p.b2
	var h1 := LootArc.position(p, float(b1[0]) + float(b1[1]) * 0.5).y - b.y
	var h2 := LootArc.position(p, float(b2[0]) + float(b2[1]) * 0.5).y - b.y
	assert_true(h1 > 0.08 and h2 > 0.0 and h2 < h1, "rebonds décroissants (%.3f puis %.3f)" % [h1, h2])
	var t := 0.0
	while t < float(p.settle):
		assert_true(LootArc.position(p, t).y >= b.y - 0.0001, "jamais sous le sol (t=%.2f)" % t)
		t += 0.01
	# Avance horizontalement sans revenir en arrière.
	var last := -1.0
	t = 0.0
	while t <= float(p.settle):
		var x := LootArc.position(p, t).x
		assert_true(x >= last - 0.0001, "avance vers l'arrivée")
		last = x
		t += 0.02


func test_hover_and_spin_after_landing() -> void:
	var p := LootArc.plan(Vector3(0, 0.7, 0), Vector3(1, 0, 0), 11)
	assert_eq(LootArc.hover(p, -0.1), 0.0, "pas de flottement en vol")
	assert_near(LootArc.hover(p, 0.0), 0.0, 0.0001, "se pose d'abord")
	var h := LootArc.hover(p, 3.0)
	assert_true(absf(h - LootArc.HOVER_H) <= LootArc.BOB_AMP + 0.001, "flotte à sa hauteur (%.3f)" % h)
	# Tour lent au repos, rotation continue à l'atterrissage.
	var s0 := LootArc.spin(p, float(p.settle))
	var s1 := LootArc.spin(p, float(p.settle) + 1.0)
	assert_near(absf(s1 - s0), LootArc.SPIN_IDLE, 0.001, "rotation lente")
	assert_near(LootArc.spin(p, float(p.settle) - 0.0001), s0, 0.01, "pas de saut de rotation")
	assert_eq(LootArc.tumble(p, float(p.settle) + 0.5), 0.0, "posé à plat")


# --------------------------------------------------------------------------
# Rareté (LootFx)
# --------------------------------------------------------------------------

func test_rarity_fx_selection() -> void:
	var c := LootFx.tier(LootFx.COMMON)
	assert_eq(int(c.sparkles), 0, "commune : pas d'étoiles")
	assert_eq(int(c.beams), 0)
	assert_eq(float(c.light), 0.0, "commune : pas de lumière")
	for r in [LootFx.RARE, LootFx.EPIC]:
		var t := LootFx.tier(r)
		assert_true(int(t.sparkles) > 0 and int(t.beams) == 0, "rare / épique : étoiles, pas de faisceau")
	assert_true(int(LootFx.tier(LootFx.EPIC).sparkles) > int(LootFx.tier(LootFx.RARE).sparkles), "épique plus scintillante")
	for r in [LootFx.LEGENDARY, LootFx.UNIQUE]:
		var t := LootFx.tier(r)
		assert_true(int(t.beams) >= 3 and float(t.beam_h) >= 2.0, "légendaire / unique : faisceaux visibles de loin")
		assert_true(float(t.light) > 0.0 and int(t.motes) > 0 and bool(t.big_stars), "lumière, étincelles, grandes étoiles")
	assert_eq(LootFx.tier(99).beams, LootFx.tier(LootFx.UNIQUE).beams, "rareté bornée")
	assert_eq(LootFx.color(LootFx.LEGENDARY), Color("FF9A1F"), "couleur du hub v2")
	assert_eq(LootFx.color(LootFx.RARE), Color("4D9BFF"))


func test_rarity_sounds() -> void:
	var seen := {}
	for r in 4:
		var n := LootFx.pickup_sound(r)
		assert_false(seen.has(n), "un son par rareté : %s" % n)
		seen[n] = true
		assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % n), "%s.wav généré" % n)
	assert_eq(LootFx.pickup_sound(LootFx.UNIQUE), LootFx.pickup_sound(LootFx.LEGENDARY))
	for n in [LootFx.LAND_SOUND, LootFx.DROP_LEGENDARY_SOUND]:
		assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % n), "%s.wav généré" % n)
	assert_eq(SfxLoudness.category("loot_pickup_epic").id, "butin")
	assert_eq(SfxLoudness.category("loot_land").id, "butin_sol")


func test_sample_and_part_rarity() -> void:
	assert_eq(LootFx.sample_rarity("dog_fang"), LootFx.COMMON)
	assert_eq(LootFx.sample_rarity("nurse_badge"), LootFx.RARE)
	assert_eq(LootFx.sample_rarity("surgeon_scalpel"), LootFx.EPIC)
	assert_eq(LootFx.sample_rarity("surgeon_heart"), LootFx.LEGENDARY)
	var weak := {"id": "part_damage", "level": 3, "mods": {"damage": 0.05}}
	var strong := {"id": "part_damage", "level": 3, "mods": {"damage": 0.25, "fire_rate": 0.2}}
	assert_true(LootFx.part_rarity(strong) > LootFx.part_rarity(weak), "meilleure pièce, rareté plus haute")


func test_fx_nodes_per_rarity() -> void:
	for r in 5:
		var root := Node3D.new()
		var item := Node3D.new()
		root.add_child(item)
		var fx := LootFx.build(root, item, r, 0.3)
		var t := LootFx.tier(r)
		assert_eq((fx.beams as Array).size(), int(t.beams) + (1 if int(t.beams) > 0 else 0), "faisceaux (rareté %d)" % r)
		assert_eq(item.get_node_or_null("Sparkles") != null, int(t.sparkles) > 0, "étoiles (rareté %d)" % r)
		assert_eq(fx.light != null, float(t.light) > 0.0, "lumière (rareté %d)" % r)
		LootFx.set_fade(fx, 1.0, float(t.light))
		for b: MeshInstance3D in fx.beams:
			assert_near(b.scale.y, 1.0, 0.001, "faisceau déployé")
		root.free()


func test_drop_model_dressed() -> void:
	for r in 5:
		var root := Node3D.new()
		var parts := LootDrop.build_model(root, "ak47", r)
		assert_true(root.get_node_or_null("Body/Spin") != null, "corps et pivot")
		var meshes := (parts.model as Node).find_children("*", "MeshInstance3D", true, false)
		assert_true(meshes.size() > 0, "vraie arme")
		for mi: MeshInstance3D in meshes:
			assert_true(mi.material_overlay is ShaderMaterial, "contour de rareté")
		assert_true(float(parts.half) > 0.2, "demi-taille d'un fusil : %.2f" % float(parts.half))
		root.free()


func test_item_models_are_cubic() -> void:
	for r in 5:
		for mesh: Mesh in [LootFx.sample_mesh(r), LootFx.part_mesh(r)]:
			var rep := VoxelCheck.check_mesh(mesh, Transform3D.IDENTITY, 1.0, "butin", VoxelCheck.CUBE_CHAR)
			assert_true(rep.ok, "cubes de 2,5 cm : %s" % rep.get("fr", ""))
	var star := LootFx.star_mesh(true)
	assert_true(star.get_surface_count() == 1, "étoile en un maillage")


# --------------------------------------------------------------------------
# Fiche (LootCard)
# --------------------------------------------------------------------------

func test_weapon_card_data() -> void:
	var w := GameWeapon.make("ak47", 12, LootFx.LEGENDARY)
	var hand := GameWeapon.make("m1911", 1, LootFx.COMMON)
	var c := LootCard.weapon_info(w, hand, 5, "", "E")
	assert_eq(c.title, WeaponDB.display_name("ak47"))
	assert_true(String(c.eyebrow).begins_with("LÉGENDAIRE"), "rareté : %s" % c.eyebrow)
	assert_eq(c.color, LootFx.color(LootFx.LEGENDARY))
	assert_eq(c.level, "NIV. 12 REQUIS", "niveau trop haut")
	assert_true(c.level_bad)
	assert_eq(c.key, "E", "touche réelle")
	assert_eq(c.action, "RAMASSER")
	assert_true(String(c.delta).begins_with("▲"), "meilleure que l'arme en main : %s" % c.delta)
	assert_true(c.delta_good)
	assert_eq((c.stats as Array).size(), 6, "six statistiques")
	var dmg: Dictionary = c.stats[0]
	assert_eq(dmg.key, "damage")
	assert_true(String(dmg.mod).begins_with("+"), "dégâts au-dessus de l'arme en main : %s" % dmg.mod)
	assert_true(dmg.good)
	# Niveau atteint : pas d'avertissement ; arme moins bonne : écart rouge.
	var c2 := LootCard.weapon_info(GameWeapon.make("m1911", 1, 0), GameWeapon.make("ak47", 12, 3), 20, "", "F")
	assert_eq(c2.level, "NIV. 1")
	assert_false(c2.level_bad)
	assert_true(String(c2.delta).begins_with("▼") and not c2.delta_good, "moins bonne : %s" % c2.delta)
	# Arme d'un coéquipier : pas de touche.
	var c3 := LootCard.weapon_info(w, {}, 50, "Ann", "F")
	assert_eq(c3.key, "")
	assert_eq(c3.action, "BUTIN DE ANN")
	assert_eq(c3.delta, "", "sans arme en main : pas d'écart")
	assert_eq(String((c3.stats[0] as Dictionary).mod), "")
	assert_eq(LootCard.weapon_info(w, {}, 50, "", "F", true).warn, "INVENTAIRE PLEIN")
	Settings.language = "en"
	assert_eq(LootCard.weapon_info(w, hand, 5, "", "E").level, "LVL 12 REQUIRED")
	assert_eq(LootCard.weapon_info(w, {}, 50, "Ann", "F").action, "ANN'S LOOT")


func test_part_and_sample_card_data() -> void:
	var p := {"id": "part_damage", "level": 7, "mods": {"damage": 0.12, "recoil": -0.08}}
	var c := LootCard.part_info(p)
	assert_eq(c.level, "NIV. 7")
	assert_true(String(c.eyebrow).begins_with("PIÈCE"), c.eyebrow)
	assert_eq((c.lines as Array).size(), 2, "deux modificateurs")
	assert_true(c.lines[0][1], "bonus en vert")
	assert_eq(c.key, "", "ramassage automatique")
	var s := LootCard.sample_info("dog_fang", 3)
	assert_eq(s.title, "CROC")
	assert_eq(s.score, "DANS LE SAC : 3")
	assert_eq(s.color, LootFx.color(LootFx.COMMON))


func test_pick_looked_item() -> void:
	var eye := Vector3(0, 1.6, 0)
	var fwd := Vector3(0, 0, -1)
	var pts := [Vector3(1.5, 0.4, -2), Vector3(0.1, 1.4, -2.5), Vector3(0, 1.5, 3), Vector3(0.05, 1.5, -8)]
	assert_eq(LootCard.pick(eye, fwd, pts, 4.5), 1, "l'objet dans l'axe du regard")
	assert_eq(LootCard.pick(eye, fwd, [pts[0], pts[2]], 4.5), -1, "rien à côté ni derrière")
	assert_eq(LootCard.pick(eye, fwd, [pts[3]], 4.5), -1, "trop loin")
	assert_eq(LootCard.pick(eye, fwd, [], 4.5), -1)


func test_valid_pop() -> void:
	assert_true(LootSystem.valid_pop([LootPickup.KIND_SAMPLE, {"id": "dog_fang"}, Vector3(0, 0.7, 0), Vector3(1, 0, 0), 5]))
	assert_false(LootSystem.valid_pop(["gold", {}, Vector3.ZERO, Vector3.ONE, 5]), "sorte inconnue")
	assert_false(LootSystem.valid_pop([LootPickup.KIND_PART, {}, Vector3.ZERO, Vector3(50, 0, 0), 5]), "trop loin du corps")
	assert_false(LootSystem.valid_pop([LootPickup.KIND_PART, {}, Vector3(NAN, 0, 0), Vector3.ZERO, 5]), "non fini")
	assert_false(LootSystem.valid_pop("x"))
	assert_true(absf(LootSystem.scatter_angle(3, 1, 2) - LootSystem.scatter_angle(3, 0, 2) - PI) < 0.0001, "répartis en couronne")
