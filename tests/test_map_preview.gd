extends TestCase
## APERÇU 3D de l'éditeur de cartes (scripts/editor/map_preview_*.gd,
## docs/MAP_AUTHORING.md §2 ter) : même géométrie que le jeu sur DRAFT ARENA
## (même description, mêmes nœuds, collisions, lampes, objets de jeu), mise à
## jour toute seule après un ajout, une suppression, une annulation (hors du
## fil principal, seuls les morceaux changés), options (plafonds masqués,
## courant, étages), sélection par un rayon, vue joueur arrêtée par les murs,
## réglages mémorisés, aucun rendu quand l'aperçu est masqué, temps de mise à
## jour sur une carte de 50 pièces.

const TMP := "res://tests/_out/test_map_preview"
const OFF := MapGeom.WORLD_OFFSET


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ outils

func _world(doc: EditorMap) -> MapPreviewWorld:
	var w := MapPreviewWorld.new()
	host.add_child(w)
	w.doc = doc
	w.auto = false
	return w


## Libéré après les ajouts différés des objets de jeu (fin d'image).
func _free(w: Node) -> void:
	w.queue_free()
	await wait_frames(2)


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	return ed


func _until(cond: Callable, limit: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await wait_frames(1)
	return true


## Deux salles collées, une porte, deux fenêtres, départ, boîte, arme, atout.
static func _base() -> EditorMap:
	var doc := EditorMap.blank("apercu_test", "APERCU", "PREVIEW")
	for r in [[0, 0, 14, 10], [14, 0, 24, 10]]:
		var z := doc.add_zone("Salle", "Room")
		doc.pieces.append({"id": doc.new_id("p"), "nom": "Salle", "altitude": 0, "zone": String(z.id),
			"contour": [[r[0], r[1]], [r[2], r[1]], [r[2], r[3]], [r[0], r[3]]]})
	doc.depart = String(doc.zones[0].id)
	for o in [{"type": "porte", "position": [14.0, 5.25], "largeur": 2.0, "prix": 750},
			{"type": "fenetre", "position": [3.25, 0.0]}, {"type": "fenetre", "position": [19.25, 0.0]}]:
		o["id"] = doc.new_id("o")
		o["altitude"] = 0.0
		doc.ouvertures.append(o)
	for o in [{"type": "depart", "position": [9.0, 7.0]}, {"type": "boite", "position": [6.75, 10.0], "mur": "s", "depart": false},
			{"type": "arme", "arme": "m14", "position": [11.25, 10.0], "mur": "s"}, {"type": "atout", "atout": "titan", "position": [24.0, 5.0], "mur": "e"}]:
		o["id"] = doc.new_id("x")
		o["altitude"] = 0.0
		doc.objets.append(o)
	return doc


static func _names(root: Node, type: String) -> Array:
	var out := []
	for n in root.find_children("*", type, true, false):
		out.append(String(n.name))
	out.sort()
	return out


# ------------------------------------------------------------------ même géométrie que le jeu

func test_same_geometry_as_the_game_on_draft_arena() -> void:
	var doc := EditorMap.load_dir("res://assets/maps/draft_arena/")
	# Le jeu : carte validée, décrite, construite (MeshMapBuilder).
	var def := EditorMapDef.from_map(doc.duplicate_map(), "draft_arena")
	assert_true(def.is_valid(), "DRAFT ARENA jouable")
	var game_world := Node3D.new()
	host.add_child(game_world)
	var layout := def.create_layout() as MeshMapLayout
	var _props := layout.build(game_world) as MapProps
	# L'aperçu.
	var w := _world(doc)
	w.rebuild_now()
	assert_eq(w.errors, 0, "aucune erreur relevée")
	assert_true(w.data == def.layout_data, "même description en maillage que le jeu (MapLayoutExport)")
	var arch_game: Node = game_world.find_child("Architecture", true, false)
	var arch_prev: Node = w.groups.arch
	assert_eq(_names(arch_prev, "MeshInstance3D"), _names(arch_game, "MeshInstance3D"), "mêmes maillages (murs, sols, plafonds, escalier)")
	assert_eq(_names(arch_prev, "StaticBody3D"), _names(arch_game, "StaticBody3D"), "mêmes collisions")
	var game_boxes := game_world.find_children("*", "CollisionBox", true, false).size()
	var prev_boxes := 0
	for p in ["arch", "decor", "lamps"]:
		prev_boxes += (w.groups[p] as Node).find_children("*", "CollisionBox", true, false).size()
	assert_eq(prev_boxes, game_boxes, "mêmes pavés CollisionBox")
	# Lampes : mêmes positions, énergies, portées et ombres (code commun add_lamp).
	var lamps_game := game_world.find_children("Lamp*", "OmniLight3D", true, false)
	var lamps_prev := (w.groups.lamps as Node).find_children("Lamp*", "OmniLight3D", true, false)
	assert_eq(lamps_prev.size(), lamps_game.size(), "même nombre de lampes (%d)" % lamps_game.size())
	assert_true(lamps_game.size() > 5, "des lampes")
	for i in mini(lamps_game.size(), lamps_prev.size()):
		var a := lamps_game[i] as OmniLight3D
		var b := lamps_prev[i] as OmniLight3D
		assert_true(a.position.is_equal_approx(b.position) and is_equal_approx(a.omni_range, b.omni_range) and a.shadow_enabled == b.shadow_enabled,
			"lampe %d identique" % i)
	# Objets de jeu : portes, fenêtres barricadées, atouts, armes, boîte, courant.
	var stuff: Node = w.groups.stuff
	assert_eq(stuff.find_children("*", "Door", true, false).size(), layout.doors().size(), "portes")
	assert_eq(stuff.find_children("*", "Barricade", true, false).size(), 7, "7 fenêtres barricadées")
	assert_eq(stuff.find_children("*", "PerkMachine", true, false).size(), layout.perks().size(), "atouts")
	assert_eq(stuff.find_children("*", "WallBuy", true, false).size(), layout.wall_buys().size(), "armes murales")
	assert_eq(stuff.find_children("*", "MysteryBox", true, false).size(), 1, "boîte")
	assert_eq(stuff.find_children("*", "PowerSwitch", true, false).size(), 1, "interrupteur du courant")
	# Figés : aucun calcul par image dans l'éditeur.
	for n in stuff.find_children("*", "Interactable", true, false):
		assert_false(n.is_processing() or n.is_physics_processing(), "objet figé : %s" % n.name)
	game_world.free()
	_props = null
	await _free(w)


func test_unfinished_map_is_shown() -> void:
	# Une pièce seule : ni départ, ni fenêtre, ni boîte (carte en cours).
	var doc := EditorMap.blank("en_cours", "EN COURS", "WIP")
	var z := doc.add_zone("A", "A")
	doc.pieces.append({"id": "p1", "nom": "A", "altitude": 0, "zone": String(z.id), "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]})
	var w := _world(doc)
	w.rebuild_now()
	assert_false(w.data.is_empty(), "description construite")
	assert_true((w.groups.arch as Node).find_children("*__floor", "MeshInstance3D", true, false).size() >= 1, "sol de la pièce")
	assert_true((w.groups.arch as Node).find_children("*__block", "MeshInstance3D", true, false).size()
		+ (w.groups.arch as Node).find_children("*__wall", "MeshInstance3D", true, false).size() >= 1, "murs de la pièce")
	# Carte vide : rien.
	doc.pieces.clear()
	w.rebuild_now()
	assert_true(w.data.is_empty() and (w.groups.arch as Node).get_child_count() == 0, "carte vide : aperçu vide")
	await _free(w)


# ------------------------------------------------------------------ mise à jour en direct

func test_live_update_after_add_delete_undo() -> void:
	var ed := await _editor()
	var pv := ed.preview
	var w := pv.world
	pv.pause_unfocused = false
	for r in [[2, 2, 12, 10], [12, 2, 20, 10]]:
		ed.add_object({"contour": [[r[0], r[1]], [r[2], r[1]], [r[2], r[3]], [r[0], r[3]]]}, 0)
	# Masqué : rien n'est construit.
	await wait_frames(8)
	assert_eq(w.builds, 0, "aperçu masqué : aucune construction")
	pv.set_shown(true)
	assert_true(await _until(func(): return w.builds > 0 and w.idle() and not w.is_stale(), 8.0), "première construction")
	var floors0 := (w.groups.arch as Node).find_children("*__floor", "MeshInstance3D", true, false).size()
	assert_true(floors0 >= 1, "sols construits")
	# Ajout d'un luminaire : seules les lampes sont refaites.
	var n0 := (w.groups.lamps as Node).find_children("*", "OmniLight3D", true, false).size()
	var arch_before: Node = w.groups.arch
	var lamp := ed.add_object({"type": "luminaire", "luminaire": "suspension", "position": [6.0, 6.0], "rot": 0,
		"couleur": "#ffc88a", "intensite": 2.0, "portee": 8.0, "courant": true, "vacille": false}, 0)
	var t0 := Time.get_ticks_msec()
	assert_true(await _until(func(): return w.idle() and not w.is_stale(), 8.0), "mise à jour après l'ajout")
	var dt := Time.get_ticks_msec() - t0
	var n1 := (w.groups.lamps as Node).find_children("*", "OmniLight3D", true, false).size()
	assert_eq(n1, n0 + 1, "le luminaire apparaît (%d -> %d lampes)" % [n0, n1])
	assert_eq(w.last_times.parts, ["lamps"], "seules les lampes sont reconstruites")
	assert_true(w.groups.arch == arch_before, "architecture gardée")
	assert_true(dt >= int(MapPreviewWorld.DELAY * 1000.0) - 50, "après le délai de %.1f s (%d ms)" % [MapPreviewWorld.DELAY, dt])
	# Suppression, puis annulation.
	ed.delete_element(String(lamp.id))
	assert_true(await _until(func(): return w.idle() and not w.is_stale(), 8.0), "mise à jour après la suppression")
	assert_eq((w.groups.lamps as Node).find_children("*", "OmniLight3D", true, false).size(), n0, "luminaire retiré")
	ed.undo()
	assert_true(await _until(func(): return w.idle() and not w.is_stale(), 8.0), "mise à jour après l'annulation")
	assert_eq((w.groups.lamps as Node).find_children("*", "OmniLight3D", true, false).size(), n0 + 1, "luminaire revenu (annuler)")
	# Nouvelle pièce : l'architecture change.
	ed.add_object({"contour": [[20, 2], [26, 2], [26, 10], [20, 10]]}, 0)
	assert_true(await _until(func(): return w.idle() and not w.is_stale(), 8.0), "mise à jour après la pièce")
	assert_true(w.last_times.parts.has("arch") and w.groups.arch != arch_before, "architecture refaite")
	assert_true((w.groups.arch as Node).find_children("*__floor", "MeshInstance3D", true, false).size() >= floors0, "sol de la nouvelle pièce")
	ed.queue_free()
	await wait_frames(2)


# ------------------------------------------------------------------ options, sélection, vue joueur

func test_display_options() -> void:
	var doc := EditorMap.load_dir("res://assets/maps/draft_arena/")
	var w := _world(doc)
	w.rebuild_now()
	var ceils := (w.groups.arch as Node).find_children("*__ceil", "MeshInstance3D", true, false)
	assert_true(ceils.size() > 0, "plafonds")
	w.set_options({"ceil": true})
	assert_true(ceils.all(func(n): return not n.visible), "plafonds masqués")
	assert_true((w.groups.arch as Node).find_children("*__floor", "MeshInstance3D", true, false).all(func(n): return n.visible), "sols toujours visibles")
	w.set_options({"ceil": false})
	assert_true(ceils.all(func(n): return n.visible), "plafonds de nouveau visibles")
	# Courant : les lampes liées au courant passent de faibles à allumées.
	var lamp := (w.groups.lamps as Node).find_children("Lamp*", "OmniLight3D", true, false)[0] as OmniLight3D
	w.set_options({"power": false})
	var off_e := lamp.light_energy
	assert_true(lamp.light_color.is_equal_approx(PowerGrid.OFF_COLOR), "courant coupé : lumière pâle")
	w.set_options({"power": true})
	assert_true(lamp.light_energy > off_e * 2.0, "courant rétabli : lampe allumée (%.2f > %.2f)" % [lamp.light_energy, off_e])
	# Étages : seulement l'étage 1 (la passerelle), puis jusqu'à l'étage 0.
	w.set_view_floor(1)
	w.set_options({"floors": MapPreviewWorld.Floors.ONLY})
	var floor_meshes := (w.groups.arch as Node).find_children("*__floor", "MeshInstance3D", true, false)
	var low := floor_meshes.filter(func(n): return (n as MeshInstance3D).get_aabb().position.y < 1.0)
	var high := floor_meshes.filter(func(n): return (n as MeshInstance3D).get_aabb().position.y > 3.0)
	assert_true(not low.is_empty() and not high.is_empty(), "sols des deux étages")
	assert_true(low.all(func(n): return not n.visible) and high.all(func(n): return n.visible), "étage 1 seulement")
	w.set_view_floor(0)
	w.set_options({"floors": MapPreviewWorld.Floors.UP_TO})
	assert_true(low.all(func(n): return n.visible) and high.all(func(n): return not n.visible), "jusqu'à l'étage 0")
	w.set_options({"floors": MapPreviewWorld.Floors.ALL})
	assert_true(floor_meshes.all(func(n): return n.visible), "tous les étages")
	# Éclairage plein : lumière ambiante forte, sans brume.
	w.set_options({"full": true})
	assert_true(w.env.ambient_light_energy > 1.0 and not w.env.fog_enabled, "éclairage plein")
	w.set_options({"full": false})
	assert_true(w.env.fog_enabled, "éclairage de jeu")
	await _free(w)


## Le clic choisit ce que l'utilisateur VOIT : un plafond vu d'au-dessus (face
## non rendue) est traversé, le sol vu d'en haut reste la pièce, un étage
## masqué est ignoré.
func test_pick_sees_through_unrendered_faces() -> void:
	var doc := _base()
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [19.0, 5.0]})
	var w := _world(doc)
	w.rebuild_now()
	w.set_options({"ceil": false, "floors": MapPreviewWorld.Floors.ALL})
	var rig := w.rig
	rig.yaw = 0.0
	rig.pitch = -1.5
	rig.dist = 15.0
	var center := Vector2(w.viewport.size) * 0.5
	# Plafonds affichés, caméra au-dessus : le décor sous le plafond.
	rig.pivot = Vector3(19.0 + OFF, 0.0, 5.0 + OFF)
	rig._apply()
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	assert_eq(w.pick(center), "d1", "décor sous un plafond vu d'au-dessus")
	# Le sol nu vu d'en haut : la pièce.
	rig.pivot = Vector3(16.0 + OFF, 0.0, 8.0 + OFF)
	rig._apply()
	await host.get_tree().physics_frame
	assert_eq(w.pick(center), String(doc.pieces[1].id), "sol de la salle B : la pièce")
	# Le rayon passe le plafond (vu de dos) et s'arrête au sol.
	var hit := w.ray(center)
	assert_true(not hit.is_empty() and hit.position.y < 0.5, "d'en haut, le rayon s'arrête au sol")
	await _free(w)
	# Étage du dessus au-dessus de la salle B : choisi en vue de tous les
	# étages, ignoré quand seul le rez-de-chaussée est montré.
	var doc2 := _base()
	doc2.objets.append({"id": "d1", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [19.0, 5.0]})
	var z := doc2.add_zone("Haut", "Up")
	doc2.pieces.append({"id": "p_haut", "nom": "Haut", "altitude": 1 * EditorMap.FLOOR_STEP, "zone": String(z.id), "contour": [[14, 0], [24, 0], [24, 10], [14, 10]]})
	var w2 := _world(doc2)
	w2.rebuild_now()
	w2.set_options({"ceil": false, "floors": MapPreviewWorld.Floors.ALL})
	w2.rig.yaw = 0.0
	w2.rig.pitch = -1.5
	w2.rig.dist = 15.0
	w2.rig.pivot = Vector3(19.0 + OFF, 0.0, 5.0 + OFF)
	w2.rig._apply()
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var c2 := Vector2(w2.viewport.size) * 0.5
	assert_eq(w2.pick(c2), "p_haut", "tous les étages : le sol de l'étage du dessus")
	w2.view_floor = 0
	w2.set_options({"floors": MapPreviewWorld.Floors.ONLY})
	await host.get_tree().physics_frame
	assert_eq(w2.pick(c2), "d1", "étage du dessus masqué : ignoré, le décor du rez-de-chaussée")
	await _free(w2)


func test_pick_and_highlight() -> void:
	var doc := _base()
	var w := _world(doc)
	w.rebuild_now()
	await wait_frames(2)
	# Caméra au-dessus de la salle B (plafonds masqués), vue vers le bas.
	w.set_options({"ceil": true})
	var rig := w.rig
	rig.pivot = Vector3(19.0 + OFF, 0.0, 5.0 + OFF)
	rig.pitch = -1.5
	rig.yaw = 0.0
	rig.dist = 15.0
	rig._apply()
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var center := Vector2(w.viewport.size) * 0.5
	var id := w.pick(center)
	assert_eq(id, String(doc.pieces[1].id), "clic au milieu : la salle B")
	# Plafonds visibles : le rayon s'arrête au plafond, toujours la salle B.
	w.set_options({"ceil": false})
	assert_eq(w.pick(center), String(doc.pieces[1].id), "plafond de la salle B")
	# Surlignage de l'élément choisi.
	w.selected_id = String(doc.objets[3].id)
	w.update_overlay()
	var im := (w.get_node("PreviewViewport/PreviewWorld/Highlight") as MeshInstance3D).mesh as ImmediateMesh
	assert_true(im.get_surface_count() == 2, "atout surligné (traits et faces)")
	w.selected_id = ""
	w.update_overlay()
	assert_eq(im.get_surface_count(), 0, "rien de surligné")
	await _free(w)


func test_player_view_does_not_cross_a_wall() -> void:
	var doc := _base()
	var w := _world(doc)
	w.rebuild_now()
	await wait_frames(2)
	var rig := w.rig
	rig.pivot = Vector3(7.0 + OFF, 0.0, 5.0 + OFF)
	rig.pitch = -0.4
	rig._apply()
	rig.set_mode(MapPreviewCamera.Mode.WALK, w.ground_below)
	assert_eq(rig.mode, MapPreviewCamera.Mode.WALK, "vue joueur")
	assert_near(rig.walker.global_position.y, 0.05, 0.1, "posée au sol")
	# Face au mur nord de la salle A (y = 0) : on avance 1,5 s.
	rig.walker.global_position = Vector3(8.0 + OFF, 0.05, 3.0 + OFF)
	rig.yaw = 0.0
	rig.move = Vector2(0, 1)
	for i in 90:
		await host.get_tree().physics_frame
	rig.move = Vector2.ZERO
	var z := rig.walker.global_position.z - OFF
	assert_true(z > MapGeom.WALL_HALF + Player.RADIUS - 0.05, "arrêtée par le mur (y = %.2f m)" % z)
	assert_near(rig.eye().y - rig.walker.global_position.y, Player.EYE_HEIGHT, 0.01, "yeux à %.2f m" % Player.EYE_HEIGHT)
	# La porte fermée se traverse (visite) : de la salle A à la salle B.
	rig.walker.global_position = Vector3(12.5 + OFF, 0.05, 5.25 + OFF)
	rig.yaw = -PI * 0.5
	rig.move = Vector2(0, 1)
	for i in 60:
		await host.get_tree().physics_frame
	rig.move = Vector2.ZERO
	assert_true(rig.walker.global_position.x - OFF > 14.5, "passée par la porte (x = %.2f m)" % (rig.walker.global_position.x - OFF))
	await _free(w)


# ------------------------------------------------------------------ réglages, rendu, temps

func test_state_is_remembered() -> void:
	var ed := await _editor()
	var pv := ed.preview
	pv.set_shown(true)
	pv.set_option("ceil", true)
	pv.set_option("floors", MapPreviewWorld.Floors.UP_TO)
	pv.set_option("power", false)
	pv.set_render_scale(0.5)
	pv.set_follow(true)
	pv.set_camera_mode(MapPreviewCamera.Mode.FLY)
	pv.position = Vector2(100, 90)
	pv.size = Vector2(500, 330)
	pv.save_prefs()
	var saved: Dictionary = MapEditor.pref(MapPreviewPanel.PREF_KEY, {})
	assert_eq(saved.get("visible"), true, "visible mémorisé")
	ed.queue_free()
	await wait_frames(2)
	var ed2 := await _editor()
	await wait_frames(2)
	var p2 := ed2.preview
	assert_true(p2.shown and p2.visible, "rouvert affiché")
	assert_true(p2.world.hide_ceilings and p2.world.floors_mode == MapPreviewWorld.Floors.UP_TO and not p2.world.power_on, "options relues")
	assert_near(p2.render_scale, 0.5, 0.001, "résolution relue")
	assert_true(p2.follow and p2.world.rig.mode == MapPreviewCamera.Mode.FLY, "caméra et suivi relus")
	assert_true(p2.position.is_equal_approx(Vector2(100, 90)) and p2.size.is_equal_approx(Vector2(500, 330)), "position et taille relues (%s %s)" % [p2.position, p2.size])
	# Valeurs piégées : ignorées.
	p2.apply_state({"rect": ["x", 1, 2], "scale": "gros", "floors": 99, "camera": -4})
	assert_near(p2.render_scale, 0.75, 0.001, "échelle invalide ignorée")
	assert_eq(int(p2.world.floors_mode), 2, "étages bornés")
	ed2.queue_free()
	await wait_frames(2)


## Regard au clic droit : la souris capturée est toujours rendue, même si le
## relâchement arrive au plan 2D (curseur bloqué au centre de la fenêtre), si
## le relâchement est perdu, ou si l'éditeur perd le focus.
func test_captured_mouse_is_always_given_back() -> void:
	var ed := await _editor()
	var pv := ed.preview
	pv.set_shown(true)
	await wait_frames(2)
	# Relâchement vu par la fenêtre (et non par l'aperçu) : souris rendue, événement consommé.
	pv._rmb = true
	pv._captured = true
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	assert_true(pv._captured_mouse_input(up), "relâchement lu pour toute la fenêtre")
	assert_false(pv._captured, "souris rendue au relâchement")
	assert_false(pv._rmb, "regard terminé")
	# Mouvement pendant la capture : il tourne la caméra de l'aperçu, pas le plan.
	pv._rmb = true
	pv._captured = true
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(40, 0)
	assert_true(pv._captured_mouse_input(mm), "mouvement capturé consommé")
	# Relâchement perdu (bouton déjà relâché) : rendue à l'image suivante.
	await wait_frames(2)
	assert_false(pv._captured, "filet : bouton relâché, souris rendue")
	# Perte du focus.
	pv._rmb = true
	pv._captured = true
	pv._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(pv._captured, "perte du focus : souris rendue")
	assert_false(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "curseur visible")
	# Sans capture, les clics du plan ne sont pas touchés.
	assert_false(pv._captured_mouse_input(up), "sans capture : rien de consommé")
	pv.set_shown(false)
	ed.queue_free()
	await wait_frames(2)


func test_no_render_when_hidden() -> void:
	var ed := await _editor()
	var pv := ed.preview
	pv.pause_unfocused = false
	pv.set_shown(false)
	var r0 := pv.renders
	await wait_frames(10)
	assert_eq(pv.renders, r0, "masqué : aucune image demandée")
	assert_eq(pv.world.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "rendu désactivé")
	assert_false(pv.world.active, "construction en pause")
	pv.set_shown(true)
	await wait_frames(10)
	assert_true(pv.renders > r0, "affiché : rendu")
	# Sans focus (option par défaut) : en pause.
	pv.pause_unfocused = true
	if not pv._app_focused():
		var r1 := pv.renders
		await wait_frames(10)
		assert_eq(pv.renders, r1, "sans focus : aucune image")
	pv.set_shown(false)
	ed.queue_free()
	await wait_frames(2)


func test_update_time_on_a_50_room_map() -> void:
	var doc := EditorMap.blank("grande", "GRANDE", "BIG")
	for row in 2:
		for col in 25:
			var x0 := 2.0 + col * 6.0
			var y0 := 4.0 + row * 6.0
			var z := doc.add_zone("S", "R")
			doc.pieces.append({"id": doc.new_id("p"), "nom": "S", "altitude": 0, "zone": String(z.id),
				"contour": [[x0, y0], [x0 + 6, y0], [x0 + 6, y0 + 6], [x0, y0 + 6]]})
			doc.ouvertures.append({"id": doc.new_id("o"), "altitude": 0, "type": "fenetre", "position": [x0 + 3.25, y0 if row == 0 else y0 + 6]})
			if col > 0:
				doc.ouvertures.append({"id": doc.new_id("o"), "altitude": 0, "type": "porte", "position": [x0, y0 + 3.25], "largeur": 2.0, "prix": 750})
			doc.objets.append({"id": doc.new_id("lu"), "altitude": 0, "type": "luminaire", "luminaire": "suspension", "position": [x0 + 3, y0 + 3], "rot": 0,
				"couleur": "#ffc88a", "intensite": 2.0, "portee": 8.0, "courant": true, "vacille": false})
	doc.ouvertures.append({"id": doc.new_id("o"), "altitude": 0, "type": "porte", "position": [5.25, 10.0], "largeur": 2.0, "prix": 750})
	doc.depart = String(doc.zones[0].id)
	doc.objets.append({"id": doc.new_id("s"), "altitude": 0, "type": "depart", "position": [5.0, 7.0]})
	var w := _world(doc)
	w.auto = true
	w.active = true
	# Mise à jour automatique : conversion dans le fil de travail, construction étalée.
	var _frames := 0
	var worst := 0.0
	var t0 := Time.get_ticks_msec()
	while w.builds == 0 and Time.get_ticks_msec() - t0 < 60000:
		var f0 := Time.get_ticks_usec()
		await wait_frames(1)
		worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
		_frames += 1
	assert_eq(w.builds, 1, "construite")
	assert_eq((w.groups.stuff as Node).find_children("*", "Barricade", true, false).size(), 50, "50 fenêtres")
	print("    [apercu] 50 pieces : conversion %.0f ms (fil de travail), construction %.0f ms en %d etapes (plus longue %.0f ms), delai total %.0f ms, pire image %.0f ms" % [
		w.last_times.thread, w.last_times.apply, w.last_times.parts.size() + 2, w.last_times.step_max, w.last_times.total, worst])
	# Une lampe de plus : seules les lampes (rapide).
	doc.objets.append({"id": doc.new_id("lu"), "altitude": 0, "type": "luminaire", "luminaire": "ampoule", "position": [8.0, 6.0], "rot": 0,
		"couleur": "#ffc88a", "intensite": 2.0, "portee": 8.0, "courant": true, "vacille": false})
	t0 = Time.get_ticks_msec()
	while w.builds == 1 and Time.get_ticks_msec() - t0 < 60000:
		await wait_frames(1)
	assert_eq(w.last_times.parts, ["lamps"], "lampe ajoutée : seulement les lampes")
	print("    [apercu] 50 pieces, lampe ajoutee : conversion %.0f ms, construction %.0f ms, delai total %.0f ms" % [
		w.last_times.thread, w.last_times.apply, w.last_times.total])
	assert_true(w.last_times.step_max < 1500.0, "aucune étape longue sur le fil principal (%.0f ms)" % w.last_times.step_max)
	await _free(w)
