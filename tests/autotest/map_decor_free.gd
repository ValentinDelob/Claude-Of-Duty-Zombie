extends AutotestScenario
## Décor posé librement dans le vrai éditeur (docs/MAP_OBJECTS.md § 8), de
## bout en bout :
##   1. le bug du papier peint : un bureau, une caisse, un baril, un interrupteur
##      du courant et une porte glissés à la souris contre un mur (et dedans) ne
##      changent la texture d'AUCUN mur, ni dans les données de l'aperçu 3D
##      ni dans la description construite par le jeu ;
##   2. baril, caisse, étagère tournée et applique posés depuis la barre
##      rapide contre et dans les murs, au centimètre ; hauteur de l'applique
##      réglée dans les propriétés ; carte enregistrée, rouverte (tout à sa
##      place), puis TESTER : collisions à la vraie place du décor (rien à la
##      place arrondie), murs entiers, applique à sa hauteur.

const Free := preload("res://tests/test_map_decor_free.gd")
const OFF := MapGeom.WORLD_OFFSET

var ed: MapEditor
var cv: MapCanvas


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(3)
	var ref := Free.probes(Free.layout(Free.two_rooms()))
	var doc := Free.two_rooms()
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "bureau", "altitude": 0, "position": [4.0, 5.0], "rot": 0})
	doc.objets.append({"id": "d2", "type": "caisse", "altitude": 0, "position": [9.25, 4.25]})
	doc.objets.append({"id": "d3", "type": "baril", "altitude": 0, "position": [10.0, 7.0]})
	doc.objets.append({"id": "w1", "type": "courant", "altitude": 0, "position": [6.75, 10.0], "mur": "s"})
	ed.new_map(true)
	ed._reset(doc)
	await frames(2)
	cv.zoom = 26.0
	cv.origin = Vector2(40, 40)
	cv.set_snap_mode("libre")
	ed.select_mouse()

	# 1. Objets glissés contre (et dans) les murs : textures des murs inchangées.
	await drag(Vector2(4.0, 5.0), Vector2(0.9, 5.0))      # bureau contre le mur ouest (à 0,15 m dans le mur)
	await drag(Vector2(9.25, 4.25), Vector2(13.6, 3.6))   # caisse dans le mur mitoyen
	await drag(Vector2(10.0, 7.0), Vector2(13.9, 0.3))    # baril dans l'angle nord-est de A
	await drag(Vector2(6.75, 9.6), Vector2(0.9, 9.6))     # interrupteur vers l'angle sud-ouest
	await drag(Vector2(14.0, 5.25), Vector2(14.0, 9.2))   # porte au bout sud du mur mitoyen
	var moved := {}
	for id in ["d1", "d2", "d3", "w1", "o1"]:
		moved[id] = MapGeom.v2(ed.doc.find(id).position)
	print("[decor] positions après glisser : %s" % str(moved))
	at.check(moved.d1.distance_to(Vector2(0.9, 5.0)) < 0.02, "bureau glissé contre le mur, au centimètre (%s)" % moved.d1)
	at.check(moved.d2.distance_to(Vector2(13.6, 3.6)) < 0.02, "caisse glissée dans le mur mitoyen (%s)" % moved.d2)
	at.check(moved.d3.distance_to(Vector2(13.9, 0.3)) < 0.02, "baril glissé dans l'angle (%s)" % moved.d3)
	at.check(moved.w1.x < 2.0 and moved.w1.y == 10.0, "interrupteur glissé vers l'angle (%s)" % moved.w1)
	at.check(moved.o1.y > 7.5 and moved.o1.x == 14.0, "porte glissée au bout du mur (%s)" % moved.o1)
	var door_span := Vector2(moved.o1.y - 1.3, moved.o1.y + 1.3)
	var preview := MapPreviewWorld.compute(ed.doc)
	at.check(preview.errors == 0, "aperçu 3D : carte sans erreur (%d)" % preview.errors)
	at.check(_wall_diff(ref, Free.probes(preview.data), door_span) == "", "aperçu 3D : texture de chaque mur inchangée %s" % _wall_diff(ref, Free.probes(preview.data), door_span))
	var game_data := EditorMapDef.from_map(ed.doc, "perso:decor").layout_data
	at.check(_wall_diff(ref, Free.probes(game_data), door_span) == "", "jeu : texture de chaque mur inchangée %s" % _wall_diff(ref, Free.probes(game_data), door_span))
	at.check(Free.wall_mat_at(game_data, 14.2, 3.6) == "wall_green", "mur mitoyen entier derrière la caisse, côté B en vert")

	# 2. Pose libre depuis la barre rapide (au centimètre, sans grille).
	var old_ids := ed.doc.objets.map(func(o): return String(o.id))
	ed.set_hotbar(8, "baril")
	await click(Vector2(0.2, 3.0))                         # à cheval sur le mur ouest
	ed.set_hotbar(8, "caisse")
	await click(Vector2(5.37, 7.21))                       # hors de la grille
	ed.set_hotbar(8, "prefab:etagere")
	ed.place_rot = 37
	await click(Vector2(1.0, 1.0))                         # tournée dans l'angle nord-ouest
	ed.set_hotbar(8, "luminaire:applique")
	await click(Vector2(6.37, 0.6))                        # contre le mur nord, au centimètre
	var placed := {}
	for o: Dictionary in ed.doc.objets:
		if old_ids.has(String(o.id)):
			continue
		placed[String(o.get("prefab", o.get("luminaire", o.type)))] = o
	print("[decor] posés : %s" % str(placed.keys()))
	at.check(placed.has("baril") and MapGeom.v2(placed.baril.position).distance_to(Vector2(0.2, 3.0)) < 0.006, "baril posé à cheval sur le mur %s" % cv.refusal)
	at.check(placed.has("caisse") and MapGeom.v2(placed.caisse.position).distance_to(Vector2(5.37, 7.21)) < 0.006, "caisse posée au centimètre %s" % cv.refusal)
	at.check(placed.has("etagere") and int(placed.etagere.get("rot", 0)) == 37, "étagère tournée de 37° dans l'angle %s" % cv.refusal)
	at.check(placed.has("applique") and placed.applique.position == [6.37, 0.0] and placed.applique.mur == "n", "applique contre le mur nord, au centimètre %s" % cv.refusal)
	if placed.size() < 4:
		return
	# Hauteur de l'applique : propriétés (outil Sélection), champ « Hauteur ».
	ed.select_mouse()
	ed.select(String(placed.applique.id))
	await frames(2)
	var spin := _spin_of(Lang.t("Hauteur", "Height"))
	at.check(spin != null and absf(spin.value - 2.0) < 0.001, "champ Hauteur de l'applique (2 m par défaut)")
	if spin == null:
		return
	spin.value = 0.65
	await frames(1)
	at.check(is_equal_approx(float(ed.doc.find(String(placed.applique.id)).get("hauteur", 0.0)), 0.65), "applique réglée à 0,65 m")

	# Enregistrée (format 7), rouverte : tout à sa place.
	at.check(ed.save(), "carte enregistrée")
	var dir := ed.map_dir
	var carte = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	at.check(carte is Dictionary and int(carte.get("format", 0)) == EditorMap.FORMAT and EditorMap.FORMAT >= 7, "fichier au format 7 et plus")
	var before := ed.doc.objets.duplicate(true)
	ed.new_map(true)
	ed.open_dir(dir)
	await frames(2)
	var same := true
	for o: Dictionary in before:
		var b := ed.doc.find(String(o.id))
		if b.is_empty() or str(b.get("position")) != str(o.get("position")) or int(b.get("rot", 0)) != int(o.get("rot", 0)) \
				or str(b.get("hauteur", "")) != str(o.get("hauteur", "")):
			same = false
			print("[decor] relu différent : %s / %s" % [str(o), str(b)])
	at.check(same, "relue : chaque objet à sa place, tourné et à sa hauteur")
	var check := ed.doc.objets.filter(func(o): return MapCatalog.is_decor(o) and not MapRules.check_existing(ed.doc, o).ok)
	at.check(check.is_empty(), "décor relu : aucun en rouge (%s)" % str(check.map(func(o): return o.id)))

	# TESTER : le jeu construit la carte.
	if not ed.test_map():
		at.fail("TESTER refusé : %s" % str(ed.validator.errors().map(func(m): return m.fr) if ed.validator else []))
		return
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée"):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	p.teleport_to(Vector3(7.0 + OFF, 0.05, 6.0 + OFF), 0.0)
	await seconds(0.3)
	var played: Dictionary = (game.map_def as EditorMapDef).layout_data
	at.check(_wall_diff(ref, Free.probes(played), door_span) == "", "en jeu : texture de chaque mur inchangée")
	var space := p.get_world_3d().direct_space_state
	# Mur mitoyen entier derrière la caisse (pas de trou) : un rayon depuis B
	# s'arrête sur la face du mur.
	var h := _ray(space, Vector3(16.0, 0.5, 3.6), Vector3(12.0, 0.5, 3.6))
	at.check(not h.is_empty() and absf(h.position.x - (14.25 + OFF)) < 0.03, "mur mitoyen entier derrière la caisse (touché en x = %s)" % (str(h.position.x - OFF) if not h.is_empty() else "rien"))
	# Baril à cheval sur le mur ouest : sa collision à sa vraie place.
	h = _ray(space, Vector3(3.0, 0.5, 3.0), Vector3(-1.0, 0.5, 3.0))
	at.check(not h.is_empty() and absf(h.position.x - (0.45 + OFF)) < 0.03, "baril : collision à sa vraie place (x = %s, bord à 0,45)" % (str(h.position.x - OFF) if not h.is_empty() else "rien"))
	# Caisse au centimètre (4,87..5,87 × 6,71..7,71) : touchée à sa place,
	# rien à la place arrondie des cases (4,75..5,75).
	h = _ray(space, Vector3(5.82, 0.5, 5.5), Vector3(5.82, 0.5, 9.0))
	at.check(not h.is_empty() and absf(h.position.z - (6.71 + OFF)) < 0.03, "caisse au centimètre : collision à sa place (z = %s)" % (str(h.position.z - OFF) if not h.is_empty() else "rien"))
	h = _ray(space, Vector3(4.80, 0.5, 5.5), Vector3(4.80, 0.5, 9.0))
	at.check(h.is_empty() or h.position.z > 8.0 + OFF, "rien à la place arrondie de la caisse (%s)" % (str(h.position - Vector3(OFF, 0, OFF)) if not h.is_empty() else "libre"))
	# Bureau contre le mur ouest : sa collision suit sa place.
	h = _ray(space, Vector3(3.0, 0.5, 5.0), Vector3(-1.0, 0.5, 5.0))
	at.check(not h.is_empty() and h.position.x > 1.2 + OFF and h.position.x < 1.8 + OFF, "bureau : collision à sa place (x = %s)" % (str(h.position.x - OFF) if not h.is_empty() else "rien"))
	# Applique à 0,65 m : sa lumière devant le mur nord.
	var want := Vector3(6.37 + OFF, 0.65, 0.45 + OFF)
	var lights := game.world.find_children("*", "Light3D", true, false).filter(func(l): return (l as Node3D).global_position.distance_to(want) < 0.15)
	at.check(not lights.is_empty(), "applique éclairée à 0,65 m du sol, au centimètre")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(root)


## Différences de textures de murs, sauf sur la largeur de la porte (son
## ancienne et sa nouvelle place sur le mur mitoyen).
func _wall_diff(ref: Dictionary, got: Dictionary, door_span: Vector2) -> String:
	var bad := []
	for k in ref:
		var xy := String(k).split(":")
		var x := float(xy[0])
		var y := float(xy[1])
		if absf(x - 14.0) < 0.5 and ((y > 4.25 and y < 6.25) or (y > door_span.x and y < door_span.y)):
			continue
		if String(ref[k]) != String(got.get(k, "?")):
			bad.append("%s : %s -> %s" % [k, ref[k], got.get(k, "?")])
	return ", ".join(bad.slice(0, 6))


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var o := Vector3(OFF, 0, OFF)
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(a + o, b + o, 1))


## Champ numérique des propriétés dont la ligne porte ce libellé.
func _spin_of(label: String) -> SpinBox:
	for s: SpinBox in ed.find_children("*", "SpinBox", true, false):
		var row := s.get_parent()
		for c in row.get_children():
			if c is Label and (c as Label).text.begins_with(label):
				return s
	return null


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _motion(m: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = cv.to_px(m)
	cv._gui_input(e)


func _button(m: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = cv.to_px(m)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	cv._gui_input(e)


func click(m: Vector2) -> void:
	_motion(m)
	_button(m, true)
	_button(m, false)
	await frames(1)


func drag(a: Vector2, b: Vector2) -> void:
	_motion(a)
	_button(a, true)
	for i in 4:
		_motion(a.lerp(b, (i + 1) / 4.0))
		await frames(1)
	_button(b, false)
	await frames(1)
