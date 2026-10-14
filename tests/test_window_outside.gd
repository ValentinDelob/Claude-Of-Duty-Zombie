extends TestCase
## Le dehors des fenêtres barricadées et des portes à zombies (WindowOutside) :
## aspect déterministe mais varié, masque des interstices qui suit les
## planches (faisceaux, projecteur, poussière), aucune collision ni
## navigation, préréglage LOW, accroche des ambiances.


## Fenêtre (ou porte) seule, au sol en (0, 0, 0), intérieur vers +Z, mur de
## 1 m (cartes grille) ou de 0,5 m (porte).
func make(kind := BarricadeRules.WINDOW, s := 1234) -> Barricade:
	var o := BarricadeLayout.Opening.new()
	o.index = 0
	o.pos = Vector3.ZERO
	o.inward_dir = Vector3(0, 0, 1)
	o.height = MapBuilder.WALL_HEIGHT
	o.kind = kind
	o.width = BarricadeRules.width(kind)
	o.seed = s
	if kind != BarricadeRules.WINDOW:
		o.wall_depth = MapGeom.WALL_HALF * 2.0
	var b := Barricade.new()
	b.setup(o)
	host.add_child(b)
	return b


func test_params_are_deterministic_and_varied() -> void:
	var seen := {}
	for s in 15:
		var sd := hash(Vector2i(s * 7, 30 - s))
		var a := WindowOutside.params_for(sd)
		assert_eq(a, WindowOutside.params_for(sd), "même graine, même dehors")
		var n := int(a.panes.x * a.panes.y)
		assert_true(a.broken != 0 and a.broken != (1 << n) - 1, "au moins une vitre cassée, jamais toutes")
		assert_eq(a.broken & a.cracked, 0, "une vitre est cassée OU fêlée")
		assert_true(absf(a.light_x) <= 0.3, "source près de l'axe")
		seen[[a.panes, a.broken, a.cracked]] = true
	assert_true(seen.size() >= 8, "15 fenêtres, au moins 8 dehors différents (%d)" % seen.size())
	assert_eq(WindowOutside.params_for(5, true).broken, 0, "porte : pas de vitre")


func test_gap_mask_follows_planks() -> void:
	for kind in [BarricadeRules.WINDOW, BarricadeRules.DOOR, BarricadeRules.DOUBLE_DOOR]:
		var b := make(kind)
		var area := WindowOutside.opening_rect(b)
		var full := WindowOutside.gap_mask(area, WindowOutside.blockers(b, b.full_mask()))
		var open := WindowOutside.gap_mask(area, WindowOutside.blockers(b, 0))
		var f_full := WindowOutside.open_fraction(full)
		var f_open := WindowOutside.open_fraction(open)
		assert_true(f_full > 0.0, "%s : du jour entre les planches (%.2f)" % [kind, f_full])
		assert_true(f_full < 0.6, "%s : les planches bouchent l'essentiel (%.2f)" % [kind, f_full])
		if kind == BarricadeRules.WINDOW:
			assert_near(f_open, 1.0, 0.001, "fenêtre sans planche : tout ouvert")
		else:
			assert_true(f_open < 1.0 and f_open > 0.4, "%s : le battant cassé bouche le bas (%.2f)" % [kind, f_open])
		# Chaque planche arrachée ouvre exactement son rectangle (moins ce que
		# d'autres planches couvrent encore).
		var prev := f_full
		var m := b.full_mask()
		for i in b.plank_count:
			m &= ~(1 << i)
			var g := WindowOutside.gap_mask(area, WindowOutside.blockers(b, m))
			var fr := WindowOutside.open_fraction(g)
			assert_true(fr >= prev, "%s : planche %d arrachée, jamais moins de jour" % [kind, i])
			prev = fr
			# Le milieu de la planche arrachée est du jour, sauf si une autre
			# planche (ou le battant) la recouvre encore.
			var c: Vector3 = b._rest[i].origin
			var covered := false
			for r in WindowOutside.blockers(b, m):
				covered = covered or r.has_point(Vector2(c.x, c.y))
			var px := clampi(int((c.x - area.position.x) / area.size.x * WindowOutside.MASK_RES.x), 0, WindowOutside.MASK_RES.x - 1)
			var py := clampi(int((area.end.y - c.y) / area.size.y * WindowOutside.MASK_RES.y), 0, WindowOutside.MASK_RES.y - 1)
			assert_eq(g[py * WindowOutside.MASK_RES.x + px] > 127, not covered, "%s : texel de la planche %d" % [kind, i])
		assert_near(prev, f_open, 0.001, "%s : toutes arrachées = ouverture nue" % kind)
		b.free()


## Le jeu suit les planches : masque, texture du projecteur, faisceaux.
func test_outside_follows_barricade_mask() -> void:
	var b := make()
	var o := b.outside
	assert_true(o != null, "dehors créé avec la fenêtre")
	o.place(-2.5, 1.5, MapBuilder.WALL_HEIGHT, true)
	assert_true(o.card != null and o.frame != null, "carte et cadre posés")
	assert_near(o.card.position.z, -2.5 + WindowOutside.CARD_GAP, 0.001, "carte contre le mur du fond")
	var lit_full := _lit(o)
	b.set_mask(b.full_mask() & 0b010101, false)
	var lit_half := _lit(o)
	b.set_mask(0, false)
	var lit_open := _lit(o)
	assert_true(lit_full > 0, "planches clouées : quelques raies (%d)" % lit_full)
	# Vu de la source, l'embrasure de 1 m ne laisse voir qu'une tranche des planches.
	assert_true(lit_half > lit_full and lit_open >= lit_half, "plus de jour quand on arrache (%d < %d <= %d)" % [lit_full, lit_half, lit_open])
	assert_near(WindowOutside.open_fraction(o.mask_image.get_data()), 1.0, 0.001, "masque des faisceaux à jour")
	b.set_mask(b.full_mask(), false)
	assert_eq(_lit(o), lit_full, "planches reposées : mêmes raies")
	b.free()


func _lit(o: WindowOutside) -> int:
	var n := 0
	for v in o.proj_image.get_data():
		if v > 127:
			n += 1
	return n


## Purement visuel : aucun corps, aucune forme, aucune navigation ; la seule
## collision de la fenêtre reste sa barrière.
func test_no_collision_no_nav() -> void:
	for kind in [BarricadeRules.WINDOW, BarricadeRules.DOUBLE_DOOR]:
		var b := make(kind)
		var before := b.find_children("*", "CollisionShape3D", true, false).size()
		b.outside.place(-2.0, 1.5, MapBuilder.WALL_HEIGHT, true)
		await wait_frames(2)
		var o := b.outside
		assert_eq(o.find_children("*", "CollisionObject3D", true, false).size(), 0, "%s : aucun corps" % kind)
		assert_eq(o.find_children("*", "CollisionShape3D", true, false).size(), 0, "%s : aucune forme" % kind)
		assert_eq(o.find_children("*", "NavigationRegion3D", true, false).size(), 0)
		assert_eq(o.find_children("*", "NavigationObstacle3D", true, false).size(), 0)
		assert_eq(b.find_children("*", "CollisionShape3D", true, false).size(), before, "%s : barrière seule" % kind)
		for gi: GeometryInstance3D in o.find_children("*", "GeometryInstance3D", true, false):
			assert_eq(gi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s : %s sans ombre" % [kind, gi.name])
			assert_true(gi.visibility_range_end > 0.0, "%s : %s s'efface au loin" % [kind, gi.name])
		assert_false(o.shaft.shadow_enabled, "projecteur sans ombre")
		assert_near(o.shaft.light_volumetric_fog_energy, 0.0, 0.0001, "pas de cône plein dans la brume")
		b.free()


## Cadre cubique : sommets sur la grille de 5 cm du monde.
func test_frame_on_cube_grid() -> void:
	for kind in [BarricadeRules.WINDOW, BarricadeRules.DOOR]:
		var b := make(kind, 99)
		b.outside.place(-2.5, 1.5, MapBuilder.WALL_HEIGHT, true)
		var fr := b.outside.frame
		var bad := 0
		for v: Vector3 in fr.mesh.get_faces():
			var w := fr.position + v
			for k in 3:
				if absf(w[k] / VoxelBuild.CUBE - roundf(w[k] / VoxelBuild.CUBE)) > 0.001:
					bad += 1
		assert_eq(bad, 0, "%s : cadre sur la grille de 5 cm" % kind)
		b.free()


func test_activity_rules() -> void:
	assert_near(WindowOutside.activity_for(true, 0, 6), 0.0, 0.0001, "fenêtre ouverte : le vrai zombie passe, plus de silhouettes")
	assert_true(WindowOutside.activity_for(false, 6, 6) < WindowOutside.activity_for(true, 6, 6), "moins entre deux manches")
	assert_true(WindowOutside.activity_for(true, 2, 6) < WindowOutside.activity_for(true, 6, 6), "moins quand les vrais arrachent")
	var b := make()
	var o := b.outside
	o.place(-2.5, 1.5, MapBuilder.WALL_HEIGHT, true)
	o.apply_quality(RenderQuality.preset(Settings.Quality.LOW))
	assert_false(o.live, "LOW : carte fixe")
	assert_false(o.shaft.visible or o.beams.visible or o.motes.visible, "LOW : ni raies, ni faisceaux, ni poussière")
	assert_near(o.activity, 0.0, 0.0001, "LOW : aucune silhouette")
	assert_true(o.card.visible, "LOW : la carte reste (lumière du dehors fixe)")
	o.apply_quality(RenderQuality.preset(Settings.Quality.MEDIUM))
	assert_true(o.live and o.shaft.visible and o.beams.visible, "MEDIUM : tout")
	b.free()


func test_mood_hook() -> void:
	assert_eq(WindowOutside.tint_for("a"), WindowOutside.TINT, "sans ambiance : bleu-vert")
	WindowOutside.mood_provider = func(zone: String) -> Color: return Color.RED if zone == "c" else Color(0, 0, 0, 0)
	assert_eq(WindowOutside.tint_for("c"), Color.RED, "ambiance de la pièce")
	assert_eq(WindowOutside.tint_for("a"), WindowOutside.TINT, "couleur transparente : défaut")
	WindowOutside.mood_provider = Callable()
