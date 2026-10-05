extends TestCase
## Grandeurs verticales et élévations de l'éditeur de cartes (MapVertical,
## MapElevationItems, MapElevation ; docs/EDITOR_VIEWS.md § 3.2) : hauteurs de
## tous les types sur DRAFT ARENA (double hauteur, passerelle, escalier,
## ouvertures, objets muraux), plafond sous la dalle de l'étage du dessus,
## même plafond que l'export en jeu, projection et choix au clic, coupe,
## étages montrés, cache par version de la carte, temps de dessin sur une
## carte de 50 pièces et 2000 objets.

const TMP := "res://tests/_out/test_map_vertical"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


static func _arena() -> EditorMap:
	return EditorMap.load_dir("res://assets/maps/draft_arena/")


static func _by_id(items: Array) -> Dictionary:
	var out := {}
	for it in items:
		out[String(it.id)] = it
	return out


func test_heights_on_draft_arena() -> void:
	var doc := _arena()
	var v := MapRaster.build(doc).v
	var it := _by_id(MapElevationItems.build(doc, v))
	# Entrepôt en double hauteur : jusqu'au plafond de l'étage 1 (3,50 + 3,30).
	assert_near(float(it.p3.z0), 0.0, 0.001)
	assert_near(float(it.p3.z1), 6.8, 0.001, "double hauteur")
	# Salle des machines : son plafond (rien au-dessus).
	assert_near(float(it.p1.z1), 3.2, 0.001)
	# Passerelle (étage 1) : de 3,50 au plafond de l'étage, avec sa dalle.
	assert_near(float(it.p5.z0), 3.5, 0.001)
	assert_near(float(it.p5.z1), 6.8, 0.001)
	assert_true(bool(it.p5.slab) and not bool(it.p1.slab), "dalle sous la passerelle seulement")
	# Escalier : d'un sol à l'autre.
	assert_eq(String(it.x2.kind), "stairs")
	assert_near(float(it.x2.z0), 0.0, 0.001)
	assert_near(float(it.x2.z1), 3.5, 0.001)
	# Pilier : jusqu'en haut de la double hauteur.
	assert_near(float(it.x1.z1), 6.8, 0.001, "pilier dans l'entrepôt")
	# Ouvertures : fenêtre de l'allège au linteau, porte de hauteur_portes.
	for o in doc.ouvertures:
		var e: Dictionary = it[String(o.id)]
		match String(o.type):
			"fenetre":
				assert_near(float(e.z1) - float(e.z0), MapValidator.LINTEL - MapValidator.SILL, 0.001, "fenêtre %s" % o.id)
				assert_near(float(e.z0) - EditorMap.alt_of(o), MapValidator.SILL, 0.001)
			"porte", "debris":
				assert_near(float(e.z1) - float(e.z0), 2.5, 0.001, "porte %s" % o.id)
				assert_eq(int(e.price), int(o.prix))
	# Objets muraux : tableau d'arme en hauteur, boîte au sol, sur leur étage.
	assert_near(float(it.w1.z0), 1.1, 0.001)
	assert_near(float(it.b3.z0), 3.5, 0.001, "boîte de la passerelle à l'étage 1")
	assert_eq(String(it.s1.kind), "fobj")


func test_ceiling_under_the_slab_of_the_floor_above() -> void:
	var doc := EditorMap.blank("dalle", "DALLE", "SLAB")
	var z := String(doc.add_zone("A", "A").id)
	# Pièce haute (4 m) sous une pièce de l'étage 1 : coupée sous sa dalle.
	doc.pieces.append({"id": "p1", "nom": "Bas", "altitude": 0, "zone": z, "plafond": 4.0, "contour": [[0, 0], [10, 0], [10, 8], [0, 8]]})
	doc.pieces.append({"id": "p2", "nom": "Haut", "altitude": 3.5, "plafond": 3.0, "zone": z, "contour": [[0, 0], [5, 0], [5, 8], [0, 8]]})
	var v := MapRaster.build(doc).v
	assert_near(MapVertical.ceil_z(v, 0, Vector2(2, 4)), 3.5 - MapVertical.DALLE, 0.001, "sous la pièce du dessus : dessous de la dalle")
	assert_near(MapVertical.ceil_z(v, 0, Vector2(8, 4)), 4.0, 0.001, "ailleurs : son plafond")
	var it := _by_id(MapElevationItems.build(doc, v))
	assert_near(float(it.p1.z1), 4.0, 0.001, "boîte jusqu'au plus haut de ses plafonds")
	# Même plafond que l'export en jeu.
	var ex := MapLayoutExport.new()
	ex.md = v
	ex.n_floors = v.floors.size()
	for c in [Vector2i(4, 8), Vector2i(16, 8)]:
		assert_eq(ex.ceil_at(0, c), MapVertical.ceil_at(v, 0, c))
	assert_near(ex.top(0), MapVertical.top(v, 0), 0.0001)


func test_lights_effects_and_decor_heights() -> void:
	var doc := _arena()
	doc.objets.append({"id": "fx1", "type": "effet", "effet": "torche", "altitude": 0, "position": [9.5, 4.5], "mur": "n", "hauteur": 2.4})
	doc.objets.append({"id": "lu1", "type": "luminaire", "luminaire": "suspension", "altitude": 0, "position": [10.0, 26.0], "rot": 0})
	doc.objets.append({"id": "lu2", "type": "luminaire", "luminaire": "applique", "altitude": 0, "position": [6.0, 21.5], "mur": "n", "hauteur": 2.2})
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [10.0, 28.0], "rot": 0})
	var v := MapRaster.build(doc).v
	var it := _by_id(MapElevationItems.build(doc, v))
	assert_near(float(it.fx1.z), 2.4, 0.001, "torche à sa hauteur")
	assert_true(is_nan(float(it.fx1.hook)), "effet mural : accroché au mur")
	assert_near(float(it.lu1.z), 3.2 - 0.7, 0.001, "suspension : sous le plafond (drop)")
	assert_near(float(it.lu1.hook), 3.2, 0.001)
	assert_near(float(it.lu2.z), 2.2, 0.001, "applique à sa hauteur")
	assert_near(float(it.d1.z0), 0.0, 0.001)
	assert_near(float(it.d1.z1), 1.5, 0.001, "pile de caisses : h du catalogue")


func test_projection_pick_and_cut() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed._reset(_arena())
	await wait_frames(2)
	assert_eq(ed.views.layout_id, "2v", "deux vues empilées par défaut")
	var av: MapElevation = ed.views.panes[1].view
	assert_eq(av.plane, "avant")
	var list := av.projected()
	assert_true(list.size() > 20, "boîtes projetées")
	for i in range(1, list.size()):
		assert_true(float(list[i - 1].near) <= float(list[i].near), "du plus lointain au plus proche")
	# Clic : la passerelle (plus petite que l'entrepôt qui la contient), l'atelier.
	assert_eq(String(av.element_at(Vector2(5.0, -5.0)).get("id", "")), "p5")
	# Avant : la caméra est au sud ; la salle des machines (y 21,5 → 33) est devant.
	assert_eq(String(av.element_at(Vector2(15.0, -0.5)).get("id", "")), "p1", "la pièce la plus au sud est devant")
	# Fenêtre du mur nord vue de face (le passage de l'atelier, plus proche, n'y est pas).
	assert_eq(String(av.element_at(Vector2(15.25, -1.5)).get("id", "")), "o6")
	assert_eq(String(av.element_at(Vector2(11.25, -1.5)).get("id", "")), "o4", "le passage, devant la fenêtre o5")
	# Coupe autour de l'atelier (caché derrière la salle des machines) : le
	# reste ne répond plus au clic.
	ed.select("p4")
	assert_true(av.cut_around_selection())
	assert_eq(av.coupe, [17.0, 21.5])
	assert_eq(String(av.element_at(Vector2(9.0, -0.5)).get("id", "")), "p4", "l'atelier, caché sans la coupe")
	assert_near(av.alpha_of(av.projected_of("p1")), MapElevation.OUT_OF_CUT, 0.001, "hors de la coupe : 15 %")
	av.set_cut([], "aucune")
	# Étages : l'étage courant seulement (0) : la passerelle n'est plus là.
	ed.set_floor(0)
	av.floors_mode = MapElevation.Floors.ONLY
	assert_eq(String(av.element_at(Vector2(5.0, -5.0)).get("id", "")), "p3")
	av.floors_mode = MapElevation.Floors.ALL
	# Cache : même version, même liste ; une modification la refait.
	var before := av.projected()
	assert_true(av.projected() == before, "pas de recalcul sans modification")
	ed.select("p5")
	assert_true(is_same(av.projected(), before), "la sélection ne refait pas la projection")
	ed.push_undo()
	ed.doc.find("p5")["plafond"] = 3.0
	ed.changed()
	assert_false(is_same(av.projected(), before), "modification : projection refaite")
	ed.queue_free()
	await wait_frames(1)


func test_draw_time_on_a_big_map() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	var doc := EditorMap.blank("grande", "GRANDE", "BIG")
	for row in 2:
		for col in 25:
			var x0 := 2.0 + col * 6.0
			var y0 := 4.0 + row * 6.0
			var z := doc.add_zone("S", "R")
			doc.pieces.append({"id": doc.new_id("p"), "nom": "S", "altitude": 0, "zone": String(z.id),
				"contour": [[x0, y0], [x0 + 6, y0], [x0 + 6, y0 + 6], [x0, y0 + 6]]})
	for i in 2000:
		@warning_ignore("integer_division")
		doc.objets.append({"id": doc.new_id("q"), "type": "apparition", "altitude": 0, "position": [3.0 + (i % 148), 5.0 + (i / 148) * 0.8]})
	ed._reset(doc)
	await wait_frames(3)
	var av: MapElevation = ed.views.panes[1].view
	av.frame_all()
	await wait_frames(2)
	av._proj_key = ""
	var t0 := Time.get_ticks_usec()
	var n := av.projected().size()
	var t_cache := (Time.get_ticks_usec() - t0) / 1000.0
	var worst := 0
	var total := 0
	for i in 10:
		av._layer_key = ""
		av.queue_redraw()
		await wait_frames(1)
		worst = maxi(worst, av.last_draw_us)
		total += av.last_draw_us
	print("    élévation, 50 pièces + 2000 objets : %d boîtes, projection %.1f ms, dessin %.2f ms en moyenne (pire %.2f ms)" % [n, t_cache, total / 10000.0, worst / 1000.0])
	assert_eq(n, 2050)
	# Objectif : 4 ms (§ 9) ; marge pour une machine chargée (tests en parallèle).
	assert_true(worst < 8000, "dessin d'une élévation : %.2f ms" % (worst / 1000.0))
	# Mouvement de la souris : le contenu n'est pas redessiné.
	var draws := av.content_draws
	for i in 5:
		var mm := InputEventMouseMotion.new()
		mm.position = Vector2(200 + i * 10, 150)
		av._gui_input(mm)
		await wait_frames(1)
	assert_eq(av.content_draws, draws, "survol : seul le dessus est redessiné")
	ed.queue_free()
	await wait_frames(1)
