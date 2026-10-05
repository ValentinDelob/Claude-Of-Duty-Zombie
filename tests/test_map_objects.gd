extends TestCase
## Objets de l'éditeur de cartes, format 5 (docs/MAP_OBJECTS.md) : variantes
## d'aspect (portes, débris, armes murales : catalogue, JSON aller-retour,
## valeur par défaut quand la clé manque, variante piégée refusée par
## CustomMapGuard, bon modèle construit par le jeu, touche V dans l'éditeur)
## et barrière invisible (catalogue, JSON, cases pleines pour le validateur,
## CollisionBox sur la couche BARRIER sans maillage en jeu, pavé translucide
## dans l'aperçu 3D, balles qui passent, corps arrêté, trajets qui la
## contournent).

const TMP := "res://tests/_out/test_map_objects"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ carte d'essai

static func _room(doc: EditorMap, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	var id := doc.new_id("p")
	var z := String(doc.add_zone("Salle " + id, "Room " + id).id)
	var r := {"id": id, "nom": "Salle " + id, "altitude": 0, "zone": z, "contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}
	doc.pieces.append(r)
	return r


## Trois salles : A (départ), B à l'est (porte en bois, barrière invisible),
## C au sud (débris en éboulement de béton) ; M14 sur une planche.
static func objects_map() -> EditorMap:
	var doc := EditorMap.blank("objets", "OBJETS", "OBJECTS")
	_room(doc, 0, 0, 14, 10)
	_room(doc, 14, 0, 24, 10)
	_room(doc, 0, 10, 14, 16)
	doc.depart = String(doc.zones[0].id)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": [14.0, 5.25], "largeur": 2.0, "prix": 750, "variante": "bois"})
	doc.ouvertures.append({"id": "o2", "type": "fenetre", "altitude": 0, "position": [3.25, 0.0]})
	doc.ouvertures.append({"id": "o3", "type": "fenetre", "altitude": 0, "position": [19.25, 0.0]})
	doc.ouvertures.append({"id": "o4", "type": "debris", "altitude": 0, "position": [3.75, 10.0], "largeur": 2.0, "prix": 1000, "variante": "gravats"})
	doc.ouvertures.append({"id": "o5", "type": "fenetre", "altitude": 0, "position": [7.25, 16.0]})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [9.0, 7.0]})
	doc.objets.append({"id": "b1", "type": "boite", "altitude": 0, "position": [9.75, 0.0], "mur": "n", "depart": false})
	doc.objets.append({"id": "w1", "type": "arme", "arme": "m14", "altitude": 0, "position": [11.25, 10.0], "mur": "s", "variante": "planche"})
	doc.objets.append({"id": "a1", "type": "atout", "atout": "titan", "altitude": 0, "position": [24.0, 5.0], "mur": "e"})
	doc.objets.append({"id": "i1", "type": "bloc_invisible", "altitude": 0, "rect": [16, 3, 17, 8]})
	return doc


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


static func _door_marker(variant: String, debris := false) -> MapMarker:
	var mk := MapMarker.new()
	mk.id = "t_" + variant
	mk.block = "door_" + mk.id
	mk.data = {"cost": 750, "width": 2.0, "height": 2.5, "depth": 0.75, "yaw": 0.0, "zones": ["a", "b"], "debris": debris, "variant": variant}
	return mk


# ------------------------------------------------------------------ catalogue

func test_catalog_variants_and_barrier_entry() -> void:
	assert_eq(MapCatalog.variants("porte"), ["blindee", "bois", "grille"], "trois portes")
	assert_true(MapCatalog.variants("debris").size() >= 2, "deux tas de débris")
	assert_true(MapCatalog.variants("arme").size() >= 2, "deux cadres d'arme murale")
	assert_eq(MapCatalog.default_variant("porte"), "blindee", "par défaut : la porte d'avant")
	# Format 8 : l'entrée des zombies a trois types (fenêtre d'avant par défaut).
	assert_eq(MapCatalog.variants("fenetre"), ["fenetre", "porte", "porte_double"], "fenêtre, porte simple, porte double")
	for t in MapCatalog.VARIANTS:
		for v in MapCatalog.VARIANTS[t]:
			assert_true(String(v[1]) != "" and String(v[2]) != "" and String(v[1]) != String(v[0]), "%s.%s : noms FR et EN" % [t, v[0]])
	assert_eq(MapCatalog.next_variant("porte", "grille"), "blindee", "V revient au premier aspect")
	var it := MapCatalog.item("bloc_invisible")
	assert_eq(String(it.get("tool", "")), "poly", "barrière : tracée en polygone (format 9)")
	assert_eq(String(it.get("cat", "")), "construction")
	assert_true(String(it.fr) != "" and String(it.en) != "" and String(it.hint_fr) != "" and String(it.hint_en) != "", "textes FR / EN")
	assert_eq(MapCatalog.item_for({"type": "bloc_invisible"}).get("id"), "bloc_invisible")
	var kinds := MapCatalog.allowed_kinds()
	assert_eq(kinds.porte.keys.variante.values, MapCatalog.variants("porte"), "variantes admises des portes")
	assert_eq(kinds.arme.keys.variante.values, MapCatalog.variants("arme"), "variantes admises des armes")
	assert_eq(kinds.fenetre.keys.variante.values, MapCatalog.variants("fenetre"), "types admis des entrées des zombies (format 8)")
	assert_true(kinds.has("bloc_invisible") and kinds.bloc_invisible.required == ["id", "type"], "barrière : type admis (sommets ou rect : CustomMapGuard)")
	assert_eq(kinds.bloc_invisible.keys.keys().filter(func(k): return not k in ["id", "type", "altitude"]), ["sommets", "rect", "rot", "hauteur"])


# ------------------------------------------------------------------ JSON

func test_variant_and_barrier_json_round_trip() -> void:
	assert_true(EditorMap.FORMAT >= 5, "format 5 et plus : variantes et barrière invisible (format %d)" % EditorMap.FORMAT)
	var doc := objects_map()
	doc.objets[-1]["rot"] = 30
	doc.objets[-1]["hauteur"] = 2.5
	var texts := doc.file_texts()
	assert_true(String(texts["ouvertures.json"]).contains("\"variante\":\"bois\""), "variante écrite")
	var back := EditorMap.from_texts(texts)
	assert_eq(back.load_errors, [], "relue sans erreur")
	# Format 9 : la barrière rectangle d'avant est relue comme le polygone de
	# ses 4 coins (même place) ; ensuite le fichier se relit à l'identique.
	var again := back.file_texts()
	assert_eq(EditorMap.from_texts(again).file_texts(), again, "relue puis réécrite à l'identique")
	assert_eq(texts["ouvertures.json"], again["ouvertures.json"], "ouvertures inchangées")
	assert_eq(MapCatalog.variant_of(back.find("o1")), "bois")
	assert_eq(MapCatalog.variant_of(back.find("o4")), "gravats")
	assert_eq(MapCatalog.variant_of(back.find("w1")), "planche")
	var clip := back.find("i1")
	assert_false(clip.has("rect") or clip.has("rot"), "rect et rot remplacés par les sommets")
	var want := MapGeom.rot_rect_poly(Vector2(16.5, 5.5), Vector2(1, 5), 30)
	var got := MapGeom.poly(clip.sommets)
	assert_eq(got.size(), 4, "4 sommets")
	for i in 4:
		assert_true(got[i].distance_to(want[i]) < 0.002, "coin %d à sa place (%s / %s)" % [i, got[i], want[i]])
	assert_near(float(clip.hauteur), 2.5, 0.0001)
	# Aspect par défaut : la clé disparaît (fichier identique à une carte d'avant).
	var door := back.find("o1")
	assert_true(MapCatalog.set_variant(door, "blindee"))
	assert_false(door.has("variante"), "aspect par défaut : pas de clé")
	assert_false(MapCatalog.set_variant(door, "gravats"), "variante d'un autre type refusée")
	assert_eq(MapCatalog.variant_of({"type": "porte"}), "blindee", "clé absente : aspect par défaut")


func test_old_maps_keep_their_look() -> void:
	# Carte au format 4 sans variante : lue telle quelle, aucun nouvel attribut.
	var doc := objects_map()
	for o in doc.ouvertures + doc.objets:
		o.erase("variante")
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	var texts := doc.file_texts()
	texts = load("res://tests/test_levels_migration.gd").as_format(texts, 4)
	var m := EditorMap.from_texts(texts)
	assert_eq(m.load_errors, [], "format 4 lu sans erreur")
	assert_eq(m.format_read, 4)
	for o in m.ouvertures + m.objets:
		assert_false(o.has("variante"), "%s : pas de variante ajoutée" % o.id)
	var def := EditorMapDef.from_map(m, "perso:objets")
	assert_true(def.is_valid(), _errs(def.validator))
	for d in def.layout_data.markers.doors:
		assert_false(d.has("variant"), "porte %s : description inchangée" % d.id)
	for w in def.layout_data.markers.wall_buys:
		assert_false(w.has("variant"), "arme %s : description inchangée" % w.id)
	assert_false(def.layout_data.blockers.any(func(b): return b.has("clip")), "aucune barrière")
	# Fichier écrit à la main avec une variante inconnue : aspect par défaut.
	var hand := doc.file_texts()
	hand["ouvertures.json"] = String(hand["ouvertures.json"]).replace("\"id\":\"o1\"", "\"id\":\"o1\",\"variante\":\"titane\"")
	var hm := EditorMap.from_texts(hand)
	assert_false(hm.find("o1").has("variante"), "variante inconnue retirée à la lecture")


func test_guard_accepts_variants_and_refuses_bad_values() -> void:
	var texts := objects_map().file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte avec variantes et barrière acceptée")
	assert_true(bool(CustomMapGuard.check_full(texts).get("ok", false)), "et jouable")
	var bad_cases := [
		["ouvertures.json", "\"variante\":\"bois\"", "\"variante\":\"titane\"", "variante inconnue"],
		["ouvertures.json", "\"variante\":\"bois\"", "\"variante\":\"planche\"", "variante d'un autre type"],
		["ouvertures.json", "\"variante\":\"bois\"", "\"variante\":3", "variante qui n'est pas un texte"],
		["ouvertures.json", "\"variante\":\"bois\"", "\"variante\":\"res://icon.svg\"", "chemin de ressource"],
		["ouvertures.json", "\"id\":\"o2\"", "\"id\":\"o2\",\"variante\":\"bois\"", "variante sur une fenêtre"],
		["objets.json", "\"rect\":[16,3,17,8]", "\"rect\":[16,3,17,8],\"hauteur\":100", "barrière trop haute"],
		["objets.json", "\"rect\":[16,3,17,8]", "\"rect\":[16,3,17,8],\"hauteur\":\"x\"", "hauteur texte"],
		["objets.json", "\"rect\":[16,3,17,8]", "\"rect\":[16,3,17,8],\"modele\":\"res://x.tscn\"", "clé inconnue sur la barrière"],
		["objets.json", "\"rect\":[16,3,17,8]", "\"position\":[16,3]", "barrière sans rect"],
	]
	for bc in bad_cases:
		var t := texts.duplicate()
		var src := String(t[bc[0]])
		assert_true(src.contains(bc[1]), "cas %s préparé" % bc[3])
		t[bc[0]] = src.replace(bc[1], bc[2])
		var r := CustomMapGuard.check_texts(t)
		assert_false(r.reasons.is_empty(), "refusée : %s" % bc[3])


# ------------------------------------------------------------------ validateur

func test_barrier_cells_are_solid_for_the_validator() -> void:
	var one := MapRaster.clip_cells({"rect": [5, 5, 5.5, 8]})
	assert_eq(one.size(), 6, "barrière de 0,5 × 3 m : une rangée de 6 cases (%s)" % str(one))
	assert_eq(MapRaster.clip_cells({"rect": [9, 9.5, 11.5, 12]}).size(), 25, "2,5 × 2,5 m : 25 cases")
	var turned := MapRaster.clip_cells({"rect": [4, 4, 6, 6], "rot": 45}).size()
	assert_true(turned >= 12 and turned <= 20, "carré de 2 m tourné de 45° : environ 16 cases (%d)" % turned)
	var doc := objects_map()
	var r := MapRaster.build(doc)
	var v := r.v
	v.analyze()
	assert_eq(v.errors().size(), 0, "carte d'essai valide :\n" + _errs(v))
	var f := v.floors[0]
	for c in MapRaster.clip_cells(doc.find("i1")):
		assert_eq(f.at(c), MapValidator.K.MUR, "case %s pleine" % c)
		assert_eq(f.key_at(c), "decor#i1")
	assert_eq(v.clips.size(), 1)
	assert_eq(v.variants, {"o1": "bois", "o4": "gravats", "w1": "planche"}, "variantes transmises")
	# Barrière d'un mur à l'autre de la salle B : l'est de B (fenêtre, atout)
	# n'est plus accessible à pied, comme derrière un mur.
	var cut := objects_map()
	cut.find("i1")["rect"] = [17, 0, 17.5, 10]
	var vc := _check(cut)
	assert_false(vc.errors().is_empty(), "barrière qui coupe la salle : signalée par le validateur")
	# Règles de pose (format 9) : n'importe où, même dehors ou sur un objet.
	assert_true(MapRules.check_rect(doc, 0, "bloc_invisible", Rect2(20, 2, 0.5, 3)).ok, "0,5 m d'épaisseur accepté")
	assert_false(MapRules.check_rect(doc, 0, "pilier", Rect2(20, 2, 0.5, 3)).ok, "un pilier garde 1 m au moins")
	assert_true(MapRules.check_rect(doc, 0, "bloc_invisible", Rect2(30, 2, 1, 1)).ok, "hors d'une pièce accepté")
	assert_true(MapRules.check_rect(doc, 0, "bloc_invisible", Rect2(16.5, 4, 1, 1)).ok, "par-dessus une autre barrière accepté")


# ------------------------------------------------------------------ jeu

func test_game_builds_each_variant() -> void:
	var def := EditorMapDef.from_map(objects_map(), "perso:objets")
	assert_true(def.is_valid(), _errs(def.validator))
	var data := def.layout_data
	var doors: Array = data.markers.doors
	assert_eq(doors.filter(func(d): return d.get("variant", "") == "bois").size(), 1, "porte en bois décrite")
	assert_eq(doors.filter(func(d): return d.get("variant", "") == "gravats" and d.get("debris", false)).size(), 1, "éboulement décrit")
	assert_eq(String(data.markers.wall_buys[0].get("variant", "")), "planche", "M14 sur une planche")
	var layout := MeshMapLayout.new(def, data, "")
	var looks := {}
	for mk in layout.doors():
		var d := Door.new()
		d.setup_marker(mk)
		host.add_child(d)
		looks[String(d.look())] = true
		d.queue_free()
	assert_eq(looks, {"bois": true, "gravats": true}, "le jeu construit la porte en bois et l'éboulement")
	# Chaque aspect : son propre modèle, sous le même battant « Slab ».
	var shapes := {}
	for spec in [["", false], ["blindee", false], ["bois", false], ["grille", false], ["inconnu", false], ["", true], ["gravats", true]]:
		var d := Door.new()
		d.setup_marker(_door_marker(spec[0], spec[1]))
		host.add_child(d)
		var slab := d.get_node("Slab")
		var meshes := slab.find_children("*", "MeshInstance3D", true, false)
		var cyl := meshes.filter(func(n): return n.mesh is CylinderMesh).size()
		var wood := meshes.filter(func(n): return n.material_override == WorldLook.surface("wood") or n.material_override == WorldLook.surface("dark_wood")).size()
		var concrete := meshes.filter(func(n): return n.material_override == WorldLook.surface("concrete_dark")).size()
		shapes["%s|%s" % spec] = [d.look(), meshes.size(), cyl, wood, concrete]
		assert_true(d.get_children().any(func(n): return n is StaticBody3D), "collision de la porte (%s)" % spec[0])
		d.queue_free()
	assert_eq(shapes["|false"][0], "blindee", "sans variante : porte blindée")
	assert_eq(shapes["|false"], shapes["blindee|false"], "clé absente = porte blindée à l'identique")
	assert_eq(shapes["inconnu|false"], shapes["|false"], "variante inconnue : porte blindée")
	assert_true(shapes["bois|false"][3] >= 7 and shapes["bois|false"][2] == 0, "porte en bois : planches, traverses (%s)" % str(shapes["bois|false"]))
	assert_true(shapes["grille|false"][2] >= 8, "grille : barreaux (%s)" % str(shapes["grille|false"]))
	assert_eq(shapes["|true"][0], "planches", "débris par défaut : planches")
	assert_true(shapes["gravats|true"][4] >= 2 and shapes["gravats|true"][2] >= 3, "éboulement : béton et fers (%s)" % str(shapes["gravats|true"]))
	assert_true(shapes["|true"][2] == 0, "débris par défaut sans fers à béton")
	# Arme murale : planche derrière la craie, craie seule par défaut.
	var wms := layout.wall_buys()
	var wb := WallBuy.new()
	wb.setup_marker(wms[0], "m14")
	host.add_child(wb)
	assert_true(wb.get_node_or_null("Board") != null and wb.get_node_or_null("Chalk") != null, "craie sur une planche")
	var plain := WallBuy.new()
	var mk := MapMarker.new()
	mk.id = "m14_plain"
	mk.data = {"weapon": "m14"}
	plain.setup_marker(mk, "m14")
	host.add_child(plain)
	assert_true(plain.get_node_or_null("Board") == null and plain.get_node_or_null("Chalk") != null, "par défaut : craie seule")
	wb.queue_free()
	plain.queue_free()
	await wait_frames(1)


func test_barrier_is_an_invisible_collision_box() -> void:
	var def := EditorMapDef.from_map(objects_map(), "perso:objets")
	var data := def.layout_data
	var clips: Array = data.blockers.filter(func(b): return b.get("clip", false))
	assert_eq(clips.size(), 1, "une barrière décrite")
	var cl: Dictionary = clips[0]
	var off := MapGeom.WORLD_OFFSET
	assert_true(bool(cl.barrier), "couche BARRIER")
	assert_near(float(cl.center[0]), 16.5 + off, 0.001)
	assert_near(float(cl.center[2]), 5.5 + off, 0.001)
	assert_near(float(cl.size[0]), 1.0, 0.001)
	assert_near(float(cl.size[2]), 5.0, 0.001)
	assert_near(float(cl.size[1]), EditorMap.DEFAULT_CEILING, 0.001, "du sol au plafond")
	# En jeu : une CollisionBox sur la couche BARRIER, sans aucun maillage.
	var world := Node3D.new()
	host.add_child(world)
	var mb := MeshMapBuilder.new(data, "")
	mb.build(world)
	var boxes := world.find_children("*", "CollisionBox", true, false).filter(func(b): return absf(b.global_position.x - (16.5 + off)) < 0.01 and absf(b.global_position.z - (5.5 + off)) < 0.01)
	assert_eq(boxes.size(), 1, "CollisionBox de la barrière")
	await wait_frames(1)
	if boxes.size() == 1:
		var b: CollisionBox = boxes[0]
		assert_eq(b.collision_layer, Barricade.BARRIER_LAYER, "joueurs et zombies seulement")
		assert_false(b.find_children("*", "MeshInstance3D", true, false).size() > 0, "aucun maillage")
	assert_eq(world.find_children("ClipView*", "", true, false).size(), 0, "rien de visible en jeu")
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var from := Vector3(off + 15, 1.2, off + 5.5)
	var to := Vector3(off + 19, 1.2, off + 5.5)
	var bullet := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	assert_true(bullet.is_empty(), "les balles (couche 1) passent : %s" % str(bullet.get("collider", "")))
	var walker := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | Barricade.BARRIER_LAYER))
	assert_true(not walker.is_empty() and walker.collider is CollisionBox, "arrêt pour ce qui marche (joueurs, zombies)")
	var grenade := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Throwable.FLIGHT_MASK))
	assert_true(grenade.is_empty(), "les grenades passent")
	# Un corps (masque du joueur) poussé contre la barrière ne la traverse pas.
	var body := CharacterBody3D.new()
	body.collision_mask = 1 | Barricade.BARRIER_LAYER
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.95
	body.add_child(cs)
	world.add_child(body)
	body.global_position = Vector3(off + 14.9, 0.05, off + 5.5)
	await host.get_tree().physics_frame
	for i in 50:
		body.move_and_collide(Vector3(0.1, 0, 0))
	assert_true(body.global_position.x < off + 16.0 - 0.35, "le corps bute sur la barrière (x = %.2f)" % (body.global_position.x - off))
	# Aperçu 3D : un pavé translucide montrable (option), à la même place.
	var pv := Node3D.new()
	host.add_child(pv)
	var pb := MapPreviewBuilder.new(data)
	pb.build_decor(pv)
	var views := pv.find_children("ClipView_*", "MeshInstance3D", true, false)
	assert_eq(views.size(), 1, "pavé de la barrière dans l'aperçu")
	if views.size() == 1:
		assert_near((views[0] as Node3D).global_position.x, 16.5 + off, 0.01)
	pv.queue_free()
	world.queue_free()
	await wait_frames(1)


func test_navigation_goes_around_the_barrier() -> void:
	var def := EditorMapDef.from_map(objects_map(), "perso:objets")
	var world := Node3D.new()
	host.add_child(world)
	MeshMapBuilder.new(def.layout_data, "").build(world)
	await host.get_tree().physics_frame
	var nav := MeshNav.new()
	nav.setup(world)
	nav.bake()
	for i in 20:
		await host.get_tree().process_frame
	NavigationServer3D.map_force_update(nav.map)
	var off := MapGeom.WORLD_OFFSET
	var bar := Rect2(16, 3, 1, 5)
	var path := nav.find_path(Vector3(off + 15, 0, off + 5.5), Vector3(off + 19, 0, off + 5.5))
	assert_true(path.size() >= 3, "chemin trouvé avec un détour (%d points)" % path.size())
	var detour := false
	for i in path.size():
		var p := Vector2(path[i].x, path[i].z) - Vector2.ONE * off
		assert_false(bar.grow(0.2).has_point(p), "point du chemin dans la barrière : %s" % p)
		detour = detour or p.y < 3.0 or p.y > 8.0
		if i + 1 < path.size():
			var q := Vector2(path[i + 1].x, path[i + 1].z) - Vector2.ONE * off
			for e in [[bar.position, Vector2(bar.end.x, bar.position.y)], [Vector2(bar.end.x, bar.position.y), bar.end],
					[bar.end, Vector2(bar.position.x, bar.end.y)], [Vector2(bar.position.x, bar.end.y), bar.position]]:
				assert_true(Geometry2D.segment_intersects_segment(p, q, e[0], e[1]) == null, "le chemin traverse la barrière entre %s et %s" % [p, q])
	assert_true(detour, "le chemin passe au nord ou au sud de la barrière")
	nav.region.queue_free()
	world.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ éditeur

func test_v_key_cycles_the_look_in_the_editor() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	ed._reset(objects_map())
	var door := ed.doc.find("o1")
	MapCatalog.set_variant(door, "blindee")
	ed.select("o1")
	var key := func(code: Key) -> void:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = true
		ed._input(e)
	key.call(KEY_V)
	assert_eq(MapCatalog.variant_of(ed.doc.find("o1")), "bois", "V : porte en bois")
	key.call(KEY_V)
	assert_eq(MapCatalog.variant_of(ed.doc.find("o1")), "grille", "V : grille")
	key.call(KEY_V)
	assert_false(ed.doc.find("o1").has("variante"), "V : retour à la porte blindée (clé retirée)")
	ed.undo()
	assert_eq(MapCatalog.variant_of(ed.doc.find("o1")), "grille", "Ctrl+Z : aspect précédent")
	# Objet tenu : V choisit l'aspect avant de poser.
	var slot := MapCatalog.DEFAULT_HOTBAR.find("porte")
	ed.select_slot(slot)
	key.call(KEY_V)
	assert_eq(ed.place_variant, "bois", "porte tenue : en bois")
	ed.canvas.mouse_m = Vector2(14.0, 2.75)
	ed.canvas._update_preview()
	assert_eq(MapCatalog.variant_of(ed.canvas.preview.get("obj", {})), "bois", "l'aperçu de pose porte la variante")
	ed.select_mouse()
	assert_eq(ed.place_variant, "", "changer d'objet : aspect par défaut")
	# Barrière invisible tracée en polygone (format 9 ; 0,5 m d'épaisseur).
	var res: Dictionary = ed.canvas._poly_creation(MapCatalog.item("bloc_invisible"),
		PackedVector2Array([Vector2(20, 2), Vector2(20.5, 2), Vector2(20.5, 6), Vector2(20, 6)]))
	assert_true(res.ok, "barrière de 0,5 m acceptée : %s" % MapRules.why(res))
	var o := ed.add_object(res.obj, 0)
	assert_true(String(o.id).begins_with("i"), "identifiant i… (%s)" % o.id)
	assert_eq(String(o.type), "bloc_invisible")
	ed.queue_free()
	await wait_frames(1)
