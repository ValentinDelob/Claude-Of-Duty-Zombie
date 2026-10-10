extends AutotestScenario
## FORMES LIBRES dans l'éditeur de cartes, avec les vrais outils (souris et
## clavier envoyés à la vue) : une salle ronde de 32 points posée au cercle
## (un clic au centre puis « 13 Tab 32 Entrée » au clavier), G G : sans
## grille, une annexe tracée au polygone collée au côté est du cercle
## (aimant aux sommets, « 8 Tab 0 Entrée » pour un côté), une porte sur le
## bord commun, deux fenêtres (celle de la salle ronde glissée à la souris sur
## le côté voisin du cercle puis ramenée, sans grille), un mur libre tracé sans
## grille avec l'interrupteur du courant contre sa face nord, un mur courbe (rayon et ouverture au clavier),
## un pilier tourné à 30° avec la poignée de rotation, le départ et la boîte ;
## vérification sans erreur, Ctrl+S (format courant), rechargement identique. Puis
## TESTER : l'interrupteur du mur libre s'actionne depuis son côté ; murs obliques de la
## salle ronde (CollisionBox tournées), un rayon
## arrêté par le mur rond, le mur courbe et le pilier ; des zombies entrent
## par la fenêtre de la salle ronde et rejoignent le joueur en contournant le
## pilier et le mur courbe sans jamais les traverser.
## Captures : tests/_out/shots/map_editor_freeform_*.png.

var ed: MapEditor
var cv: MapCanvas
var off := MapGeom.WORLD_OFFSET
## Trait (y, m) du mur libre tracé dans la salle ronde (l'éditeur est fermé en jeu).
var free_wall_y := 25.0


func run() -> void:
	timeout_sec = 300
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(3)
	ed.new_map(true)
	ed.doc.carte.nom = {"fr": "FORMES LIBRES", "en": "FREE SHAPES"}
	cv.set_snap_mode("grille")
	await frames(2)
	cv.zoom = 22.0
	cv.origin = Vector2(50, 40)

	# Salle ronde : Cercle (inventaire), un clic au centre, « 13 Tab 32 Entrée ».
	await key(KEY_4)   # case 4 (Mur) : reçoit l'objet pris dans l'inventaire
	await key(KEY_E)
	ed.inventory.show_category("construction")
	_pick("piece_cercle")
	at.check(ed.current_item().id == "piece_cercle", "cercle pris dans l'inventaire")
	await click(Vector2(16, 16))
	at.check(cv.drag.get("sticky", false), "un clic : le tracé suit le curseur")
	_motion(Vector2(22, 16))
	await type_text("13")
	await key(KEY_TAB)
	await type_text("32")
	await frames(2)
	await at.screenshot("cercle_clavier")
	await key(KEY_ENTER)
	var circle: Dictionary = ed.doc.pieces[0] if not ed.doc.pieces.is_empty() else {}
	at.check(not circle.is_empty() and int(circle.get("forme", {}).get("points", 0)) == 32 and absf(float(circle.forme.rx) - 13.0) < 0.001,
		"salle ronde de 32 points, rayon 13 m (%s)" % str(circle.get("forme", {})))
	if circle.is_empty():
		return
	var cpoly := MapGeom.poly(circle.contour)
	var e := _east_edge(cpoly)
	var top: Vector2 = e[0]
	var bottom: Vector2 = e[1]

	# G G : sans grille. Annexe au polygone, collée au côté est (aimant aux sommets).
	await key(KEY_G)
	await key(KEY_G)
	at.check(cv.snap_mode == "libre", "G G : aimantation libre (%s)" % cv.snap_mode)
	await key(KEY_3)
	await click(top + Vector2(0.09, -0.06))
	at.check(not cv.poly_pts.is_empty() and cv.poly_pts[0] == top, "premier sommet aimanté au sommet du cercle (%s)" % str(cv.poly_pts))
	_motion(top + Vector2(3, 0.4))
	await type_text("8")
	await key(KEY_TAB)
	await type_text("0")
	await key(KEY_ENTER)
	at.check(cv.poly_pts.size() == 2 and cv.poly_pts[1].is_equal_approx(top + Vector2(8, 0)), "côté de 8 m à 0° au clavier (%s)" % str(cv.poly_pts))
	await click(bottom + Vector2(8.03, 0.04))
	await click(bottom + Vector2(0.07, 0.05))
	await click(top + Vector2(0.05, 0.02))
	var annex: Dictionary = ed.doc.pieces[1] if ed.doc.pieces.size() > 1 else {}
	at.check(not annex.is_empty() and MapGeom.poly(annex.contour).has(top) and MapGeom.poly(annex.contour).has(bottom),
		"annexe sans grille collée au cercle (%s)" % str(annex.get("contour", [])))
	var shared := MapRules.shared_edges(ed.doc, 0)
	at.check(shared.size() == 1, "bord commun entre la salle ronde et l'annexe")
	var mid := (top + bottom) * 0.5
	# Porte sur le bord commun, fenêtres.
	await key(KEY_5)
	await click(mid + Vector2(0.1, 0.2))
	at.check(ed.doc.ouvertures.size() == 1 and absf(float(ed.doc.ouvertures[0].get("largeur", 0.0)) - 1.5) < 0.001,
		"porte posée sur le côté est du cercle, réduite à 1,5 m pour y tenir (%s)" % (str(ed.doc.ouvertures) if cv.refusal == "" else cv.refusal))
	await key(KEY_6)
	for p in [Vector2(6.6, 6.6), mid + Vector2(8.3, 0)]:
		await click(p)
	at.check(ed.doc.ouvertures.filter(func(o): return o.type == "fenetre").size() == 2, "2 fenêtres (%s)" % cv.refusal)
	# Toujours sans grille : la fenêtre de la salle ronde glissée à la souris sur
	# le côté voisin du cercle, puis ramenée.
	await _move_window_free(cpoly)
	# Mur libre tracé sans grille dans la salle ronde, interrupteur posé contre sa face nord.
	await key(KEY_4)
	await key(KEY_E)
	ed.inventory.show_category("construction")
	_pick("mur")
	await drag(Vector2(21.03, 25.02), Vector2(24.02, 24.98))
	var fwall: Array = ed.doc.objets.filter(func(o): return o.type == "mur")
	at.check(fwall.size() == 1 and absf(float(fwall[0].a[1]) - float(fwall[0].b[1])) < 0.001, "mur libre tracé sans grille (%s)" % str(fwall))
	if not fwall.is_empty():
		free_wall_y = float(fwall[0].a[1])
	await key(KEY_4)
	await key(KEY_E)
	ed.inventory.show_category("machines")
	_pick("courant")
	await click(Vector2(22.6, 24.4))
	var guns: Array = ed.doc.objets.filter(func(o): return o.type == "courant")
	var on_wall := guns.size() == 1 and fwall.size() == 1 and String(guns[0].mur) == "s" \
		and absf(float(guns[0].position[1]) - float(fwall[0].a[1])) < 0.001
	at.check(on_wall, "interrupteur posé contre le mur libre, face au nord (%s %s)" % [str(guns), cv.refusal])
	# Mur courbe : un clic au centre, le curseur vers le début, « 7 Tab 100 Entrée ».
	await key(KEY_4)   # case 4 (Mur) : reçoit l'objet pris dans l'inventaire
	await key(KEY_E)
	ed.inventory.show_category("construction")
	_pick("mur_courbe")
	await click(Vector2(16, 16))
	_motion(Vector2(16, 16) + MapGeom.deg_dir(290.0) * 4.0)
	await type_text("7")
	await key(KEY_TAB)
	await type_text("100")
	await key(KEY_ENTER)
	var arc: Array = ed.doc.objets.filter(func(o): return o.type == "mur_courbe")
	at.check(arc.size() == 1 and absf(float(arc[0].rayon) - 7.0) < 0.01 and absf(float(arc[0].ouverture) - 100.0) < 0.01
		and absf(float(arc[0].debut) - 290.0) < 1.0, "mur courbe de 7 m sur 100° (%s)" % str(arc))
	# Retour à la grille (G) : pilier au glisser, départ, boîte dans l'annexe.
	await key(KEY_G)
	at.check(cv.snap_mode == "grille", "G : de nouveau la grille")
	await key(KEY_4)   # case 4 (Mur) : reçoit l'objet pris dans l'inventaire
	await key(KEY_E)
	ed.inventory.show_category("construction")
	_pick("pilier")
	await drag(Vector2(9, 17), Vector2(11, 19))
	var pil: Array = ed.doc.objets.filter(func(o): return o.type == "pilier")
	at.check(pil.size() == 1, "pilier posé")
	await key(KEY_8)
	await click(Vector2(20, 21))
	await key(KEY_7)
	await click(mid + Vector2(4.0, -0.9))
	at.check(ed.doc.objets.filter(func(o): return o.type == "boite").size() == 1, "boîte contre le mur de l'annexe (%s)" % cv.refusal)
	# Pilier tourné de 30° avec la poignée de rotation (pas de 15°).
	await key(KEY_QUOTELEFT)
	await click(Vector2(10, 18))
	at.check(not pil.is_empty() and ed.selected == String(pil[0].id), "pilier choisi")
	var rh := cv.rot_handle()
	if not rh.is_empty():
		var c: Vector2 = rh.c
		await drag(rh.p, c + (Vector2(rh.p) - c).rotated(deg_to_rad(31.0)))
	var pr: Dictionary = ed.doc.find(String(pil[0].id)) if not pil.is_empty() else {}
	at.check(int(pr.get("rot", 0)) == 30, "poignée : pilier tourné de 30° (%s)" % str(pr.get("rot", "?")))

	# Noms et textures (brique et parquet dans la salle ronde).
	var cr := ed.doc.find(String(circle.id))
	cr.merge({"nom": "Salle ronde", "surface_murs": "brick", "surface_sol": "parquet"}, true)
	if not annex.is_empty():
		ed.doc.find(String(annex.id)).merge({"nom": "Annexe", "surface_murs": "wall_concrete"}, true)
	ed.changed()
	# Vérification, capture de l'éditeur.
	# Porte d'évacuation obligatoire (format 18) : posée par la règle de l'éditeur.
	MapTestKit.add_evac(ed.doc)
	ed.changed()
	var v := ed.validate()
	at.check(v.ok(), "vérification : 0 erreur (%s)" % " | ".join(v.errors().map(func(m): return String(m.fr))))
	at.check(v.doors.size() == 1 and v.windows.size() == 2, "porte et fenêtres reconnues")
	ed.panels.show_tab("props")
	cv.frame_all()
	await frames(3)
	await at.screenshot("editeur")

	# Ctrl+S : format courant (4 ou plus : formes libres) ; rechargement identique.
	await key(KEY_S, true)
	var dir := ed.map_dir
	var carte = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	at.check(carte is Dictionary and int(carte.format) == EditorMap.FORMAT and EditorMap.FORMAT >= 4, "Ctrl+S : enregistrée au format %d" % EditorMap.FORMAT)
	at.check(FileAccess.get_file_as_string(dir.path_join("pieces.json")).contains("\"forme\":{"), "forme de base dans pieces.json")
	var saved := ed.doc.duplicate_map()
	ed.open_dir(dir)
	await frames(2)
	at.check(ed.doc.same_as(saved), "carte rechargée identique")
	cv.set_snap_mode("grille")

	# En jeu : TESTER.
	if not ed.test_map():
		at.fail("TESTER refusé")
		return
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 30.0, "partie lancée")
	if not ok:
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.combat.debug_invulnerable = true
	var boxes := game.world.find_children("Biais_*", "CollisionBox", true, false)
	at.check(boxes.size() >= 40, "salle ronde : %d pavés CollisionBox tournés" % boxes.size())
	await seconds(1.0)
	var space := game.world.get_world_3d().direct_space_state
	var hs := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 16, 1.2, off + 16), Vector3(off + 16, 1.2, off + 32), 1))
	at.check(not hs.is_empty() and hs.collider is CollisionBox and absf(hs.position.z - off - (16.0 + 13.0 * cos(PI / 32.0) - 0.25)) < 0.05,
		"un rayon s'arrête sur le mur rond (%s)" % str(hs.get("position", "rien")))
	var hp := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 14, 1.2, off + 18), Vector3(off + 6, 1.2, off + 18), 1))
	at.check(not hp.is_empty() and hp.collider is CollisionBox, "un rayon s'arrête sur le pilier tourné (%s)" % str(hp.get("position", "rien")))
	# Arme du mur libre : achetée depuis le bon côté.
	game.rounds.paused = true
	await _buy_on_free_wall(game, p)
	# Vue de la salle ronde : mur courbe, pilier tourné, fenêtre.
	p.global_position = Vector3(off + 24.5, 0.05, off + 23.5)
	AutotestHelpers.aim_at(p, Vector3(off + 9.5, 1.4, off + 10.5))
	await seconds(0.6)
	await at.screenshot("salle_ronde")
	game.rounds.paused = false
	# Zombies de la manche 1 : ils entrent par la fenêtre nord-ouest et
	# rejoignent le joueur, au sud du pilier, en le contournant.
	p.global_position = Vector3(off + 11.0, 0.05, off + 22.0)
	AutotestHelpers.aim_at(p, Vector3(off + 6.6, 1.2, off + 6.6))
	var win: Barricade = null
	for b: Barricade in game.barricades.windows:
		if b.zone == "a":
			win = b
	at.check(win != null, "fenêtre barricadée de la salle ronde")
	if win:
		win.srv_set_mask(0)
	var pillar := MapRaster.rect_poly(pr) if not pr.is_empty() else PackedVector2Array()
	var arc_segs := MapShapes.arc_segments(arc[0]) if not arc.is_empty() else []
	var crossed := [false, false]
	var inside := {}
	var t0 := GameClock.msec()
	var reached := false
	while GameClock.msec() - t0 < 70000:
		await tree().physics_frame
		for z: Zombie in game.zombies.zombies.values():
			if not z.is_alive():
				continue
			var ez := Vector2(z.global_position.x - off, z.global_position.z - off)
			if not pillar.is_empty() and MapGeom.contains(pillar, ez):
				crossed[0] = true
			for s in arc_segs:
				if MapGeom.dist_to_segment(ez, s[0], s[1]) < MapGeom.WALL_HALF:
					crossed[1] = true
			if MapGeom.contains(cpoly, ez) and ez.distance_to(Vector2(16, 16)) < 11.5:
				inside[z.id] = true
			if Vector2(z.global_position.x - p.global_position.x, z.global_position.z - p.global_position.z).length() < 1.6:
				reached = true
		if reached and inside.size() >= 2:
			break
	at.check(inside.size() >= 1, "des zombies entrent par la fenêtre de la salle ronde (%d)" % inside.size())
	at.check(reached, "un zombie rejoint le joueur")
	at.check(not crossed[0], "aucun zombie ne traverse le pilier tourné")
	at.check(not crossed[1], "aucun zombie ne traverse le mur courbe")
	AutotestHelpers.aim_at(p, Vector3(off + 8.0, 1.0, off + 12.0))
	await frames(4)
	await at.screenshot("en_jeu")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(EditorMap.maps_root())


## Sans grille, outil Sélection : la fenêtre posée sur la salle ronde (côté
## nord-ouest) glissée à la souris jusqu'au milieu du côté voisin du cercle,
## puis ramenée à sa place.
func _move_window_free(cpoly: PackedVector2Array) -> void:
	var win := {}
	for o in ed.doc.ouvertures:
		if o.type == "fenetre" and MapGeom.on_boundary(cpoly, MapGeom.v2(o.position), 0.02):
			win = o
	at.check(not win.is_empty(), "fenêtre de la salle ronde")
	if win.is_empty():
		return
	var p0 := MapGeom.v2(win.position)
	var side := -1
	for i in cpoly.size():
		if MapGeom.dist_to_segment(p0, cpoly[i], cpoly[(i + 1) % cpoly.size()]) < 0.02:
			side = i
	var j := (side + 1) % cpoly.size()
	var target := (cpoly[j] + cpoly[(j + 1) % cpoly.size()]) * 0.5
	await key(KEY_QUOTELEFT)
	await click(p0)
	at.check(ed.selected == String(win.id), "fenêtre choisie")
	await drag(p0, target + (target - Vector2(16, 16)).normalized() * 0.15)
	var p1 := MapGeom.v2(ed.doc.find(String(win.id)).position)
	at.check(p1.distance_to(target) < 0.3 and MapGeom.dist_to_segment(p1, cpoly[j], cpoly[(j + 1) % cpoly.size()]) < 0.02,
		"sans grille : fenêtre glissée sur le côté voisin du cercle (%s -> %s, voulu %s) %s" % [p0, p1, target, cv.refusal])
	at.check(not ed.invalid.has(String(win.id)), "fenêtre déplacée valide")
	await drag(p1, p0)
	var p2 := MapGeom.v2(ed.doc.find(String(win.id)).position)
	at.check(p2.distance_to(p0) < 0.05, "fenêtre ramenée à sa place (%s)" % p2)


## Interrupteur posé contre le mur libre : construit contre sa face nord,
## actionné depuis ce côté.
func _buy_on_free_wall(game: Game, p: Player) -> void:
	var found := (game.world as Node).find_children("*", "PowerSwitch", true, false)
	at.check(found.size() == 1, "interrupteur du mur libre construit en jeu")
	if found.size() != 1:
		return
	var sw: Interactable = found[0]
	var wy := free_wall_y
	var front := sw.interact_point()
	at.check(absf(sw.global_position.z - (off + wy)) < 0.6 and front.z < off + wy,
		"contre la face nord du mur libre, actionné du côté nord (interrupteur z %.2f, devant z %.2f, mur y %.2f)" % [sw.global_position.z - off, front.z - off, wy])
	p.teleport_to(Vector3(front.x, 0.05, front.z) + Vector3(0, 0, -0.6))
	AutotestHelpers.aim_at(p, front)
	await seconds(0.3)
	at.check(game.interact.focused == sw, "l'interrupteur du mur libre est visé depuis le côté nord")
	p.input.interact_pressed = true
	await seconds(0.5)
	at.check(game.power_on, "courant rétabli depuis le mur libre")
	await at.screenshot("interrupteur_mur_libre")


## Côté est du cercle (à plat, vertical) : [sommet haut, sommet bas].
static func _east_edge(poly: PackedVector2Array) -> Array:
	var best := 0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if absf(a.x - b.x) < 0.001 and a.x > poly[best].x - 0.001:
			best = i
	var p := poly[best]
	var q := poly[(best + 1) % poly.size()]
	return [p, q] if p.y < q.y else [q, p]


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _pick(item_id: String) -> void:
	for s in ed.inventory.cells:
		if s.item_id == item_id:
			s.clicked.emit(s)
			return
	at.fail("objet %s absent de l'inventaire" % item_id)


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


func key(code: Key, ctrl := false, text := "") -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	if text != "":
		e.unicode = text.unicode_at(0)
	ed._input(e)
	var up := e.duplicate()
	up.pressed = false
	ed._input(up)
	await frames(1)


## Chiffres tapés au clavier (saisie de la longueur, de l'angle...).
func type_text(s: String) -> void:
	for ch in s:
		await key(KEY_0 + int(ch) if ch >= "0" and ch <= "9" else KEY_PERIOD, false, ch)
