extends TestCase
## Ambiances des pièces (RoomMood, MoodZones ; format 23 de l'éditeur) :
## déduction depuis les noms, le sol et les luminaires, résolution pièce >
## zone > déduite, couleur des lampes, nœuds en jeu (remplissage, brume,
## courant, alarme), sources d'appoint colorées (catalogue, gyrophare, jamais
## d'ombre), aller-retour dans l'éditeur, migration, description exportée et
## contrôle des cartes reçues (CustomMapGuard).

const DRAFT := "res://assets/maps/draft_arena/"
const TMP := "user://test_room_mood/"


func before_each() -> void:
	CustomMapGuard.source_override = {}
	CustomMapGuard.reset_schema()


func after_each() -> void:
	CustomMapGuard.source_override = {}
	CustomMapGuard.reset_schema()
	_rm(TMP)


static func _rm(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


# ------------------------------------------------------------------ RoomMood (pur)

func test_presets_complete() -> void:
	assert_eq(RoomMood.ORDER.size(), RoomMood.PRESETS.size(), "ordre : tous les préréglages")
	for m in RoomMood.ORDER:
		var p := RoomMood.preset(m)
		for k in ["fr", "en", "lamp", "lamp_mix", "lamp_energy", "fill", "fill_energy", "fog", "fog_density", "fog_emission"]:
			assert_true(p.has(k), "%s : clé %s" % [m, k])
		assert_true(float(p.lamp_mix) >= 0.0 and float(p.lamp_mix) <= 1.0, "%s : mélange 0..1" % m)
	assert_false(RoomMood.is_preset(RoomMood.AUTO), "« auto » n'est pas un préréglage")
	assert_false(RoomMood.is_preset(""), "« » : standard")
	assert_eq(RoomMood.display_name(""), Lang.t("Standard", "Standard"), "nom de l'ambiance standard")


func test_derive_from_names() -> void:
	var cases := {
		"Laboratoire": "froid", "Couloir des cellules": "froid", "Salle de garde": "chaud", "Dortoir": "chaud",
		"Générateur": "alarme", "Salle du rituel": "eteint", "Barracks": "chaud", "Generator": "alarme",
		"Cell Block": "froid", "Chambre froide": "froid", "Salle serveur": "neon", "Bureau du directeur": "chaud",
		"Infirmerie": "froid", "Cuisine": "chaud", "Quai": "", "Pièce 3": "",
	}
	for n in cases:
		assert_eq(RoomMood.derive([n]), cases[n], "nom « %s »" % n)
	# Le nom de la zone compte aussi (pièce sans nom parlant).
	assert_eq(RoomMood.derive(["Pièce 2", "Laboratoire"]), "froid", "nom de la zone")
	assert_eq(RoomMood.fold("Générateur ÉLECTRIQUE"), "generateur electrique", "minuscules sans accents")


func test_derive_hints() -> void:
	# Luminaire fort : l'emporte même sur le nom.
	assert_eq(RoomMood.derive(["Bureau"], "", ["gyrophare"]), "alarme", "gyrophare -> alarme")
	assert_eq(RoomMood.derive(["Pièce"], "", ["ampoule", "enseigne"]), "neon", "enseigne -> néon")
	# Indices faibles, sans nom parlant : luminaires, puis sol.
	assert_eq(RoomMood.derive(["Pièce"], "concrete", ["bougies", "feu"]), "chaud", "flammes -> chaud")
	assert_eq(RoomMood.derive(["Pièce"], "concrete", ["neon", "neon"]), "froid", "tubes néon -> froid")
	assert_eq(RoomMood.derive(["Pièce"], "parquet"), "chaud", "parquet -> chaud")
	assert_eq(RoomMood.derive(["Pièce"], "tiles"), "froid", "carrelage -> froid")
	assert_eq(RoomMood.derive(["Pièce"], "concrete", ["ampoule"]), "", "rien de parlant -> standard")
	# Le nom passe avant les indices faibles.
	assert_eq(RoomMood.derive(["Laboratoire"], "parquet", ["bougies"]), "froid", "nom avant le sol et les flammes")


func test_resolve_and_lamp_color() -> void:
	assert_eq(RoomMood.resolve("chaud", "froid", "alarme"), "chaud", "la pièce l'emporte")
	assert_eq(RoomMood.resolve(null, "froid", "alarme"), "froid", "puis la zone")
	assert_eq(RoomMood.resolve("disco", 3, "alarme"), "alarme", "valeurs inconnues : déduite")
	assert_eq(RoomMood.resolve(null, null, ""), "", "standard")
	var std := RoomMood.lamp("", PowerGrid.ON_COLOR, 2.0)
	assert_eq(std[0], PowerGrid.ON_COLOR, "standard : couleur inchangée")
	assert_near(float(std[1]), 2.0, 0.0001, "standard : énergie inchangée")
	var warm: Color = RoomMood.lamp("chaud", PowerGrid.ON_COLOR, 2.0)[0]
	var cold: Color = RoomMood.lamp("froid", PowerGrid.ON_COLOR, 2.0)[0]
	assert_true(warm.b < PowerGrid.ON_COLOR.b and warm.r >= warm.g, "chaud : plus orange")
	assert_true(cold.b > PowerGrid.ON_COLOR.b + 0.2, "froid : bleuté")
	var kept := RoomMood.lamp("froid", Color.RED, 2.0, false)
	assert_eq(kept[0], Color.RED, "luminaire recoloré : couleur gardée")
	assert_true(float(RoomMood.lamp("eteint", PowerGrid.ON_COLOR, 2.0)[1]) < 1.0, "éteint : lampes faibles")


# ------------------------------------------------------------------ en jeu (MoodZones, MapProps)

func _props() -> MapProps:
	var parent := Node3D.new()
	host.add_child(parent)
	var props := MapProps.new()
	props._make_root(parent)
	return props


func test_mood_zones_nodes() -> void:
	var props := _props()
	props.add_moods([
		["chaud", [AABB(Vector3(0, 0, 0), Vector3(10, 3.2, 8)), AABB(Vector3(10, 0, 0), Vector3(1, 3.2, 1))]],
		["", [AABB(Vector3(30, 0, 0), Vector3(4, 3, 4))]],
		["alarme", [AABB(Vector3(20, 0, 0), Vector3(4, 3.2, 4))]],
	])
	var mz := props.moods
	assert_true(mz != null, "ambiances posées")
	assert_eq(mz.areas.size(), 2, "ambiance standard ignorée")
	assert_eq(mz.mood_at(Vector3(5, 2.7, 4)), "chaud", "lampe dans la pièce chaude")
	assert_eq(mz.mood_at(Vector3(22, 1, 2)), "alarme", "alarme")
	assert_eq(mz.mood_at(Vector3(32, 1, 2)), "", "hors pièce : standard")
	var fills := mz.find_children("Fill*", "OmniLight3D", false, false)
	assert_eq(fills.size(), 2, "un remplissage par pièce (petite boîte : aucun)")
	for f: OmniLight3D in fills:
		assert_false(f.shadow_enabled, "remplissage sans ombre")
	assert_eq(mz.find_children("*", "FogVolume", false, false).size(), 3, "une brume par boîte")
	# Courant coupé : remplissage à 35 %, sauf l'alarme (secours).
	props.power.apply_immediate(false)
	var warm_fill: OmniLight3D = fills.filter(func(f): return f.light_color.is_equal_approx(RoomMood.PRESETS.chaud.fill))[0]
	assert_near(warm_fill.light_energy, float(RoomMood.PRESETS.chaud.fill_energy) * MoodZones.UNPOWERED, 0.001, "chaud : courant coupé")
	props.power.apply_immediate(true)
	assert_near(warm_fill.light_energy, float(RoomMood.PRESETS.chaud.fill_energy), 0.001, "chaud : courant rétabli")
	assert_true(MoodZones.alarm_pulse(0.0) >= 0.3 and MoodZones.alarm_pulse(0.4) <= 1.0, "pulsation bornée")
	# Les lampes prennent la couleur de leur pièce ; une source d'appoint jamais.
	var lamp := props.add_lamp(Vector3(5, 2.7, 4), 2.0, 10.0, false)
	assert_true(lamp.light_color.b < PowerGrid.ON_COLOR.b, "lampe de la pièce chaude : plus orange")
	var out := props.add_lamp(Vector3(32, 2.5, 2), 2.0, 10.0, false)
	assert_eq(out.light_color, PowerGrid.ON_COLOR, "lampe hors ambiance : inchangée")
	var acc := props.add_lamp(Vector3(5, 1.0, 4), 0.8, 3.0, false, Color.GREEN, false, "ecran", false)
	assert_eq(acc.light_color, Color.GREEN, "écran : couleur gardée")
	props.root.get_parent().queue_free()


func test_ceiling_bounce_and_dust() -> void:
	var props := _props()
	var lamp := props.add_lamp(Vector3(0, 2.7, 0), 2.4, 11.0, false)
	var pool := lamp.get_node("Pool") as LampPool
	var bounce := lamp.get_node_or_null("Bounce") as SpotLight3D
	assert_true(bounce != null and pool.bounce == bounce, "lampe de plafond : rebond")
	assert_true(bounce.global_basis.z.normalized().is_equal_approx(Vector3.DOWN), "rebond dirigé vers le haut (-Z local = +Y)")
	assert_true(bounce.position.y < 0.0 and not bounce.shadow_enabled, "sous la lampe, sans ombre")
	assert_near(bounce.light_volumetric_fog_energy, 0.0, 0.0001, "rebond : pas de faisceau dans la brume")
	pool.sync()
	assert_near(bounce.light_energy, pool.light_energy * float(LampStyle.CEILING.bounce), 0.001, "rebond : part de la flaque")
	var desk := props.add_lamp(Vector3(3, 1.2, 0), 0.9, 5.0, false, PowerGrid.ON_COLOR, true, "lampe_bureau")
	assert_true(desk.get_node_or_null("Bounce") == null, "lampe de bureau : pas de rebond")
	# Poussière : un seul système pour toutes les lampes à flaque.
	props.finish_lamps()
	assert_true(props.dust != null and props.dust.cone_count() == 2, "un cône par lampe à flaque")
	props.dust.apply_quality(RenderQuality.preset(Settings.Quality.LOW))
	assert_false(props.dust.visible, "LOW : pas de poussière")
	props.dust.apply_quality(RenderQuality.preset(Settings.Quality.HIGH))
	assert_true(props.dust.visible and props.dust.amount == 2 * int(LampDust.PER_LAMP.high), "HIGH : grains par lampe")
	assert_eq(props.root.find_children("*", "LampDust", true, false).size(), 1, "un seul système")
	props.root.get_parent().queue_free()


func test_accent_lights() -> void:
	for id in ["gyrophare", "ecran", "tubes", "sortie", "enseigne"]:
		var d: Dictionary = MapCatalog.LIGHTS.get(id, {})
		assert_true(d.has("accent"), "%s : source d'appoint" % id)
		assert_true(ResourceLoader.exists("res://assets/models/props/%s.glb" % String(d.get("model", ""))), "%s : modèle cubique" % id)
		var s := LampStyle.of(id)
		assert_false(LampStyle.has_pool(s), "%s : pas de flaque" % id)
		assert_true(bool(s.get("no_shadow", false)), "%s : jamais d'ombre" % id)
		assert_eq(String(d.get("bloque", "non")), "non", "%s : ne bloque pas (aucune collision)" % id)
	var props := _props()
	var beacon := props.add_lamp(Vector3(0, 2.3, 0), 2.0, 6.0, false, Color.RED, false, "gyrophare", false)
	var spin := beacon.get_node_or_null("Beacon") as BeaconSpin
	assert_true(spin != null and spin.beams.size() == 2, "gyrophare : deux faisceaux")
	for q in [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		RenderQuality.apply_lamp(beacon, RenderQuality.preset(q))
		assert_false(RenderQuality.lamp_casts_shadow(beacon), "gyrophare sans ombre (qualité %d)" % q)
		for b in spin.beams:
			assert_false(b.shadow_enabled, "faisceau sans ombre")
			assert_true(b.distance_fade_enabled, "faisceau : fondu")
	spin.sync()
	assert_near(spin.beams[0].light_energy, 2.0 * float(LampStyle.BEACON.beam), 0.001, "faisceau : énergie de la lampe x beam")
	assert_eq(spin.beams[1].light_color, Color.RED, "couleur recopiée")
	props.root.get_parent().queue_free()


func test_bunker_moods_and_accents() -> void:
	var def: MapDef = load("res://scripts/game/map/maps/bunker_k7.gd").new()
	assert_eq(def.zone_mood("a"), "chaud", "salle de garde chaude")
	assert_eq(def.zone_mood("b"), "froid", "couloir froid")
	assert_eq(def.zone_mood("e"), "alarme", "générateur en alarme")
	assert_eq(def.zone_mood("f"), "", "quai standard")
	var data := MapData.parse(def.rows)
	for e in def.accent_lights:
		assert_true(MapCatalog.LIGHTS.has(String(e.light)), "luminaire connu : %s" % e.light)
		if e.has("cell"):
			assert_true(data.is_floor(e.cell), "%s posé sur du sol" % e.light)
		else:
			var w: Vector2i = e.wall
			var at: Vector2 = e.at
			# Le point est sur la face d'un mur : derrière, un mur (ou une porte
			# dans le mur, panneau de sortie au-dessus) ; devant, du sol.
			var behind := Vector2i(floori(at.x + w.x * 0.5), floori(at.y + w.y * 0.5))
			var front := Vector2i(floori(at.x - w.x * 0.5), floori(at.y - w.y * 0.5))
			assert_true(data.is_wall(behind) or def.doors.has(String.chr(data.at(behind))), "%s contre un mur (%s)" % [e.light, str(behind)])
			assert_true(data.is_floor(front), "%s face à la pièce (%s)" % [e.light, str(front)])


# ------------------------------------------------------------------ éditeur (format 23)

func _room_map() -> EditorMap:
	var m := EditorMap.blank("t_mood")
	m.zones = [{"id": "z1", "nom": {"fr": "Laboratoire", "en": "Lab"}}]
	m.pieces = [{"id": "p1", "nom": "Pièce", "zone": "z1", "contour": [[0, 0], [6, 0], [6, 5], [0, 5]]}]
	return m


func test_editor_mood_round_trip() -> void:
	var m := _room_map()
	var p: Dictionary = m.pieces[0]
	assert_eq(m.derived_mood(p), "froid", "déduite du nom de la zone")
	assert_eq(m.mood_of(p), "froid", "ambiance déduite")
	EditorMap.set_mood(p, "chaud")
	assert_eq(String(p.get("ambiance", "")), "chaud", "clé écrite")
	EditorMap.set_mood(m.zones[0], "alarme")
	assert_eq(m.mood_of(p), "chaud", "la pièce l'emporte sur la zone")
	EditorMap.set_mood(p, RoomMood.AUTO)
	assert_false(p.has("ambiance"), "Auto : clé retirée")
	assert_eq(m.mood_of(p), "alarme", "puis celle de la zone")
	EditorMap.set_mood(m.zones[0], "")
	# Luminaire posé dans la pièce : indice de déduction.
	m.objets.append({"id": "o1", "type": "luminaire", "luminaire": "gyrophare", "position": [3, 0.1], "mur": "n"})
	assert_eq(m.fixtures_in(p), ["gyrophare"], "luminaire dans la pièce")
	assert_eq(m.derived_mood(p), "alarme", "gyrophare -> alarme")
	m.objets.clear()
	# Aller-retour par les fichiers : la clé choisie survit, la déduite n'est jamais écrite.
	EditorMap.set_mood(p, "neon")
	var texts := m.file_texts()
	assert_eq(String(JSON.parse_string(texts["pieces.json"]).pieces[0].get("ambiance", "")), "neon", "pieces.json : ambiance écrite")
	assert_false(String(texts["zones.json"]).contains("ambiance"), "zone sans ambiance : rien d'écrit")
	assert_eq(int(JSON.parse_string(texts["carte.json"]).format), EditorMap.FORMAT, "format écrit")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	assert_eq(m.save_dir(TMP), OK, "enregistrement")
	var back := EditorMap.load_dir(TMP)
	assert_eq(String(back.pieces[0].get("ambiance", "")), "neon", "relue")
	assert_eq(back.mood_of(back.pieces[0]), "neon", "ambiance relue")


func test_editor_migration() -> void:
	assert_true(EditorMap.FORMAT >= 23, "format 23 : ambiances")
	# Carte livrée au format 22 : lue telle quelle, ambiances déduites, rien d'écrit.
	var m := EditorMap.load_dir(DRAFT)
	assert_true(m.load_errors.is_empty(), "draft_arena lisible : %s" % str(m.load_errors))
	for p in m.pieces:
		assert_false(p.has("ambiance"), "aucune ambiance ajoutée au chargement")
	assert_false(String(m.file_texts()["pieces.json"]).contains("ambiance"), "ambiances déduites jamais écrites")
	# Valeur inconnue (fichier écrit à la main) : retirée avec une note.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var t := m.file_texts()
	var pj = JSON.parse_string(t["pieces.json"])
	pj.pieces[0]["ambiance"] = "disco"
	for f in t:
		var fa := FileAccess.open(TMP + f, FileAccess.WRITE)
		fa.store_string(JSON.stringify(pj) if f == "pieces.json" else String(t[f]))
		fa.close()
	var back := EditorMap.load_dir(TMP)
	assert_false(back.pieces[0].has("ambiance"), "ambiance inconnue retirée")
	assert_true(back.load_notes.any(func(n): return String(n[0]).contains("ambiance inconnue")), "note de lecture")


func test_layout_export_moods() -> void:
	var m := EditorMap.load_dir(DRAFT)
	var p: Dictionary = m.pieces[0]
	EditorMap.set_mood(p, "alarme")
	var d := EditorMapDef.from_map(m)
	assert_true(d.is_valid(), "carte valide")
	var moods: Array = d.layout_data.get("moods", [])
	var alarm := moods.filter(func(e): return String(e.mood) == "alarme")
	assert_false(alarm.is_empty(), "boîtes d'ambiance exportées")
	for e in alarm:
		for b in e.boxes:
			assert_eq(b.size(), 6, "boîte [x0,y0,z0,x1,y1,z1]")
			assert_true(float(b[4]) > float(b[1]) + 2.0, "du sol au plafond")
	# Le jeu les lit (MeshMapBuilder._build_moods), un préréglage inconnu est ignoré.
	var parent := Node3D.new()
	host.add_child(parent)
	var layout := d.layout_data.duplicate()
	layout["moods"] = moods + [{"mood": "disco", "boxes": [[0, 0, 0, 1, 1, 1]]}, {"mood": "froid", "boxes": [[0, 0, "x", 1, 1, 1]]}]
	var b := MeshMapBuilder.new(layout)
	b._make_root(parent)
	b._build_moods()
	assert_true(b.moods != null and b.moods.areas.any(func(a): return String(a.mood) == "alarme"), "ambiance posée en jeu")
	assert_false(b.moods.areas.any(func(a): return String(a.mood) == "disco"), "préréglage inconnu ignoré")
	parent.queue_free()


func test_guard_accepts_known_moods_only() -> void:
	var m := EditorMap.load_dir(DRAFT)
	var t := m.file_texts()
	var pj = JSON.parse_string(t["pieces.json"])
	pj.pieces[0]["ambiance"] = "chaud"
	var zj = JSON.parse_string(t["zones.json"])
	zj.zones[0]["ambiance"] = "froid"
	t["pieces.json"] = JSON.stringify(pj)
	t["zones.json"] = JSON.stringify(zj)
	var r := CustomMapGuard.check_texts(t)
	assert_true(r.ok, "ambiances connues acceptées : %s" % str(r.get("reasons")))
	pj.pieces[0]["ambiance"] = "disco"
	t["pieces.json"] = JSON.stringify(pj)
	assert_false(CustomMapGuard.check_texts(t).ok, "ambiance inconnue refusée")
	pj.pieces[0]["ambiance"] = 3
	t["pieces.json"] = JSON.stringify(pj)
	assert_false(CustomMapGuard.check_texts(t).ok, "ambiance non texte refusée")
