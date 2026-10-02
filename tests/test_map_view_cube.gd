extends TestCase
## ViewCube de l'éditeur de cartes (MapViewCube, docs/EDITOR_VIEWS.md § 4) :
## les 26 cibles d'un cube (6 faces, 12 arêtes, 8 coins) et leurs directions,
## voisins de chaque face dans le net (cohérents avec les axes de la vue),
## détection au pixel (faces, coins, maison, flèches, menu), tour des
## façades, cube isométrique (faces visibles), clic sur une face : bascule de
## la fenêtre, maison : vue d'origine, pavé numérique quand la souris est sur
## une vue (et barre rapide sinon).

const TMP := "res://tests/_out/test_map_view_cube"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


func test_26_targets_and_directions() -> void:
	var t := MapViewCube.all_targets()
	assert_eq(t.size(), 26)
	assert_eq(t.keys().filter(func(k): return String(k).begins_with("f:")).size(), 6)
	assert_eq(t.keys().filter(func(k): return String(k).begins_with("e:")).size(), 12)
	assert_eq(t.keys().filter(func(k): return String(k).begins_with("c:")).size(), 8)
	for id in t:
		assert_near((t[id] as Vector3).length(), 1.0, 0.0001, String(id))
	assert_eq(MapViewCube.target_dir("f:avant"), Vector3(0, 1, 0), "Avant : caméra au sud")
	assert_true(MapViewCube.target_dir("c:avant+droite+dessus").is_equal_approx(Vector3(1, 1, 1).normalized()), "coin avant-droite-dessus")
	assert_true(t.has("e:avant+droite") and t.has("e:arriere+dessus"))


func test_net_neighbours_match_the_view_axes() -> void:
	# La bande de droite du net est la face que l'on voit en tournant vers la
	# droite de l'écran : sa direction = l'axe horizontal de la vue.
	for pl in MapView.PLANES:
		var n: Array = MapViewCube.NEIGH[pl]
		var right_dir: Vector3 = MapViewCube.FACE_DIR[n[3]]
		var a := MapView.point_of(pl, Vector2(0, 0), 0.0)
		var b := MapView.point_of(pl, Vector2(1, 0), 0.0)
		assert_true((b - a).is_equal_approx(right_dir), "%s : bande de droite = %s" % [pl, n[3]])
		var up := MapView.point_of(pl, Vector2(0, -1), 0.0) - a
		assert_true(up.is_equal_approx(MapViewCube.FACE_DIR[n[0]]), "%s : bande du haut = %s" % [pl, n[0]])
	assert_eq(MapViewCube.net_corner("avant", 1), "c:avant+droite+dessus")
	assert_eq(MapViewCube.next_facade("avant", 1), "droite")
	assert_eq(MapViewCube.next_facade("gauche", 1), "avant")
	assert_eq(MapViewCube.next_facade("avant", -1), "gauche")
	assert_eq(MapViewCube.next_facade("dessus", 1), "dessus")


func test_pixel_detection() -> void:
	var c := MapViewCube.new()
	c.size = c.wanted_size()
	c.plane = "avant"
	var shapes := c.net_shapes()
	for sh in shapes:
		var p: PackedVector2Array = sh.poly
		var mid := (p[0] + p[2]) * 0.5
		if String(sh.id) == "cur":
			assert_eq(c.target_at(mid), "cur")
		elif bool(sh.get("corner", false)):
			assert_eq(c.target_at(mid), String(sh.id), "coin %s" % sh.id)
	# Bandes : au milieu de chaque bande.
	var o := c._net_origin()
	var s := MapViewCube.S * EditorUi.factor()
	var d := MapViewCube.D * EditorUi.factor()
	assert_eq(c.target_at(o + Vector2(d + s * 0.5, d * 0.5)), "f:dessus", "bande du haut")
	assert_eq(c.target_at(o + Vector2(d + s * 0.5, d * 1.5 + s)), "f:dessous", "bande du bas")
	assert_eq(c.target_at(o + Vector2(d * 0.5, d + s * 0.5)), "f:gauche", "bande de gauche")
	assert_eq(c.target_at(o + Vector2(d * 1.5 + s, d + s * 0.5)), "f:droite", "bande de droite")
	assert_eq(c.target_at(Vector2(-50, -50)), "", "hors du cube")
	assert_true(shapes.any(func(sh): return sh.id == "next"), "flèches de façade en vue de côté")
	c.plane = "dessus"
	assert_false(c.net_shapes().any(func(sh): return sh.id == "next"), "pas de flèches en vue Dessus")
	c.free()


func test_iso_cube_shows_three_faces() -> void:
	var c := MapViewCube.new()
	c.size = Vector2(120, 100)
	c.plane = "3d"
	c.set_view_dir(Vector3(1, 1, 1))
	var faces := c.iso_shapes().filter(func(sh): return String(sh.id).begins_with("f:")).map(func(sh): return String(sh.id))
	faces.sort()
	assert_eq(faces, ["f:avant", "f:dessus", "f:droite"], "caméra avant-droite-dessus : trois faces")
	var corner := c.iso_shapes().filter(func(sh): return String(sh.id) == "c:avant+droite+dessus")
	assert_eq(corner.size(), 1)
	assert_eq(c.target_at(corner[0].pt), "c:avant+droite+dessus", "coin le plus proche cliquable")
	c.set_view_dir(Vector3(-1, -1, 0.5))
	faces = c.iso_shapes().filter(func(sh): return String(sh.id).begins_with("f:")).map(func(sh): return String(sh.id))
	faces.sort()
	assert_eq(faces, ["f:arriere", "f:dessus", "f:gauche"], "le cube suit la caméra")
	c.free()


func test_cube_actions_in_the_editor() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed._reset(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	await wait_frames(2)
	var pn: MapViewPane = ed.views.panes[1]
	assert_eq(pn.plane(), "avant")
	ed.views.cube_action(pn.view, "f:droite")
	await wait_frames(2)
	assert_eq(pn.plane(), "droite", "face Droite : la fenêtre passe en vue Droite")
	ed.views.cube_action(pn.view, "next")
	assert_eq(pn.plane(), "arriere", "► : façade suivante")
	ed.views.cube_action(pn.view, "home")
	assert_eq(pn.plane(), "avant", "maison : vue d'origine de la fenêtre")
	# Face Dessus depuis la fenêtre du bas : la vue Dessus (unique) change de fenêtre.
	ed.views.cube_action(pn.view, "f:dessus")
	assert_eq(pn.plane(), "dessus")
	assert_eq(ed.views.panes[0].plane(), "avant", "échange avec la fenêtre qui l'avait")
	ed.views.cube_action(pn.view, "home")
	# Coin : l'aperçu 3D vu de ce coin.
	ed.views.cube_action(ed.views.panes[1].view, "c:avant+droite+dessus")
	await wait_frames(2)
	assert_true(ed.preview.shown, "coin : la 3D s'affiche")
	var f := ed.preview.world.rig.forward()
	assert_true(f.x < -0.3 and f.y < -0.3 and f.z < -0.3, "caméra vue de l'avant-droite-dessus (regard %s)" % f)
	ed.preview.set_shown(false)
	ed.queue_free()
	await wait_frames(1)


func test_numpad_goes_to_the_view_under_the_mouse() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed._reset(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	await wait_frames(2)
	var pn: MapViewPane = ed.views.panes[1]
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_KP_3
	# Souris sur la fenêtre du bas : vue Droite.
	assert_true(ed.views.numpad(k, pn), "pavé 3 sur une vue")
	assert_eq(pn.plane(), "droite")
	k.ctrl_pressed = true
	assert_true(ed.views.numpad(k, pn))
	assert_eq(pn.plane(), "gauche", "Ctrl + pavé 3 : la vue opposée")
	# Souris sur aucune vue : la barre rapide garde le pavé.
	k.ctrl_pressed = false
	assert_false(ed.views.numpad(k, null), "hors des vues : pas pris")
	ed.queue_free()
	await wait_frames(1)
