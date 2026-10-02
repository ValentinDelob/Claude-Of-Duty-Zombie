extends TestCase
## Moteur de vue de l'éditeur de cartes (MapView, docs/EDITOR_VIEWS.md § 3) :
## aller-retour project / unproject pour les six plans, axes de l'écran et
## de la profondeur, règles inversées (Droite : Y décroissant vers la
## droite), zoom sous le curseur borné.


func test_round_trip_on_every_plane() -> void:
	var v := MapView.new()
	v.size = Vector2(800, 600)
	v.zoom = 23.0
	v.origin = Vector2(140, 410)
	var pts := [Vector3(0, 0, 0), Vector3(12.5, 4.25, 3.5), Vector3(-3, 17, -0.3), Vector3(40, 2, 9.75)]
	for pl in MapView.PLANES:
		v.plane = pl
		for p: Vector3 in pts:
			var px := v.project(p)
			var back := v.unproject(px, MapView.depth_of(pl, p))
			assert_true(back.distance_to(p) < 0.0001, "%s : %s -> %s -> %s" % [pl, p, px, back])
	v.free()


func test_screen_axes_of_each_plane() -> void:
	# Dessus : x vers la droite, le nord en haut (y vers le bas de l'écran).
	assert_eq(MapView.uv_of("dessus", Vector3(1, 2, 3)), Vector2(1, 2))
	# Avant (caméra au sud) : x vers la droite, z vers le haut, le sud est près.
	assert_eq(MapView.uv_of("avant", Vector3(1, 2, 3)), Vector2(1, -3))
	assert_true(MapView.depth_of("avant", Vector3(0, 10, 0)) > MapView.depth_of("avant", Vector3(0, 2, 0)), "Avant : le sud est plus près")
	# Arrière : x vers la gauche.
	assert_eq(MapView.uv_of("arriere", Vector3(1, 2, 3)), Vector2(-1, -3))
	# Droite (caméra à l'est, regard vers l'ouest) : le nord à droite.
	assert_eq(MapView.uv_of("droite", Vector3(1, 2, 3)), Vector2(-2, -3))
	assert_true(MapView.depth_of("droite", Vector3(9, 0, 0)) > MapView.depth_of("droite", Vector3(1, 0, 0)), "Droite : l'est est plus près")
	assert_eq(MapView.uv_of("gauche", Vector3(1, 2, 3)), Vector2(2, -3))
	assert_true(MapView.depth_of("gauche", Vector3(1, 0, 0)) > MapView.depth_of("gauche", Vector3(9, 0, 0)), "Gauche : l'ouest est plus près")
	# Dessous : miroir de la vue du dessus, le bas est près.
	assert_eq(MapView.uv_of("dessous", Vector3(1, 2, 3)), Vector2(-1, 2))
	assert_true(MapView.depth_of("dessous", Vector3(0, 0, -1)) > MapView.depth_of("dessous", Vector3(0, 0, 5)), "Dessous : le bas est plus près")


func test_axis_letters_and_signs() -> void:
	assert_eq(MapView.h_axis("dessus"), ["X", 1])
	assert_eq(MapView.v_axis("dessus"), ["Y", -1])
	assert_eq(MapView.h_axis("avant"), ["X", 1])
	assert_eq(MapView.v_axis("avant"), ["Z", 1])
	assert_eq(MapView.h_axis("droite"), ["Y", -1], "Droite : règle en Y décroissant")
	assert_eq(MapView.h_axis("arriere"), ["X", -1])
	assert_eq(MapView.h_axis("gauche"), ["Y", 1])
	assert_eq(MapView.depth_axis("avant"), ["Y", 1])
	assert_eq(MapView.depth_axis("droite"), ["X", 1])
	assert_true(MapView.is_elevation("avant") and MapView.is_elevation("droite") and not MapView.is_elevation("dessus") and not MapView.is_elevation("dessous"))
	# Le sens de l'axe horizontal suit la projection : aller à droite fait
	# varier la vraie coordonnée du signe annoncé.
	for pl in MapView.PLANES:
		var a := MapView.point_of(pl, Vector2(0, 0), 0.0)
		var b := MapView.point_of(pl, Vector2(1, 0), 0.0)
		var d := b - a
		var axis := String(MapView.h_axis(pl)[0])
		var got: float = {"X": d.x, "Y": d.y, "Z": d.z}[axis]
		assert_near(got, float(MapView.h_axis(pl)[1]), 0.0001, "%s : axe horizontal %s" % [pl, axis])
		var up := MapView.point_of(pl, Vector2(0, -1), 0.0) - a
		var vaxis := String(MapView.v_axis(pl)[0])
		var vgot: float = {"X": up.x, "Y": up.y, "Z": up.z}[vaxis]
		assert_near(vgot, float(MapView.v_axis(pl)[1]), 0.0001, "%s : axe vertical %s" % [pl, vaxis])


func test_zoom_under_cursor_is_bounded() -> void:
	var v := MapView.new()
	v.size = Vector2(400, 300)
	v.zoom = 20.0
	v.origin = Vector2(50, 50)
	var px := Vector2(210, 130)
	var m := v.to_m(px)
	v._zoom_at(px, 1.5)
	assert_near(v.zoom, 30.0, 0.0001)
	assert_true(v.to_m(px).distance_to(m) < 0.0001, "le point sous le curseur ne bouge pas")
	for i in 40:
		v._zoom_at(px, 2.0)
	assert_near(v.zoom, MapView.MAX_ZOOM, 0.0001, "zoom borné")
	v.free()
