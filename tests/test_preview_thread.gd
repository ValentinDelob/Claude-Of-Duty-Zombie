extends TestCase
## Fil de travail de l'APERÇU 3D (MapPreviewWorld.compute, lancé dans un
## Thread) : aucun état partagé modifiable touché (ThreadGuard, docs/
## ARCHITECTURE.md « Fils de travail »). Sur une carte complète (lampes,
## luminaire posé sur un meuble, décor tourné, formes libres, murs en biais,
## mur courbe, objets muraux, pièges, étage et escalier) : le calcul dans un
## fil ne note aucun accès refusé et donne exactement la même description que
## sur le fil principal ; les caches statiques du fil principal refusent tout
## accès depuis un fil ; le catalogue est figé (lecture seule) ; la copie de
## la carte donnée au fil est profonde (aucun objet partagé) ; la langue du
## calcul est celle figée au lancement.

@warning_ignore("unused_private_class_variable")
var _res: Variant
var _probe: Array = []


# ------------------------------------------------------------------ carte complète

static func _room(doc: EditorMap, pts: Array, k := 0, extra := {}) -> Dictionary:
	var z := doc.add_zone("Salle %d" % (doc.pieces.size() + 1), "Room %d" % (doc.pieces.size() + 1))
	var r := {"id": doc.new_id("p"), "nom": "Salle %d" % (doc.pieces.size() + 1), "etage": k, "zone": String(z.id), "contour": pts}
	r.merge(extra)
	doc.pieces.append(r)
	return r


static func _add(doc: EditorMap, list: Array, o: Dictionary, prefix: String, k := 0) -> Dictionary:
	o["id"] = doc.new_id(prefix)
	o["etage"] = k
	list.append(o)
	return o


## Ouverture posée par les règles de l'éditeur près de `mouse` ({} : refusée).
static func put_opening(doc: EditorMap, type: String, mouse: Vector2, width := 2.0, k := 0) -> Dictionary:
	var r := MapRules.place_opening(doc, k, type, mouse, width, "", true)
	if not r.ok:
		return {}
	var o := {"type": type, "position": r.position}
	if type != "fenetre":
		o["largeur"] = float(r.get("largeur", width))
	if type in ["porte", "debris"]:
		o["prix"] = 750
	return _add(doc, doc.ouvertures, o, "o", k)


## Objet de l'inventaire posé par les règles (contre un mur ou au sol).
static func put_item(doc: EditorMap, item_id: String, mouse: Vector2, rot := 0, k := 0) -> Dictionary:
	var it := MapCatalog.item(item_id)
	var o: Dictionary = it.make.duplicate(true)
	if rot != 0:
		o["rot"] = rot
	var r := {}
	if it.get("wall_snap", false):
		# Boîte mystère (format 15) : au sol, ou collée au mur proche.
		r = MapRules.place_box(doc, k, o, mouse)
		if not r.ok:
			return {}
		MapRules.apply_box(o, r)
		return _add(doc, doc.objets, o, "x", k)
	if String(it.tool) == "wall_item":
		r = MapRules.place_wall_item(doc, k, o, mouse)
		if r.ok:
			MapRules.apply_wall(o, r)
	else:
		r = MapRules.place_floor_item(doc, k, o, mouse, "", false)
	if not r.ok:
		return {}
	o["position"] = r.position
	return _add(doc, doc.objets, o, "x", k)


## Carte complète pour les tests du fil de travail et le scénario de
## contrainte (map_preview_stress) : pièces de la grille, pièce en biais,
## pièce ronde (forme libre), étage avec escalier, portes, passages, fenêtres
## (dont une sur un mur en biais), objets muraux (dont un contre le mur en
## biais), luminaires (plafond, applique, lampe de bureau posée sur le
## bureau), décor tourné au degré près, caisse, baril, lampe, pilier tourné,
## mur libre en biais, mur courbe, piège et levier.
static func rich_map() -> EditorMap:
	var doc := EditorMap.blank("stress_apercu", "STRESS APERÇU", "PREVIEW STRESS")
	doc.carte["lampes_auto"] = false
	doc.carte["etages"] = [{"sol": 0.0, "hauteur": 3.2}, {"sol": 3.5, "hauteur": 3.2}]
	var a := _room(doc, [[0, 0], [15, 0], [15, 10], [0, 10]])
	_room(doc, [[15, 0], [25, 0], [25, 10], [15, 10]])
	_room(doc, [[0, 10], [15, 10], [15, 20], [0, 20]])
	# Pièce en biais (côté oblique au nord-est), collée à B.
	_room(doc, [[25, 0], [33, 0], [37, 4], [37, 10], [25, 10]])
	# Pièce ronde (forme libre, octogone : tous ses côtés en biais), collée à
	# rien : dessinée quand même.
	var forme := {"type": "cercle", "centre": [48.0, 8.0], "rx": 5.0, "points": 8, "angle": 0}
	_room(doc, MapGeom.poly_arr(MapShapes.outline(forme)), 0, {"forme": forme})
	# Étage : une salle au-dessus de C, escalier dans C.
	_room(doc, [[0, 10], [15, 10], [15, 20], [0, 20]], 1)
	doc.depart = String(a.zone)
	put_opening(doc, "passage", Vector2(15, 5))
	put_opening(doc, "porte", Vector2(7, 10))
	put_opening(doc, "debris", Vector2(25, 5))
	for m in [Vector2(3, -0.3), Vector2(20, -0.3), Vector2(5, 20.3), Vector2(52.6, 9.9)]:
		put_opening(doc, "fenetre", m)
	_add(doc, doc.objets, {"type": "depart", "position": [9.0, 7.0]}, "s")
	put_item(doc, "arme:m14", Vector2(0.6, 5))
	put_item(doc, "atout:titan", Vector2(24.4, 3))
	put_item(doc, "boite", Vector2(0.6, 15))
	put_item(doc, "courant", Vector2(20, 9.4))
	put_item(doc, "pap", Vector2(34.4, 2.8))   # contre le mur en biais
	put_item(doc, "luminaire:suspension", Vector2(4, 4))
	put_item(doc, "luminaire:neon", Vector2(30, 6))
	put_item(doc, "luminaire:applique", Vector2(23, 0.6))
	put_item(doc, "lampe", Vector2(22, 6))
	# Bureau et sa lampe posée dessus (MapRules.support_under dans le fil).
	_add(doc, doc.objets, {"type": "prefab", "prefab": "bureau", "position": [10.5, 15.0], "rot": 0}, "d")
	put_item(doc, "luminaire:lampe_bureau", Vector2(10.5, 15.0))
	put_item(doc, "prefab:caisses", Vector2(19, 5), 37)
	put_item(doc, "prefab:gravats", Vector2(31, 7), 0)
	put_item(doc, "caisse", Vector2(12, 3))
	put_item(doc, "baril", Vector2(13, 7))
	_add(doc, doc.objets, {"type": "pilier", "rect": [3.0, 13.0, 5.0, 15.0], "rot": 30}, "x")
	_add(doc, doc.objets, {"type": "mur", "a": [16.5, 2.0], "b": [19.0, 4.5], "epaisseur": 0.5}, "m")
	_add(doc, doc.objets, {"type": "mur_courbe", "centre": [48.0, 8.0], "rayon": 2.5, "debut": 0.0, "ouverture": 120.0, "segments": 8, "epaisseur": 0.5}, "m")
	_add(doc, doc.objets, {"type": "escalier", "rect": [10.0, 16.0, 14.0, 19.5], "monte": "n"}, "e")
	_add(doc, doc.objets, {"type": "piege", "rect": [2.0, 2.0, 4.0, 4.0], "rot": 20}, "t")
	put_item(doc, "levier", Vector2(0.6, 2.5))
	return doc


# ------------------------------------------------------------------ outils

func _in_thread(c: Callable) -> Variant:
	var t := Thread.new()
	t.start(c)
	return t.wait_to_finish()


## Copie « simple » : seulement des données (aucun objet, donc rien de partagé
## par référence avec la carte de l'éditeur).
static func _plain(v: Variant) -> bool:
	if v is Object:
		return false
	if v is Dictionary:
		for k in v:
			if not _plain(k) or not _plain(v[k]):
				return false
	elif v is Array:
		for x in v:
			if not _plain(x):
				return false
	return true


# ------------------------------------------------------------------ tests

func test_rich_map_covers_every_kind() -> void:
	var doc := rich_map()
	var types := {}
	for o in doc.objets + doc.ouvertures:
		types[String(o.type)] = int(types.get(String(o.type), 0)) + 1
	for t in ["passage", "porte", "debris", "fenetre", "arme", "atout", "boite", "courant", "pap", "luminaire", "lampe", "prefab",
			"caisse", "baril", "pilier", "mur", "mur_courbe", "escalier", "piege", "levier", "depart"]:
		assert_true(types.has(t), "carte complète : %s posé (%s)" % [t, str(types)])
	assert_eq(int(types.get("fenetre", 0)), 4, "4 fenêtres (dont une sur un côté en biais de la pièce ronde)")
	assert_true(doc.objets.any(func(o): return String(o.type) == "pap" and o.has("angle")), "Pack-a-Punch contre le mur en biais")
	assert_eq(int(types.get("luminaire", 0)), 4, "4 luminaires (dont la lampe sur le bureau)")


func test_worker_path_touches_no_shared_state() -> void:
	var doc := rich_map()
	MapCatalog.items()
	ThreadGuard.take_violations()
	var job := MapPreviewWorld.Job.new()
	job.map = doc.duplicate_map()
	job.lang_en = false
	var res: Dictionary = _in_thread(job.run)
	var bad := ThreadGuard.take_violations()
	assert_eq(bad.size(), 0, "aucun état partagé touché dans le fil : %s" % str(bad))
	var here := MapPreviewWorld.compute(doc.duplicate_map())
	assert_false((res.data as Dictionary).is_empty(), "description calculée dans le fil")
	assert_eq(int(res.errors), int(here.errors), "mêmes erreurs que sur le fil principal (%d)" % int(here.errors))
	assert_eq(var_to_str(res.data), var_to_str(here.data), "même description que sur le fil principal")
	assert_true((res.data.markers.lamps as Array).size() >= 5 and (res.data.props as Array).size() >= 3 and (res.data.markers.traps as Array).size() == 1, "lampes, décor et piège dans la description")


func test_main_thread_caches_refuse_worker_access() -> void:
	var doc := rich_map()
	ThreadGuard.take_violations()
	MapRules.end_batch()
	var poly := doc.room_poly(doc.pieces[0])
	var key := var_to_str(poly)
	MapRules._inner_cache.erase(key)
	_probe = []
	var probe := func() -> void:
		MapRules.begin_batch(doc)
		_probe.append(MapRules._batch_doc == null)
		_probe.append(MapRules.inner_cells(poly).size())
		MapRules.end_batch()
		_probe.append(WeaponDB.display_name("m14"))
		_probe.append(Lang.t("fr", "en"))
	_in_thread(probe)
	var bad := ThreadGuard.take_violations()
	assert_true(bool(_probe[0]), "lot de vérification : pas ouvert depuis un fil")
	assert_false(MapRules._inner_cache.has(key), "cache des cases intérieures : rien écrit depuis le fil")
	assert_eq(int(_probe[1]), MapRules.inner_cells(poly).size(), "cases intérieures justes sans le cache")
	assert_eq(String(_probe[2]), WeaponDB.display_name("m14"), "nom de l'arme calculé sans le cache des armes")
	assert_eq(String(_probe[3]), "fr", "langue : français par défaut dans un fil non préparé")
	for what in ["MapRules.begin_batch", "MapRules._inner_cache", "MapRules.end_batch", "Settings.language"]:
		assert_true(Array(bad).any(func(v): return String(v).begins_with(what)), "accès refusé et noté : %s (%s)" % [what, str(bad)])
	assert_false(Array(bad).any(func(v): return String(v).contains("WeaponDB")), "armes : calcul local, pas un accès refusé")


func test_worker_language_is_frozen_at_launch() -> void:
	var job := MapPreviewWorld.Job.new()
	var doc := rich_map()
	doc.zones[0]["nom"] = {"fr": "Entrée", "en": "Lobby"}
	job.map = doc.duplicate_map()
	job.lang_en = true
	var res: Dictionary = _in_thread(job.run)
	assert_eq(ThreadGuard.take_violations().size(), 0, "aucun accès refusé")
	var names: Dictionary = res.data.map_def.zone_names
	assert_true(names.values().has("Lobby"), "noms des zones dans la langue figée au lancement (%s)" % str(names))


func test_catalog_is_frozen() -> void:
	var items := MapCatalog.items()
	assert_true(items.is_read_only(), "liste du catalogue en lecture seule")
	var it := MapCatalog.item("luminaire:lampe_bureau")
	assert_true(it.is_read_only() and (it.make as Dictionary).is_read_only() and (it.fp as Array).is_read_only(), "objet, modèle et emprise figés")
	var o: Dictionary = it.make.duplicate(true)
	o["position"] = [1.0, 2.0]
	assert_eq(o.position, [1.0, 2.0], "une copie du modèle reste modifiable")


func test_map_copy_is_deep() -> void:
	var doc := rich_map()
	var m := doc.duplicate_map()
	assert_true(_plain(m.to_dict()), "copie faite de données seulement (aucun objet)")
	doc.pieces[0].contour[0][0] = 99.0
	doc.objets[0]["position"] = [1.0, 1.0]
	doc.carte.etages[0]["hauteur"] = 9.0
	doc.zones[0].nom["fr"] = "changé"
	assert_near(float(m.pieces[0].contour[0][0]), 0.0, 0.001, "contour copié")
	assert_true(m.objets[0].position != [1.0, 1.0], "objets copiés")
	assert_near(m.floor_height(0), 3.2, 0.001, "étages copiés")
	assert_true(String(m.zones[0].nom.fr) != "changé", "noms des zones copiés")
