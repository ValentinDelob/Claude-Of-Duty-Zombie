extends TestCase
## Format 19 -> 20 (docs/VOXEL_ARCHITECTURE_PLAN.md § 2.5, MapCubeSnap) :
## toute l'architecture d'une carte sur la grille des cubes de 5 cm après la
## lecture (fixtures de tous les formats, Verrückt), conversion idempotente
## et relue à l'identique, objets muraux gardés sur leur mur, copie de
## sauvegarde faite une seule fois, carte rendue invalide par l'arrondi
## signalée (FR/EN) et conservée, export sur la grille, saisies de l'éditeur
## (aimantation libre, rotation, déplacement) sur la grille.

const TMP := "res://tests/_out/test_voxel_archi_migration"
const LEVELS := "res://tests/fixtures/levels/"
const SUMMARY := "res://tests/fixtures/map_summary/"
const LM := preload("res://tests/test_levels_migration.gd")
const CUF := preload("res://tests/test_ceiling_under_floor.gd")


## Textes d'une carte d'un « doc » de tests/fixtures/map_summary.
static func summary_texts(doc: Dictionary) -> Dictionary:
	return {"carte.json": JSON.stringify(doc.get("carte", {})), "pieces.json": JSON.stringify({"pieces": doc.get("pieces", [])}),
		"ouvertures.json": JSON.stringify({"ouvertures": doc.get("ouvertures", [])}),
		"objets.json": JSON.stringify({"objets": doc.get("objets", [])}),
		"zones.json": JSON.stringify({"depart": doc.get("depart", ""), "zones": doc.get("zones", [])})}


## Toutes les cartes d'essai : {nom: EditorMap lue (convertie)}.
static func fixtures() -> Dictionary:
	var out := {}
	for d in DirAccess.get_directories_at("res://tests/fixtures/maps/"):
		out["maps/" + d] = EditorMap.load_dir("res://tests/fixtures/maps/%s/" % d)
	for f in DirAccess.get_files_at(LEVELS):
		if f.ends_with("_map_f16.json"):
			var t: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVELS + f))
			out["levels/" + f] = EditorMap.from_texts(t if t is Dictionary else {})
	for f in ["map_verruckt.json", "map_quai_13.json", "map_nouvelle_carte_3.json", "map_smallest.json", "map_draft_arena.json"]:
		var fx: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUMMARY + f))
		if fx is Dictionary and fx.get("doc") is Dictionary:
			out["summary/" + f] = EditorMap.from_texts(summary_texts(fx.doc))
	out["draft_arena"] = EditorMap.load_dir(EditorMap.EXAMPLES.draft_arena)
	return out


## Valeurs d'architecture d'une carte hors de la grille des cubes : [texte].
static func off_cube(doc: EditorMap) -> Array:
	var out := []
	var chk := func(v: Variant, what: String) -> void:
		if (v is float or v is int) and not MapGeom.on_cube(float(v)):
			out.append("%s = %s" % [what, str(v)])
	var chk_pt := func(p: Variant, what: String) -> void:
		if p is Array and p.size() >= 2:
			chk.call(p[0], what + ".x")
			chk.call(p[1], what + ".y")
	for p in doc.pieces:
		for q in p.get("contour", []):
			chk_pt.call(q, "%s contour" % p.id)
		for k in ["altitude", "plafond"]:
			chk.call(p.get(k), "%s %s" % [p.id, k])
	for o in doc.objets:
		chk.call(o.get("altitude"), "%s altitude" % o.id)
		match String(o.get("type", "")):
			"mur":
				chk_pt.call(o.get("a"), "%s a" % o.id)
				chk_pt.call(o.get("b"), "%s b" % o.id)
				chk.call(o.get("epaisseur"), "%s epaisseur" % o.id)
			"mur_courbe":
				chk_pt.call(o.get("centre"), "%s centre" % o.id)
				chk.call(o.get("rayon"), "%s rayon" % o.id)
			"pilier", "escalier":
				for x in o.get("rect", []):
					chk.call(x, "%s rect" % o.id)
				chk.call(o.get("altitude_haut"), "%s altitude_haut" % o.id)
	for o in doc.ouvertures:
		chk.call(o.get("altitude"), "%s altitude" % o.id)
	chk.call(doc.carte.get("hauteur_portes"), "hauteur_portes")
	return out


func test_cube_rounding() -> void:
	assert_eq(MapGeom.cube(0.149), 0.15)
	assert_eq(MapGeom.cube(3.19), 3.2)
	assert_eq(MapGeom.cube(-0.024), 0.0)
	assert_eq(MapGeom.cube(0.15000000000000002), 0.15, "valeur exacte k / 20")
	assert_true(MapGeom.on_cube(4.25) and MapGeom.on_cube(-1.35) and not MapGeom.on_cube(3.19))
	assert_eq(MapGeom.round_cube(Vector2(3.337, 7.861)), Vector2(3.35, 7.85))
	# Aimant sur un côté en biais : le point de la grille le plus près du trait.
	var q := MapGeom.cube_near_line(Vector2(3.01, 1.98), Vector2(0, 0), Vector2(6, 4))
	assert_true(MapGeom.on_cube(q.x) and MapGeom.on_cube(q.y), "sur la grille : %s" % q)
	assert_true(absf((q - Vector2.ZERO).cross(Vector2(6, 4).normalized())) < 0.001, "sur le côté : %s" % q)


func test_every_fixture_migrates_onto_the_grid() -> void:
	var all := fixtures()
	assert_true(all.size() >= 20, "cartes d'essai lues (%d)" % all.size())
	for name in all:
		var doc: EditorMap = all[name]
		assert_true(doc.load_errors.is_empty(), "%s : lue sans erreur %s" % [name, doc.load_errors])
		var off := off_cube(doc)
		assert_true(off.is_empty(), "%s : architecture hors de la grille : %s" % [name, ", ".join(off.slice(0, 6))])
		# Idempotente : une seconde passe ne change rien.
		assert_eq(MapCubeSnap.snap_map(doc), 0, "%s : idempotente" % name)
		# Relue au format 20 : aucune conversion, mêmes fichiers.
		var texts := doc.file_texts()
		assert_true(String(texts["carte.json"]).contains("\"format\": 20"), "%s : écrite au format 20" % name)
		var again := EditorMap.from_texts(texts)
		assert_eq(again.format_read, EditorMap.FORMAT)
		assert_eq(again.cube_changes, 0, "%s : rien à arrondir au format 20" % name)
		assert_eq(again.file_texts(), texts, "%s : relue à l'identique" % name)
		# Export : toute l'architecture sur la grille.
		var data: Dictionary = MapPreviewWorld.compute(doc).data
		if not data.is_empty():
			var og := MapLayoutExport.off_grid(data)
			assert_true(og.is_empty(), "%s : export hors grille : %s" % [name, ", ".join(og.slice(0, 6))])


func test_verruckt_and_old_fixtures_keep_their_errors() -> void:
	# Aucune carte d'essai ne gagne d'erreur au passage aux cubes.
	var all := fixtures()
	for name in all:
		var doc: EditorMap = all[name]
		var fresh := doc.cube_check()
		assert_true(fresh.is_empty(), "%s : erreurs nouvelles : %s" % [name, "\n".join(fresh.map(func(m): return String(m.fr)))])
	var verruckt: EditorMap = all["summary/map_verruckt.json"]
	assert_eq(verruckt.format_read, 1, "Verrückt : format 1")
	assert_false(verruckt.carte.has("etages"), "niveaux convertis avant les cubes")


func test_values_rounded_and_counted() -> void:
	var t := LM.texts({"format": 19, "hauteur_portes": 2.43},
		[{"id": "p1", "zone": "z1", "altitude": 0.01, "plafond": 3.33, "contour": [[0, 0], [8.013, 0], [8.013, 6.02], [0, 6.02]]},
			{"id": "p2", "zone": "z1", "altitude": 0.01, "contour": [[8.013, 0], [12, 0], [12, 6.02], [8.013, 6.02]]}],
		[{"id": "o1", "type": "porte", "altitude": 0.01, "position": [8.013, 3.012], "largeur": 2, "prix": 750},
			{"id": "o2", "type": "fenetre", "altitude": 0.01, "position": [4.013, 6.02]}],
		[{"id": "m1", "type": "mur", "altitude": 0.01, "a": [1.01, 1.02], "b": [3.04, 1.02], "epaisseur": 0.33},
			{"id": "w1", "type": "mur_courbe", "altitude": 0.01, "centre": [10.01, 3.03], "rayon": 1.23, "debut": 0, "ouverture": 90, "segments": 4},
			{"id": "x1", "type": "pilier", "altitude": 0.01, "rect": [5.01, 2.02, 5.99, 2.98]},
			{"id": "c1", "type": "courant", "altitude": 0.01, "position": [2.013, 0], "mur": "n"},
			{"id": "d1", "type": "prefab", "prefab": "caisse", "altitude": 0.01, "position": [6.013, 4.017]}])
	var doc := EditorMap.from_texts(t)
	assert_true(doc.cube_changes > 20, "valeurs comptées (%d)" % doc.cube_changes)
	assert_true(doc.load_notes.any(func(n): return String(n[0]).contains("cubes de 5 cm") and String(n[1]).contains("5 cm cubes")), "note FR/EN : %s" % str(doc.load_notes))
	var p1 := doc.find("p1")
	assert_eq(p1.contour, [[0.0, 0.0], [8.0, 0.0], [8.0, 6.0], [0.0, 6.0]], "contour")
	assert_eq(float(p1.plafond), 3.35, "plafond")
	assert_eq(float(p1.altitude), 0.0, "altitude")
	assert_eq(doc.find("p2").contour[0], [8.0, 0.0], "bord commun gardé")
	assert_eq(float(doc.carte.hauteur_portes), 2.45, "hauteur des portes")
	assert_eq(doc.find("o1").position, [8.0, 3.0], "porte : sur le mur, place au cube")
	assert_eq(doc.find("o2").position, [4.0, 6.0], "fenêtre : sur le mur arrondi")
	assert_eq(doc.find("c1").position, [2.0, 0.0], "objet mural : sur son mur")
	var m1 := doc.find("m1")
	assert_eq([m1.a, m1.b, float(m1.epaisseur)], [[1.0, 1.0], [3.05, 1.0], 0.35], "mur libre")
	var w1 := doc.find("w1")
	assert_eq([w1.centre, float(w1.rayon), int(w1.debut)], [[10.0, 3.05], 1.25, 0], "mur courbe : centre et rayon (angles gardés)")
	assert_eq(doc.find("x1").rect, [5.0, 2.0, 6.0, 3.0], "pilier")
	assert_eq(doc.find("d1").position, [6.013, 4.017], "décor : ses propres règles")
	assert_eq(float(doc.find("d1").altitude), 0.0, "décor : altitude du niveau")


func test_wall_item_stays_on_an_oblique_wall() -> void:
	# Pièce au côté en biais de (0, 6) à (6.02, 0.01) : la fenêtre posée sur ce
	# côté y reste après l'arrondi des sommets.
	var a := Vector2(0, 6)
	var b := Vector2(6.02, 0.01)
	var at := a.lerp(b, 0.4)
	var t := LM.texts({"format": 19},
		[{"id": "p1", "zone": "z1", "contour": [[0, 0], [6.02, 0.01], [0, 6]]}],
		[{"id": "o1", "type": "fenetre", "position": [at.x, at.y]}])
	var doc := EditorMap.from_texts(t)
	var poly := doc.room_poly(doc.find("p1"))
	var p := MapGeom.v2(doc.find("o1").position)
	assert_true(MapGeom.on_boundary(poly, p, 0.002), "fenêtre sur le côté arrondi : %s, côté %s" % [p, poly])
	assert_true(p.distance_to(at) < 0.06, "à sa place (%s -> %s)" % [at, p])


func test_backup_made_once() -> void:
	var root := ProjectSettings.globalize_path(TMP)
	_wipe(root)
	EditorMap.root_override = root
	var dir := root.path_join("vieille")
	DirAccess.make_dir_recursive_absolute(dir)
	var t := LM.texts({"format": 12},
		[{"id": "p1", "zone": "z1", "contour": [[0, 0], [8.013, 0], [8.013, 6], [0, 6]]}])
	for f in t:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		fa.store_string(t[f])
		fa.close()
	var doc := EditorMap.load_dir(dir)
	assert_true(doc.cube_changes > 0)
	var b1 := MapCubeSnap.backup(dir, doc.format_read)
	assert_true(b1 != "" and b1.get_file().begins_with("vieille_f12_"), "copie : %s" % b1)
	for f in EditorMap.FILES:
		assert_eq(FileAccess.get_file_as_string(b1.path_join(f)), String(t[f]), "copie identique : %s" % f)
	var b2 := MapCubeSnap.backup(dir, doc.format_read)
	assert_eq(b2, b1, "jamais deux fois la même copie")
	assert_eq(DirAccess.get_directories_at(root.path_join(MapCubeSnap.BACKUP_DIR)).size(), 1)
	assert_false(EditorMap.list_maps().any(func(m): return String(m.id).begins_with("_")), "la copie n'est pas une carte de la liste")
	# La carte du dossier n'est jamais écrite par la lecture.
	assert_eq(FileAccess.get_file_as_string(dir.path_join("pieces.json")), String(t["pieces.json"]), "carte d'origine intacte")
	# Refusé hors du dossier des cartes.
	assert_eq(MapCubeSnap.backup("res://tests/fixtures/maps/smallest/", 5), "")
	EditorMap.root_override = ""
	_wipe(root)


func test_editor_open_makes_the_backup() -> void:
	var root := ProjectSettings.globalize_path(TMP + "_editeur")
	_wipe(root)
	EditorMap.root_override = root
	var dir := root.path_join("vieille")
	DirAccess.make_dir_recursive_absolute(dir)
	var t := LM.texts({"format": 19},
		[{"id": "p1", "zone": "z1", "contour": [[0, 0], [8.013, 0], [8.013, 6], [0, 6]]}])
	for f in t:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		fa.store_string(t[f])
		fa.close()
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.open_dir(dir)
	var saves := DirAccess.get_directories_at(root.path_join(MapCubeSnap.BACKUP_DIR))
	assert_eq(saves.size(), 1, "copie faite à l'ouverture")
	assert_eq(ed.doc.find("p1").contour[1], [8.0, 0.0], "carte ouverte arrondie")
	assert_eq(FileAccess.get_file_as_string(dir.path_join("pieces.json")), String(t["pieces.json"]), "rien écrit avant Enregistrer")
	ed.open_dir(dir)
	assert_eq(DirAccess.get_directories_at(root.path_join(MapCubeSnap.BACKUP_DIR)).size(), 1, "rouverte : pas de seconde copie")
	ed.queue_free()
	await wait_frames(1)
	EditorMap.root_override = ""
	_wipe(root)


## Carte que l'arrondi rend invalide : deux pièces empilées à 3,098 m (admis,
## à 5 mm près de 3,1 m) ; l'arrondi monte la basse (0,026 -> 0,05) et
## descend la haute (3,124 -> 3,1) : 3,05 m, trop près. L'erreur nouvelle est
## signalée (FR/EN), la carte reste entière, rien n'est retiré. (Le
## validateur travaille sur des cases de 0,5 m dont les bords sont sur la
## grille des cubes : un arrondi au cube ne fait presque jamais changer une
## case ; les altitudes sont le cas qui reste.)
func test_invalid_after_rounding_is_reported_and_kept() -> void:
	var t := LM.texts({"format": 19},
		[{"id": "p1", "nom": "Bas", "zone": "z1", "altitude": 0.026, "contour": [[0, 0], [10, 0], [10, 8], [0, 8]]},
			{"id": "p2", "nom": "Haut", "zone": "z1", "altitude": 3.124, "contour": [[0, 0], [5, 0], [5, 8], [0, 8]]}],
		[{"id": "o1", "type": "fenetre", "altitude": 0.026, "position": [8, 0]}],
		[{"id": "s1", "type": "depart", "altitude": 0.026, "position": [7, 4]}])
	var doc := EditorMap.from_texts(t)
	assert_true(doc.cube_changes > 0)
	var before := MapCubeSnap.errors_of(EditorMap._from_texts(t, false))
	assert_false(before.any(func(m): return String(m.fr).contains("se recouvrent")), "avant : empilées assez haut")
	var fresh := doc.cube_check()
	assert_true(fresh.any(func(m): return String(m.fr).contains("se recouvrent")), "erreur nouvelle trouvée : %s" % str(fresh.map(func(m): return m.fr)))
	assert_true(doc.load_notes.any(func(n): return String(n[0]).begins_with("après le passage aux cubes de 5 cm : ") and String(n[1]).begins_with("after the switch to 5 cm cubes: ")),
		"signalée FR/EN : %s" % str(doc.load_notes))
	assert_eq(doc.pieces.size(), 2, "rien retiré")
	assert_eq([float(doc.find("p1").altitude), float(doc.find("p2").altitude)], [0.05, 3.1])
	assert_eq(float(doc.find("o1").altitude), 0.05, "la fenêtre reste au niveau de sa pièce")
	# Une seule fois : un second appel ne double pas les notes.
	var n := doc.load_notes.size()
	doc.cube_check()
	assert_eq(doc.load_notes.size(), n)


func test_editor_edits_land_on_the_grid() -> void:
	var doc := EditorMap.blank()
	doc.pieces.append({"id": "p1", "zone": "z1", "altitude": 0.0, "contour": [[0, 0], [8, 0], [8, 6], [0, 6]]})
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "altitude": 0.0, "position": [4, 6]})
	var before := doc.snapshot()
	# Saisie libre au millimètre (MCP, fichier, glisser) : arrondie au cube à la validation.
	doc.find("p1")["contour"] = [[0, 0], [8.013, 0], [8.013, 6.02], [0, 6.02]]
	doc.find("p1")["plafond"] = 3.33
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "caisse", "altitude": 0.0, "position": [2.013, 2.017]})
	var n := MapCubeSnap.snap_edited(before, doc)
	assert_true(n > 0)
	assert_eq(doc.find("p1").contour[2], [8.0, 6.0])
	assert_eq(float(doc.find("p1").plafond), 3.35)
	assert_eq(doc.find("o1").position, [4.0, 6.0], "fenêtre du mur changé : suit l'arrondi")
	assert_eq(doc.find("d1").position, [2.013, 2.017], "décor : inchangé")
	assert_eq(MapCubeSnap.snap_edited(doc.snapshot(), doc), 0, "rien de changé : rien à arrondir")
	# Rotation libre d'une pièce : sommets sur la grille ; déplacement de même.
	var r := MapTransform.rotated(doc.find("p1"), Vector2(4, 3), 30.0)
	for q in r.contour:
		assert_true(MapGeom.on_cube(float(q[0])) and MapGeom.on_cube(float(q[1])), "pièce tournée : %s" % str(q))
	var s := MapTransform.shifted(doc.find("p1"), Vector2(0.013, 0.021))
	assert_eq(s.contour[0], [0.0, 0.0], "pièce déplacée au cube")
	assert_true(MapGeom.v2(MapTransform.shifted(doc.find("d1"), Vector2(0.013, 0)).position).is_equal_approx(Vector2(2.026, 2.017)), "décor déplacé au mm")
	# Aimantation libre : le cube de 5 cm.
	assert_eq(MapSnap.step_of("libre", 0.5), 0.05)
	assert_eq(MapSnap.on_step(Vector2(1.012, 2.037), "libre", 0.5), Vector2(1.0, 2.05))
	var p30 := MapGeom.snap_angle_free(Vector2(2, 12), Vector2(5.5, 10.1), 15.0, false)
	assert_true(MapGeom.on_cube(p30.x) and MapGeom.on_cube(p30.y), "tracé à 15° : %s" % p30)
	var p45 := MapGeom.snap_angle_free(Vector2(2, 2), Vector2(5.03, 5.11), 15.0, false)
	assert_true(absf((p45 - Vector2(2, 2)).x - (p45 - Vector2(2, 2)).y) < 1e-6 and MapGeom.on_cube(p45.x), "45° exact sur la grille : %s" % p45)


## Plafond sous une dalle : une seule face (le plafond), pas de scintillement
## avec le dessous de la dalle ni avec le dessous des murs du dessus.
func test_ceiling_is_the_slab_underside() -> void:
	var CU := CUF
	var doc: EditorMap = CU._two_floors()
	var data: Dictionary = MapPreviewWorld.compute(doc).data
	assert_true(MapLayoutExport.off_grid(data).is_empty())
	var root := MeshMapGeometry.build(data)
	var off := MapGeom.WORLD_OFFSET
	# Sous la pièce du dessus (plafond = dessous de la dalle), puis sous un mur
	# du dessus posé au-dessus de la pièce du bas.
	for at in [Vector3(2 + off, 1.6, 4 + off), Vector3(5.1 + off, 1.6, 4 + off)]:
		var h: Dictionary = CU._hit(root, at, true)
		assert_false(h.is_empty(), "une face au-dessus")
		assert_eq(String(h.get("name", "")).split("__")[-1], "ceil", "plafond vu d'en bas : %s" % h.get("name", ""))
		assert_eq(String(h.get("tie", "")), "", "une seule face : %s / %s" % [h.get("name", ""), h.get("tie", "")])
	root.free()


static func _wipe(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		EditorMap._remove_tree(dir)
