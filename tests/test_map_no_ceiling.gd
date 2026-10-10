extends TestCase
## Plafond masqué et ciel de la carte (format 17, docs/LEVELS_PLAN.md étape 2) :
## clé « sans_plafond » (jamais écrite à faux), « carte.ciel » (jamais écrit à
## sa valeur par défaut), contrôle des cartes reçues, export (« no_ceiling »,
## murs jusqu'au plafond réglé, pas de lampe automatique), avertissement des
## luminaires accrochés, dalle d'une pièce posée au-dessus, environnement du jeu.

const OFF := MapGeom.WORLD_OFFSET
const Ceil := preload("res://tests/test_ceiling_under_floor.gd")
const Lv := preload("res://tests/test_levels_migration.gd")


## Pièce de 8 x 6 m (zone A, départ) ; `open` : sans plafond ; `ceil` :
## hauteur sous plafond (0 : par défaut). `closed_too` : une seconde pièce
## fermée collée à l'est, reliée par un passage.
static func _open_room(open := true, ceil := 0.0, closed_too := false) -> EditorMap:
	var doc := EditorMap.blank("ciel_ouvert", "CIEL", "SKY")
	var za := doc.add_zone("A", "A")
	doc.depart = String(za.id)
	var p := {"id": "p1", "nom": "Cour", "altitude": 0, "zone": String(za.id), "contour": Lv.rect(0, 0, 8, 6)}
	if ceil > 0.0:
		p["plafond"] = ceil
	if open:
		p["sans_plafond"] = true
	doc.pieces.append(p)
	if closed_too:
		doc.pieces.append({"id": "p2", "nom": "Salle", "altitude": 0, "zone": String(za.id), "contour": Lv.rect(8, 0, 16, 6)})
		doc.ouvertures.append({"id": "o1", "type": "passage", "altitude": 0, "position": [8, 3], "largeur": 2})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [4, 3]})
	return doc


static func _data(doc: EditorMap) -> Dictionary:
	return MapPreviewWorld.compute(doc).data


## Salles de l'export qui contiennent le point (x, z) de l'éditeur.
static func _rooms_at(data: Dictionary, x: float, z: float) -> Array:
	var out := []
	for r in data.get("rooms", []):
		var poly := PackedVector2Array()
		for q in r.outline:
			poly.append(Vector2(float(q[0]), float(q[1])))
		if Geometry2D.is_point_in_polygon(Vector2(x + OFF, z + OFF), poly):
			out.append(r)
	return out


# ------------------------------------------------------------------ clés

func test_key_written_only_when_true() -> void:
	var doc := _open_room()
	var t := doc.file_texts()
	assert_true(String(t["pieces.json"]).contains("\"sans_plafond\":true"), "clé écrite")
	var back := EditorMap.from_texts(t)
	assert_true(EditorMap.no_ceiling(back.pieces[0]), "relue")
	# Faux (ou illisible) : retiré au chargement.
	for bad in [false, "oui", 1]:
		var raw := t.duplicate()
		raw["pieces.json"] = String(t["pieces.json"]).replace("\"sans_plafond\":true", "\"sans_plafond\":" + JSON.stringify(bad))
		var m := EditorMap.from_texts(raw)
		assert_false(m.pieces[0].has("sans_plafond"), "« %s » retiré" % str(bad))
	var p := {}
	EditorMap.set_no_ceiling(p, true)
	assert_eq(p, {"sans_plafond": true})
	EditorMap.set_no_ceiling(p, false)
	assert_eq(p, {}, "plafond affiché : pas de clé")


func test_sky_defaults_and_tidy() -> void:
	assert_eq(EditorMap.sky_of({}), {"type": "noir", "luminosite": 1.0}, "défaut : noir")
	var c := {}
	EditorMap.set_sky(c, "jour", 1.0)
	assert_eq(c.get("ciel"), {"type": "jour"}, "luminosité par défaut non écrite")
	EditorMap.set_sky(c, "nuit", 0.5)
	assert_eq(c.get("ciel"), {"type": "nuit", "luminosite": 0.5})
	EditorMap.set_sky(c, "noir", 0.5)
	assert_false(c.has("ciel"), "noir : clé retirée")
	EditorMap.set_sky(c, "nuit", 99.0)
	assert_eq(float(c.ciel.luminosite), EditorMap.SKY_LUM[1], "luminosité bornée")
	# Au chargement : illisible ou par défaut retiré, sinon réécrit.
	for pair in [[{"type": "noir"}, null], [{"type": "pluie"}, null], ["jour", null], [{"type": "jour", "luminosite": 1}, {"type": "jour"}],
			[{"type": "nuit", "luminosite": 1.5, "x": 1}, {"type": "nuit", "luminosite": 1.5}]]:
		var doc := _open_room()
		doc.carte["ciel"] = pair[0]
		var m := EditorMap.from_texts(doc.file_texts())
		assert_eq(m.carte.get("ciel"), pair[1], "ciel %s" % str(pair[0]))


# ------------------------------------------------------------------ cartes reçues

func test_guard() -> void:
	var doc := _open_room(true, 5.0)
	EditorMap.set_sky(doc.carte, "nuit", 0.6)
	var r := CustomMapGuard.check_texts(doc.file_texts())
	assert_true(r.ok, "plafond masqué et ciel admis : %s" % [r.reasons])
	var m: EditorMap = r.map
	assert_true(EditorMap.no_ceiling(m.pieces[0]), "la clé voyage avec la carte")
	assert_eq(EditorMap.sky_of(m.carte), {"type": "nuit", "luminosite": 0.6}, "le ciel aussi")
	# Valeurs refusées.
	for bad in [{"type": "pluie"}, {"type": "jour", "luminosite": 9}, {"type": "jour", "soleil": 1}, "jour"]:
		var t := doc.file_texts()
		var cd: Dictionary = JSON.parse_string(t["carte.json"])
		cd["ciel"] = bad
		t["carte.json"] = JSON.stringify(cd)
		assert_false(CustomMapGuard.check_texts(t).ok, "ciel %s refusé" % str(bad))
	var t2 := doc.file_texts()
	t2["pieces.json"] = String(t2["pieces.json"]).replace("\"sans_plafond\":true", "\"sans_plafond\":\"oui\"")
	assert_false(CustomMapGuard.check_texts(t2).ok, "sans_plafond non booléen refusé")
	# Format 16 (schéma figé) : ni l'une ni l'autre clé.
	var old := Lv.two_floors()
	var cd16: Dictionary = JSON.parse_string(old["carte.json"])
	cd16["ciel"] = {"type": "jour"}
	old["carte.json"] = JSON.stringify(cd16)
	assert_false(CustomMapGuard.check_texts(old).ok, "ciel refusé au format 16")
	var old2 := Lv.two_floors()
	old2["pieces.json"] = String(old2["pieces.json"]).replace("\"id\":\"p1\"", "\"id\":\"p1\",\"sans_plafond\":true")
	assert_true(String(old2["pieces.json"]).contains("sans_plafond"))
	assert_false(CustomMapGuard.check_texts(old2).ok, "sans_plafond refusé au format 16")


# ------------------------------------------------------------------ export

func test_export_no_ceiling() -> void:
	var data := _data(_open_room(true, 4.5))
	var rs := _rooms_at(data, 4.0, 3.0)
	assert_false(rs.is_empty(), "une salle")
	for r in rs:
		assert_true(r.get("no_ceiling", false), "sans plafond : %s" % r.id)
		assert_near(float(r.ceiling), 4.5, 0.001, "plafond virtuel au plafond réglé")
	# Murs jusqu'au plafond réglé.
	var top := 0.0
	for b in data.blocks:
		top = maxf(top, float(b.box[4]))
	assert_near(top, 4.5, 0.001, "murs jusqu'à 4,5 m")
	# Jeu : aucune face ni collision au-dessus de la tête.
	var root := MeshMapGeometry.build(data)
	var h := Ceil._hit(root, Vector3(4 + OFF, 1.6, 3 + OFF), true)
	assert_true(h.is_empty(), "rien au-dessus : %s" % str(h))
	assert_eq(root.find_children("*__ceil*", "", true, false).size(), 0, "aucun plafond construit")
	root.free()
	# Plafond affiché : rien ne change (pas de clé dans l'export).
	var shut := _data(_open_room(false, 4.5))
	for r in shut.rooms:
		assert_false(r.has("no_ceiling"), "plafond dessiné")


func test_no_auto_lamp_under_open_sky() -> void:
	var data := _data(_open_room(true, 0.0, true))
	assert_false(data.markers.lamps.is_empty(), "lampes dans la salle fermée")
	for l in data.markers.lamps:
		assert_true(float(l.p[0]) > 8.0 + OFF, "lampe hors de la cour (x = %.2f)" % (float(l.p[0]) - OFF))
	var all_open := _data(_open_room(true))
	assert_eq(all_open.markers.lamps.size(), 0, "ciel ouvert : aucune lampe automatique")
	# Le passage entre une pièce ouverte et une fermée garde son plafond.
	for r in _rooms_at(data, 8.0, 3.0):
		assert_false(r.get("no_ceiling", false), "passage vers une pièce fermée : plafond (%s)" % r.id)


func test_hung_fixture_warning() -> void:
	var doc := _open_room(true, 4.0)
	doc.objets.append({"id": "lu1", "altitude": 0, "type": "luminaire", "luminaire": "suspension", "position": [4.0, 3.0], "rot": 0})
	var v := MapRaster.build(doc).v
	var w := v.warnings().filter(func(m): return String(m.fr).contains("plafond masqué"))
	assert_eq(w.size(), 1, "un avertissement : %s" % str(v.messages.map(func(m): return m.fr)))
	assert_true(String(w[0].fr).contains("flotte à 4,00 m"), String(w[0].fr))
	assert_true(v.errors().is_empty(), "jamais une erreur : %s" % str(v.errors().map(func(m): return m.fr)))
	# Construit au plafond virtuel (4 m, moins sa descente).
	var data := _data(doc)
	var fx: Array = data.markers.lamps.filter(func(l): return String(l.get("fixture", "")) == "suspension")
	assert_eq(fx.size(), 1, "luminaire exporté")
	assert_near(float(fx[0].fixture_p[1]), 4.0, 0.001, "accroché au plafond virtuel")
	# Plafond affiché : pas d'avertissement.
	var shut := _open_room(false, 4.0)
	shut.objets.append(doc.objets[-1].duplicate())
	assert_true(MapRaster.build(shut).v.warnings().filter(func(m): return String(m.fr).contains("plafond masqué")).is_empty())


func test_slab_of_room_above_stays() -> void:
	# Pièce basse sans plafond, pièce posée au-dessus de sa moitié ouest.
	var doc := Ceil._two_floors()
	EditorMap.set_no_ceiling(doc.pieces[0], true)
	var data := _data(doc)
	for r in _rooms_at(data, 2.0, 4.0).filter(func(r): return float(r.floor) < 1.0):
		assert_false(r.get("no_ceiling", false), "sous la pièce du dessus : plafond sous dalle")
		# Format 20 : le plafond est le dessous de la dalle (plus d'écart de 1 cm).
		assert_near(float(r.ceiling), 3.5 - MapValidator.DALLE, 0.0001)
	for r in _rooms_at(data, 8.0, 4.0).filter(func(r): return float(r.floor) < 1.0):
		assert_true(r.get("no_ceiling", false), "hors de la pièce du dessus : ciel ouvert")
	var root := MeshMapGeometry.build(data)
	var under := Ceil._hit(root, Vector3(2 + OFF, 1.6, 4 + OFF), true)
	assert_eq(String(under.get("name", "")).split("__")[-1], "ceil", "plafond vu d'en bas : %s" % under.get("name", "rien"))
	var open := Ceil._hit(root, Vector3(8 + OFF, 1.6, 4 + OFF), true)
	assert_true(open.is_empty(), "ciel ouvert : %s" % str(open))
	root.free()
	# Pièce du dessus sans plafond : la pièce du bas garde le sien.
	var doc2 := Ceil._two_floors()
	EditorMap.set_no_ceiling(doc2.pieces[1], true)
	var d2 := _data(doc2)
	for r in _rooms_at(d2, 8.0, 4.0).filter(func(r): return float(r.floor) < 1.0):
		assert_false(r.get("no_ceiling", false), "pièce du bas fermée")
	for r in _rooms_at(d2, 2.0, 4.0).filter(func(r): return float(r.floor) > 1.0):
		assert_true(r.get("no_ceiling", false), "pièce du haut ouverte")


# ------------------------------------------------------------------ ciel

func test_sky_in_map_def() -> void:
	var doc := _open_room()
	assert_eq(_data(doc).map_def.get("sky"), {"type": "noir", "luminosite": 1.0}, "pièce ouverte, ciel par défaut : noir complet")
	EditorMap.set_sky(doc.carte, "jour", 0.8)
	var md: Dictionary = _data(doc).map_def
	assert_eq(md.get("sky"), {"type": "jour", "luminosite": 0.8}, "ciel exporté")
	# Aucune pièce sans plafond : le ciel ne se voit pas, rendu d'avant.
	var shut := _open_room(false)
	EditorMap.set_sky(shut.carte, "jour", 0.8)
	assert_false(_data(shut).map_def.has("sky"), "pas de ciel sans pièce ouverte")
	# Partie (DRAFT ARENA, salle des machines à ciel ouvert, carte reçue) :
	# l'environnement de la carte reçoit le ciel.
	var arena := EditorMap.load_dir("res://assets/maps/draft_arena/")
	EditorMap.set_no_ceiling(arena.find("p1"), true)
	EditorMap.set_sky(arena.carte, "nuit", 1.3)
	var r := CustomMapGuard.check_texts(arena.file_texts())
	assert_true(r.ok, str(r.reasons))
	var def := EditorMapDef.new()
	def._setup(r.map, "draft_ciel")
	assert_true(def.is_valid(), "carte jouable : %s" % str(def.validator.errors().map(func(m): return m.fr)))
	assert_eq(def.look.get("sky"), {"type": "nuit", "luminosite": 1.3})
	assert_true(def.layout_data.rooms.any(func(rm): return rm.get("no_ceiling", false)), "salle à ciel ouvert exportée")


func test_apply_sky_environment() -> void:
	var parent := Node3D.new()
	WorldLook.setup_environment(parent, {})
	var env := (parent.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_eq(env.background_mode, Environment.BG_COLOR, "par défaut : fond uni")
	assert_eq(env.background_color, Color(0, 0, 0), "noir")
	var amb := [env.ambient_light_source, env.ambient_light_color, env.ambient_light_energy]
	WorldLook.apply_sky(env, {"type": "jour", "luminosite": 0.7})
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_true(env.sky.sky_material is ProceduralSkyMaterial, "ciel de jour procédural")
	assert_near((env.sky.sky_material as ProceduralSkyMaterial).energy_multiplier, 0.7, 0.001, "luminosité")
	assert_eq([env.ambient_light_source, env.ambient_light_color, env.ambient_light_energy], amb, "lumière ambiante inchangée")
	WorldLook.apply_sky(env, {"type": "nuit", "luminosite": 1.4})
	var sm := env.sky.sky_material as ShaderMaterial
	assert_true(sm != null and sm.shader == WorldLook.NIGHT_SKY, "nuit étoilée : shader")
	assert_near(float(sm.get_shader_parameter("brightness")), 1.4, 0.001)
	WorldLook.apply_sky(env, {"type": "noir"})
	assert_eq(env.background_mode, Environment.BG_COLOR, "retour au noir")
	assert_eq(env.background_color, Color(0, 0, 0))
	assert_true(env.sky == null, "plus de ciel")
	assert_eq(env.fog_sky_affect, 0.0, "noir complet (pas voilé par la brume)")
	WorldLook.apply_sky(env, {"type": "noir"}, false)
	assert_eq(env.fog_sky_affect, 1.0, "carte fermée : fond d'avant")
	parent.free()
	# Carte avec ciel : setup_environment l'applique (look « sky »).
	var p2 := Node3D.new()
	WorldLook.setup_environment(p2, {"sky": {"type": "nuit", "luminosite": 1.0}})
	var env2 := (p2.get_node("WorldEnvironment") as WorldEnvironment).environment
	assert_eq(env2.background_mode, Environment.BG_SKY)
	p2.free()
