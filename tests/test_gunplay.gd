extends TestCase
## Sensation de tir : organes de visée alignés (cran, guidon), pose de visée,
## dispersion dynamique, conversion du réticule, recul progressif, lunettes,
## flammes de bouche, douilles, surfaces d'impact.


func test_sight_line_is_parallel_to_bore_axis() -> void:
	for id in WeaponDB.WEAPONS:
		var mid: String = WeaponDB.stats(id).model
		var rear := WeaponModels.anchor(mid, "sight")
		var front := WeaponModels.anchor(mid, "front")
		assert_near(rear.x, 0.0, 0.0001, "%s : cran centré" % id)
		assert_near(front.x, 0.0, 0.0001, "%s : guidon centré" % id)
		assert_near(rear.y, front.y, 0.0001, "%s : cran et guidon à la même hauteur" % id)
		assert_true(front.z < rear.z - 0.08, "%s : guidon devant le cran (%.2f / %.2f)" % [id, front.z, rear.z])
		var eye := WeaponModels.anchor(mid, "ads").z
		assert_true(eye >= 0.05 and eye <= 0.5, "%s : œil à %.2f m du cran" % [id, eye])


func test_ads_pose_puts_sight_line_on_camera_axis() -> void:
	for id in WeaponDB.WEAPONS:
		var mid: String = WeaponDB.stats(id).model
		var pose := ViewModel.ads_pose(mid)
		var xf := Transform3D(Basis(Vector3.RIGHT, float(pose[1])), pose[0])
		var eye := WeaponModels.anchor(mid, "ads").z
		var rear := xf * WeaponModels.anchor(mid, "sight")
		var front := xf * WeaponModels.anchor(mid, "front")
		assert_true(rear.distance_to(Vector3(0, 0, -eye)) < 0.0001, "%s : cran sur l'axe à %.2f m" % [id, eye])
		assert_near(front.x, 0.0, 0.0001, "%s : guidon sur l'axe (x)" % id)
		assert_near(front.y, 0.0, 0.0001, "%s : guidon sur l'axe (y)" % id)
		assert_true(front.z < rear.z, "%s : guidon devant" % id)


func test_ads_is_accurate_like_bo1() -> void:
	for id in WeaponDB.WEAPONS:
		var s := WeaponDB.stats(id)
		if int(s.pellets) > 1:
			assert_true(float(s.spread_ads) > 1.0, "%s : fusil à pompe, gerbe en visée" % id)
			continue
		assert_near(WeaponDB.spread_deg(s, 1.0, 0.0, 1.0, 0.0), 0.0, 0.0001, "%s : aucune dispersion en visée" % id)
		# Même en marchant et après une rafale.
		assert_near(WeaponDB.spread_deg(s, 1.0, 1.0, 1.0, 2.0), 0.0, 0.0001, "%s : visée précise en mouvement" % id)


func test_hip_spread_opens_with_movement_and_bloom() -> void:
	var s := WeaponDB.stats("mp40")
	var still := WeaponDB.spread_deg(s, 0.0, 0.0, 1.0, 0.0)
	assert_near(still, float(s.spread_hip), 0.0001, "à l'arrêt : dispersion de base")
	assert_true(WeaponDB.spread_deg(s, 0.0, 1.0, 1.0, 0.0) > still * 1.3, "en marchant")
	assert_true(WeaponDB.spread_deg(s, 0.0, 2.0, 1.0, 0.0) > WeaponDB.spread_deg(s, 0.0, 1.0, 1.0, 0.0), "en l'air")
	assert_true(WeaponDB.spread_deg(s, 0.0, 0.0, 0.75, 0.0) < still, "accroupi")
	assert_true(WeaponDB.spread_deg(s, 0.0, 0.0, 1.0, 1.0) > still, "après des tirs")
	# Atout (DEADEYE DRAM) : hanche seulement.
	assert_near(WeaponDB.spread_deg(s, 0.0, 0.0, 1.0, 0.0, 0.55), still * 0.55, 0.0001, "multiplicateur de hanche")
	# Mise en joue : précision pleine seulement en fin de mouvement.
	assert_true(WeaponDB.spread_deg(s, 0.5, 0.0, 1.0, 0.0) > 0.0, "mi-course : encore imprécis")
	assert_true(WeaponDB.bloom_max(s) > float(s.spread_hip), "ouverture maximale")


func test_crosshair_gap_matches_spread() -> void:
	assert_near(WeaponDB.spread_to_px(0.0, 70.0, 720.0), 0.0, 0.0001)
	# Un cône de la moitié du champ touche le bord de l'écran.
	assert_near(WeaponDB.spread_to_px(35.0, 70.0, 720.0), 360.0, 0.01)
	var a := WeaponDB.spread_to_px(2.0, 70.0, 720.0)
	assert_true(WeaponDB.spread_to_px(2.0, 50.0, 720.0) > a, "zoom : réticule plus large pour le même cône")


func test_scopes() -> void:
	for id in ["l96a1", "dragunov"]:
		var s := WeaponDB.stats(id)
		assert_eq(WeaponDB.scope_kind(s), "sniper", "%s : écran de lunette" % id)
		assert_true(float(s.scope_fov) >= 8.0 and float(s.scope_fov) <= 16.0, "%s : zoom fort (%.0f°)" % [id, s.scope_fov])
	assert_true(float(WeaponDB.stats("l96a1").scope_fov) < float(WeaponDB.stats("dragunov").scope_fov), "L96A1 plus puissante que la Dragunov")
	for id in ["aug", "g11"]:
		assert_eq(WeaponDB.scope_kind(WeaponDB.stats(id)), "optic", "%s : lunette courte" % id)
	for id in ["m1911", "m16", "mp40", "olympia", "ray"]:
		assert_eq(WeaponDB.scope_kind(WeaponDB.stats(id)), "", "%s : visée mécanique" % id)


func test_flash_and_shell_families() -> void:
	for id in WeaponDB.WEAPONS:
		var s := WeaponDB.stats(id)
		var fl: String = s.get("flash", "")
		assert_true(fl == "none" or ViewModel.FLASH.has(fl), "%s : flamme %s" % [id, fl])
		assert_true(String(s.get("shell", "")) in ["", "pistol", "rifle", "shotgun"], "%s : douille" % id)
		assert_true(float(s.get("ads_time", 0.0)) > 0.05, "%s : durée de mise en joue" % id)
		assert_true(float(s.get("recoil_recover", -1.0)) >= 0.0 and float(s.recoil_recover) <= 1.0, "%s : retour du recul" % id)
	assert_eq(WeaponDB.stats("m1911").shell, "pistol")
	assert_eq(WeaponDB.stats("python").shell, "", "revolver : pas d'éjection au tir")


func test_recoil_climbs_progressively_then_recovers() -> void:
	var p := Player.new()
	var f := ShotFeel.new()
	var s := WeaponDB.stats("m14")
	f.on_shot(s, 1.0, 1.0, 10.0)
	var kick := deg_to_rad(f.last_kick_deg)
	assert_true(kick > 0.0, "montée du canon")
	assert_near(p.pitch, 0.0, 0.00001, "rien d'appliqué à l'instant du tir")
	var t := 10.0
	for i in 6:
		t += 1.0 / 60.0
		f.update(1.0 / 60.0, p, s, 1.0, false, false, 1.0, t)
	assert_true(p.pitch > kick * 0.9 and p.pitch <= kick * 1.001, "montée appliquée en 0,1 s (%.3f / %.3f)" % [p.pitch, kick])
	for i in 90:
		t += 1.0 / 60.0
		f.update(1.0 / 60.0, p, s, 1.0, false, false, 1.0, t)
	assert_near(p.pitch, kick * (1.0 - float(s.recoil_recover)), kick * 0.05, "retour partiel automatique")
	# Recul réduit (atout) : multiplicateur appliqué.
	var g := ShotFeel.new()
	seed(7)
	g.on_shot(s, 1.0, 0.5, 0.0)
	var half := g.last_kick_deg
	seed(7)
	g.on_shot(s, 1.0, 1.0, 0.0)
	assert_near(half, g.last_kick_deg * 0.5, 0.0001, "multiplicateur de recul")
	p.free()


func test_scope_breath() -> void:
	var p := Player.new()
	var f := ShotFeel.new()
	var s := WeaponDB.stats("l96a1")
	var t := 0.0
	for i in 60:
		t += 1.0 / 60.0
		f.update(1.0 / 60.0, p, s, 1.0, true, true, 1.0, t)
	assert_true(f.holding and f.breath < 1.0, "respiration retenue")
	for i in int(ShotFeel.HOLD_TIME * 60.0):
		t += 1.0 / 60.0
		f.update(1.0 / 60.0, p, s, 1.0, true, true, 1.0, t)
	assert_true(not f.holding and f.gasp > 0.0, "souffle épuisé puis essoufflement")
	for i in int((ShotFeel.GASP_TIME + 3.5) * 60.0):
		t += 1.0 / 60.0
		f.update(1.0 / 60.0, p, s, 1.0, true, false, 1.0, t)
	assert_true(f.gasp <= 0.0 and f.breath >= 0.99, "souffle repris")
	# Hors lunette : aucun décalage de visée.
	for i in 60:
		f.update(1.0 / 60.0, p, s, 0.0, false, false, 1.0, t)
	assert_true(f.aim_offset.length() < 0.0005, "pas de balancement hors lunette")
	p.free()


func test_impact_surfaces() -> void:
	assert_eq(Fx.surface_kind("crate"), "wood")
	assert_eq(Fx.surface_kind("dark_wood"), "wood")
	assert_eq(Fx.surface_kind("steel"), "metal")
	assert_eq(Fx.surface_kind("barrel"), "metal")
	assert_eq(Fx.surface_kind("marble"), "concrete")
	assert_eq(Fx.surface_of(null), "concrete")
