extends TestCase
## Sélection multiple et actions de groupe de l'éditeur de cartes (MapGroup,
## MapContextMenu, docs/MAP_AUTHORING.md § 2) : Maj + clic, rectangle (de
## gauche à droite : dedans ; de droite à gauche : touchés), Ctrl+A ; groupe
## déplacé, pivoté, dupliqué, collé, supprimé en UNE étape d'annulation ;
## groupe refusé en entier (élément nommé, mis en évidence) ; menu du clic
## droit (entrées, états) et clic droit pendant un glissement = annulation ;
## prefab créée depuis la sélection puis posée ; une action de groupe = un
## seul lot pour la session (collaboration).

const DecorFree := preload("res://tests/test_map_decor_free.gd")
const TMP := "res://tests/_out/test_map_group"
const PORT := 17850


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


## Deux salles collées A (0..14 × 0..10) et B (14..24 × 0..10), porte o1 entre
## elles, fenêtres, départ, boîte ; deux décors dans A (caisses, sacs de sable).
static func _map() -> EditorMap:
	var doc := DecorFree.two_rooms()
	DecorFree._obj(doc, {"type": "prefab", "prefab": "caisses", "position": [4.0, 5.5], "rot": 0})
	DecorFree._obj(doc, {"type": "prefab", "prefab": "sacs_sable", "position": [6.5, 5.5], "rot": 90})
	# Départ des joueurs écarté du décor (glissements et copies à côté).
	for o in doc.objets:
		if String(o.type) == "depart":
			o["position"] = [12.0, 2.0]
	return doc


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	ed.doc = _map()
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	ed.canvas.set_snap_mode("grille")
	return ed


static func _id(doc: EditorMap, prefab: String) -> String:
	for o in doc.objets:
		if String(o.get("prefab", "")) == prefab:
			return String(o.id)
	return ""


static func _pos(doc: EditorMap, eid: String) -> Vector2:
	return MapGeom.v2(doc.find(eid).position)


## Appui puis relâché du bouton gauche de la vue Dessus en `a`, glissé en `b`.
static func _click(cv: MapCanvas, a: Vector2, b := Vector2.INF) -> void:
	cv.mouse_m = a
	cv._press(false)
	if b != Vector2.INF:
		cv.mouse_m = b
		cv._drag_update()
	cv._release()


func _undo_count(ed: MapEditor) -> int:
	return ed.collab.history.undo_count(ed.collab.my_id)


# ------------------------------------------------------------------ sélection

func test_shift_click_rectangle_and_select_all() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	# Maj + clic : ajoute, puis retire.
	cv.shift_select = true
	_click(cv, _pos(ed.doc, c))
	assert_eq(ed.sel_ids(), [c], "Maj + clic : un élément")
	assert_eq(ed.selected, c, "un seul : élément choisi")
	_click(cv, _pos(ed.doc, s))
	assert_eq(ed.sel_ids(), [c, s], "Maj + clic : ajouté")
	assert_eq(ed.selected, "", "groupe : plus d'élément choisi seul")
	_click(cv, _pos(ed.doc, c))
	assert_eq(ed.sel_ids(), [s], "Maj + clic : retiré")
	ed.select("")
	# Rectangle de gauche à droite (Maj : n'importe où) : entièrement dedans.
	_click(cv, Vector2(2, 4), Vector2(7.1, 7))
	assert_eq(ed.sel_ids(), [c, s], "de gauche à droite : les deux décors dedans, pas la pièce")
	ed.select("")
	# De droite à gauche : touchés (la pièce A aussi).
	_click(cv, Vector2(7.1, 7), Vector2(2, 4))
	var got := ed.sel_ids()
	assert_true(got.has(c) and got.has(s), "de droite à gauche : décors touchés")
	assert_true(got.has(String(ed.doc.pieces[0].id)), "de droite à gauche : la pièce touchée aussi")
	assert_false(got.has(String(ed.doc.pieces[1].id)), "pièce B non touchée")
	cv.shift_select = false
	# Sans Maj, depuis le vide : rectangle qui remplace ; un simple clic désélectionne.
	_click(cv, Vector2(30, 12), Vector2(-1, -1))
	assert_eq(ed.sel_ids().size(), MapGroup.in_rect(ed.doc, 0, Rect2(-1, -1, 31, 13), true).size(), "rectangle depuis le vide")
	_click(cv, Vector2(30, 12))
	assert_eq(ed.sel_ids(), [], "clic dans le vide : désélectionné")
	# Ctrl+A : tout l'étage ; Échap : désélectionné.
	ed.select_all()
	assert_eq(ed.sel_ids().size(), ed.doc.pieces.size() + ed.doc.ouvertures.size() + ed.doc.objets.size(), "Ctrl+A : tout l'étage")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ed._input(esc)
	assert_eq(ed.sel_ids(), [], "Échap : désélectionné")
	# Sélection commune : liste des objets, présence (collaboration), Claude (MCP).
	ed.select_many([c, s, "z1", "inconnu", c])
	assert_eq(ed.group, [c, s], "zones, inconnus et doublons ignorés")
	assert_eq(MapCollab.clean_presence({"cursor": [0, 0], "selection": ed.sel_ids()}).selection, [c, s], "présence : la sélection entière")
	ed.queue_free()


# ------------------------------------------------------------------ actions de groupe

func test_group_move_rotate_duplicate_paste_delete_one_undo_each() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	var pc := _pos(ed.doc, c)
	var ps := _pos(ed.doc, s)
	ed.select_many([c, s])
	# Glisser un élément du groupe : tout le groupe, une seule annulation.
	var u0 := _undo_count(ed)
	_click(cv, pc, pc + Vector2(0, 2))
	assert_eq(_pos(ed.doc, c), pc + Vector2(0, 2), "caisses déplacées")
	assert_eq(_pos(ed.doc, s), ps + Vector2(0, 2), "sacs déplacés avec")
	assert_eq(_undo_count(ed), u0 + 1, "une étape d'annulation")
	assert_eq(ed.sel_ids(), [c, s], "toujours sélectionnés")
	ed.undo()
	assert_eq(_pos(ed.doc, c), pc, "Ctrl+Z : caisses revenues")
	assert_eq(_pos(ed.doc, s), ps, "Ctrl+Z : sacs revenus")
	# Simple clic sur un élément du groupe : il est choisi seul.
	ed.select_many([c, s])
	_click(cv, pc)
	assert_eq(ed.sel_ids(), [c], "clic sans glisser : l'élément seul")
	# Flèches : un pas de grille.
	ed.select_many([c, s])
	ed.nudge_selection(Vector2.RIGHT)
	assert_eq(_pos(ed.doc, c), pc + Vector2(1, 0), "flèche : un pas")
	ed.undo()
	# Pivoter (R) autour du centre du groupe : une annulation.
	u0 = _undo_count(ed)
	var h0 := MapOps.hash_of(ed.doc)
	ed.select_many([c, s])
	ed.rotate_selection()
	assert_false(_pos(ed.doc, c).is_equal_approx(pc) and _pos(ed.doc, s).is_equal_approx(ps), "groupe pivoté (%s)" % ed.status.text)
	assert_eq(int(ed.doc.find(s).get("rot", 0)), 180, "sacs : 90 + 90°")
	assert_eq(_undo_count(ed), u0 + 1, "pivoter : une étape")
	ed.undo()
	assert_eq(MapOps.hash_of(ed.doc), h0, "Ctrl+Z : pivot annulé")
	# Dupliquer (Ctrl+D) : à côté, les copies deviennent la sélection.
	var n0 := ed.doc.objets.size()
	ed.select_many([c, s])
	ed.duplicate_selection()
	assert_eq(ed.doc.objets.size(), n0 + 2, "deux copies")
	assert_eq(ed.sel_ids().size(), 2, "les copies sélectionnées")
	assert_false(ed.sel_ids().has(c), "pas l'original")
	ed.undo()
	assert_eq(ed.doc.objets.size(), n0, "Ctrl+Z : copies retirées")
	# Copier, coller sous la souris, une étape.
	ed.select_many([c, s])
	ed.copy_selected()
	ed.paste(Vector2(9, 8.5))
	assert_eq(ed.doc.objets.size(), n0 + 2, "collé")
	var bb := MapGroup.bounds(ed.doc, ed.sel_ids())
	assert_true(bb.get_center().distance_to(Vector2(9, 8.5)) < 0.8, "collé sous la souris (%s)" % str(bb.get_center()))
	ed.undo()
	assert_eq(ed.doc.objets.size(), n0, "Ctrl+Z : collage retiré")
	# Couper puis supprimer : une étape chacun.
	ed.select_many([c, s])
	u0 = _undo_count(ed)
	ed.cut_selected()
	assert_true(ed.doc.find(c).is_empty() and ed.doc.find(s).is_empty(), "coupé")
	assert_eq(_undo_count(ed), u0 + 1, "couper : une étape")
	ed.paste(Vector2(5, 6))
	assert_eq(ed.doc.objets.size(), n0, "collé après couper")
	ed.select_many(ed.sel_ids())
	ed.delete_selection()
	assert_eq(ed.doc.objets.size(), n0 - 2, "Suppr : le groupe")
	ed.undo()
	assert_eq(ed.doc.objets.size(), n0, "Ctrl+Z : groupe revenu")
	ed.queue_free()


## Un groupe dont un élément serait mal placé : RIEN ne bouge, l'élément est
## nommé avec la raison et mis en évidence.
func test_invalid_group_is_refused_whole() -> void:
	var ed: MapEditor = await _editor()
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	var pc := _pos(ed.doc, c)
	var h0 := MapOps.hash_of(ed.doc)
	# Le groupe sortirait du terrain (le départ des joueurs hors des pièces) :
	# tout le groupe est refusé, le premier élément fautif est désigné.
	var dep := ""
	for o in ed.doc.objets:
		if String(o.type) == "depart":
			dep = String(o.id)
	var r := MapGroup.move(ed, MapGroup.movers(ed.doc, [c, s, dep]), Vector2(0, 12), 0, ed.doc.snapshot())
	assert_false(r.ok, "groupe qui sortirait : refusé")
	assert_true((r.get("bad", []) as Array).size() == 1 and [c, s, dep].has(r.bad[0]), "fautif désigné : %s" % str(r.get("bad")))
	assert_true(r.get("el") is Dictionary, "fautif à la place refusée (mise en évidence)")
	assert_true(MapRules.why(r).contains("«") or MapRules.why(r).contains("\""), "élément nommé (%s)" % MapRules.why(r))
	assert_eq(MapOps.hash_of(ed.doc), h0, "carte intacte")
	# Pièce B décalée sans A : sa porte n'est plus entre deux pièces -> tout refusé.
	var pb := String(ed.doc.pieces[1].id)
	var rb := MapGroup.move(ed, MapGroup.movers(ed.doc, [pb]), Vector2(1, 0), 0, ed.doc.snapshot())
	assert_false(rb.ok, "pièce dont la porte quitterait le mur commun : refusée")
	assert_true(rb.bad.has("o1") or rb.bad.has(pb), "fautif désigné : %s" % str(rb.bad))
	assert_eq(MapOps.hash_of(ed.doc), h0, "carte intacte")
	# A et B ensemble : la porte suit, accepté.
	var both := MapGroup.move(ed, MapGroup.movers(ed.doc, [String(ed.doc.pieces[0].id), pb]), Vector2(1, 1), 0, ed.doc.snapshot())
	assert_true(both.ok, "les deux pièces et leur contenu : accepté (%s)" % MapRules.why(both))
	assert_eq(_pos(ed.doc, c), pc + Vector2(1, 1), "contenu emporté")
	assert_eq(MapGeom.v2(ed.doc.find("o1").position), Vector2(15, 6.25), "porte emportée")
	ed.doc = _map()
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	# Collage hors de toute pièce : refusé, mis en évidence, rien d'ajouté.
	ed.select_many([_id(ed.doc, "caisses"), _id(ed.doc, "sacs_sable")])
	ed.copy_selected()
	var n0 := ed.doc.objets.size()
	ed.paste(Vector2(40, 40))
	assert_eq(ed.doc.objets.size(), n0, "collage refusé : rien d'ajouté")
	assert_eq(ed.canvas.refusal_elems.size(), 1, "élément fautif mis en évidence")
	assert_true(ed._status_error, "refus dans la barre d'état")
	ed.queue_free()


# ------------------------------------------------------------------ menu du clic droit

func test_context_menu_entries_states_and_right_click() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var c := _id(ed.doc, "caisses")
	# Clic droit sur un élément non choisi : choisi d'abord, menu ouvert.
	var m := ed.open_context_menu(Vector2(200, 200), Vector2(9, 6), c)
	assert_eq(ed.sel_ids(), [c], "élément choisi d'abord")
	assert_true(m.visible, "menu ouvert")
	assert_eq(m.item_count, MapContextMenu.ENTRIES.size(), "entrées et séparateurs")
	var labels := []
	for i in m.item_count:
		labels.append(m.get_item_text(i))
	assert_true(String(labels[0]).begins_with(Lang.t("Créer une prefab…", "Create a prefab…")), "Créer une prefab… en tête")
	assert_true(String(labels[0]).ends_with("Ctrl+G"), "raccourci affiché")
	assert_true(String(labels[2]).begins_with(Lang.t("Dupliquer", "Duplicate")) and String(labels[2]).ends_with("Ctrl+D"), "Dupliquer : Ctrl+D")
	var st := m.states()
	assert_eq(st[MapContextMenu.PREFAB], "", "prefab possible (décor)")
	assert_eq(st[MapContextMenu.DUPLICATE], "", "dupliquer possible")
	assert_true(st[MapContextMenu.PASTE] != "", "coller grisé : presse-papiers vide")
	assert_true(m.is_item_disabled(m.get_item_index(MapContextMenu.PASTE)), "entrée grisée")
	ed.copy_selected()
	assert_eq(m.states()[MapContextMenu.PASTE], "", "coller possible après copier")
	m.paste_at = Vector2.INF
	assert_true(m.states()[MapContextMenu.PASTE] != "", "hors vue Dessus : coller grisé")
	m.hide()
	# Une porte seule : pas de prefab (raison donnée) ; rien de choisi : grisé.
	ed.open_context_menu(Vector2(200, 200), Vector2.INF, "o1")
	assert_true(ed.context_menu.states()[MapContextMenu.PREFAB] != "", "porte : pas de prefab")
	ed.context_menu.hide()
	ed.select("")
	ed.context_menu.paste_at = Vector2.INF
	var st2 := ed.context_menu.states()
	assert_true(st2[MapContextMenu.DELETE] != "" and st2[MapContextMenu.DUPLICATE] != "", "rien de choisi : grisé")
	assert_eq(st2[MapContextMenu.SELECT_ALL], "", "tout sélectionner possible")
	# Une pièce : son contenu (décor) entre dans la prefab.
	ed.select(String(ed.doc.pieces[0].id))
	assert_eq(ed.context_menu.states()[MapContextMenu.PREFAB], "", "pièce avec du décor : prefab possible")
	# Entrée choisie : l'action.
	ed.select(c)
	var n0 := ed.doc.objets.size()
	ed.context_menu.id_pressed.emit(MapContextMenu.DUPLICATE)
	assert_eq(ed.doc.objets.size(), n0 + 1, "Dupliquer depuis le menu")
	# Clic droit pendant un glissement : annulation, pas de menu.
	ed.context_menu.hide()
	ed.select("")
	ed.select_slot(1)   # pièce rectangle
	cv.mouse_m = Vector2(30, 2)
	cv._press(false)
	cv.mouse_m = Vector2(34, 6)
	cv._drag_update()
	assert_eq(String(cv.drag.get("kind", "")), "create", "tracé en cours")
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.position = cv.to_px(Vector2(34, 6))
	cv._gui_input(rc)
	assert_true(cv.drag.is_empty(), "clic droit : tracé annulé")
	assert_false(ed.context_menu.visible, "pas de menu pendant un tracé")
	# Rien en cours : le menu.
	cv._gui_input(rc)
	assert_true(ed.context_menu.visible, "rien en cours : menu")
	ed.context_menu.hide()
	# 3D : un clic droit glissé tourne la caméra (pas de menu), un clic droit
	# sans bouger ouvre le menu.
	var pv := ed.preview
	pv._rmb_click = true
	pv._rmb_travel = 0.0
	pv._rmb_moved(Vector2(40, 0))
	pv._rmb_up()
	assert_false(ed.context_menu.visible, "3D : clic droit glissé = regard")
	pv._rmb_click = true
	pv._rmb_travel = 0.0
	pv._rmb_moved(Vector2(2, 1))
	pv._rmb_up()
	assert_true(ed.context_menu.visible, "3D : clic droit sans bouger = menu")
	ed.context_menu.hide()
	ed.queue_free()


# ------------------------------------------------------------------ prefab depuis la sélection

func test_prefab_from_selection_then_placed() -> void:
	var ed: MapEditor = await _editor()
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	# Analyse : la porte et la pièce B sont exclues, avec leur raison.
	var an := MapPrefabTools.analyze(ed.doc, [c, s, "o1", String(ed.doc.pieces[1].id)])
	assert_eq((an.parts as Array).size(), 2, "deux décors repris")
	assert_true(an.excluded.has("ouverture") and an.excluded.has("piece"), "porte et pièce exclues : %s" % str(an.excluded))
	ed.select_many([c, s, "o1"])
	var d := ed.prefab_tools.create_dialog_for(ed.sel_ids())
	assert_true(d != null and d.visible, "boîte « Créer une prefab »")
	assert_true((d.find_child("Content", true, false) as Label).text.contains("2"), "contenu : 2 décors")
	assert_true((d.find_child("Excluded", true, false) as Label).text.contains("1"), "exclus listés")
	assert_true(d.find_child("Anchor", true, false) != null and d.find_child("Help", true, false) != null, "ancrage et aide")
	assert_false(d.get_ok_button().disabled, "Créer possible")
	(d.find_child("Name", true, false) as LineEdit).text = "Barricade du hall"
	(d.find_child("Replace", true, false) as CheckBox).button_pressed = false
	var n0 := ed.doc.objets.size()
	d.confirmed.emit()
	await wait_frames(1)
	assert_eq(ed.doc.prefabs.size(), 1, "prefab dans la bibliothèque")
	var pid := String(ed.doc.prefabs.keys()[0])
	assert_eq(ed.doc.objets.size(), n0, "sans remplacer : décor gardé")
	assert_eq(String(ed.current_item().get("id", "")), "prefab:" + MapPrefabLib.ref(pid), "prefab en main")
	# Posée comme un objet, d'un clic.
	ed.canvas.mouse_m = Vector2(19, 5)
	ed.canvas._update_preview()
	assert_true(ed.canvas.preview.get("ok", false), "pose possible : %s" % MapRules.why(ed.canvas.preview))
	ed.canvas._press(false)
	assert_eq(ed.doc.prefab_users(pid).size(), 1, "prefab posée")
	# Une porte seule : boîte, mais Créer grisé.
	var d2 := ed.prefab_tools.create_dialog_for(["o1"])
	assert_true(d2.get_ok_button().disabled, "rien à grouper : Créer grisé")
	d2.queue_free()
	ed.queue_free()


# ------------------------------------------------------------------ collaboration

## Une action de groupe = un seul lot d'opérations chez l'invité ; la sélection
## multiple est partagée (présence).
func test_group_action_is_one_batch_in_session() -> void:
	var ed: MapEditor = await _editor()
	var port := PORT + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()
	assert_eq(ed.collab.host(port, "Alice"), OK, "hôte")
	var g := MapCollab.new(EditorMap.blank())
	host.add_child(g)
	g.join("127.0.0.1", port, ed.collab.session_code, "Bob")
	assert_true(await _until(func(): return g.role == MapCollab.Role.GUEST and not g._joining), "invité accueilli")
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	ed.select_many([c, s])
	var seq0 := ed.collab.seq
	_click(ed.canvas, _pos(ed.doc, c), _pos(ed.doc, c) + Vector2(1, 1))
	assert_eq(ed.collab.seq, seq0 + 1, "un seul lot pour le groupe")
	assert_true(await _until(func(): return g.seq == ed.collab.seq), "lot reçu")
	assert_eq(MapGeom.v2(g.doc.find(s).position), _pos(ed.doc, s), "groupe déplacé chez l'invité")
	ed.duplicate_selection()
	assert_eq(ed.collab.seq, seq0 + 2, "dupliquer : un lot")
	ed.delete_selection()
	assert_eq(ed.collab.seq, seq0 + 3, "supprimer : un lot")
	assert_true(await _until(func(): return g.seq == ed.collab.seq and g.pending.is_empty()), "reçus")
	assert_eq(MapOps.hash_of(g.doc), MapOps.hash_of(ed.doc), "cartes identiques")
	# Présence : la sélection multiple de l'hôte vue par l'invité.
	ed.select_many([c, s])
	ed.send_presence()
	assert_true(await _until(func(): return (g.peers.get(ed.collab.my_id, {}).get("presence", {}).get("selection", []) as Array).size() == 2), "sélection multiple partagée")
	g.leave()
	g.queue_free()
	ed.collab.leave()
	ed.queue_free()
	await wait_frames(1)


func _until(cond: Callable, limit := 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await host.get_tree().process_frame
	return true


# ------------------------------------------------------------------ corrections de revue

## Flèches : seulement quand le clavier est à une vue (une liste garde ses
## flèches) ; pendant un glissement, les actions qui changent la carte
## attendent (sinon le glissement les effacerait).
func test_arrows_focus_and_actions_blocked_while_dragging() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	var pc := _pos(ed.doc, c)
	ed.select_many([c, s])
	var right := InputEventKey.new()
	right.keycode = KEY_RIGHT
	right.pressed = true
	# Focus dans une liste (comme Pièces / Zones / Étages) : elle garde les flèches.
	var list := ItemList.new()
	list.add_item("a")
	list.add_item("b")
	ed.add_child(list)
	list.grab_focus()
	assert_false(ed.arrows_to_views(), "liste focalisée : flèches à la liste")
	ed._input(right)
	assert_eq(_pos(ed.doc, c), pc, "liste focalisée : rien ne bouge")
	list.queue_free()
	# Focus sur la vue Dessus : la sélection avance.
	cv.grab_focus()
	assert_true(ed.arrows_to_views(), "vue focalisée : flèches aux vues")
	ed._input(right)
	assert_eq(_pos(ed.doc, c), pc + Vector2(1, 0), "vue focalisée : un pas")
	ed.undo()
	# Glissement du groupe en cours : flèches, R, Suppr, Ctrl+V / X / D, prefab refusés.
	ed.select_many([c, s])
	ed.copy_selected()
	cv.mouse_m = pc
	cv._press(false)
	cv.mouse_m = pc + Vector2(0, 2)
	cv._drag_update()
	assert_true(ed.views.busy(), "glissement en cours")
	var h := MapOps.hash_of(ed.doc)
	var n0 := ed.doc.objets.size()
	ed.nudge_selection(Vector2.RIGHT)
	ed.rotate_selection()
	ed.delete_selection()
	ed.paste(Vector2(9, 8.5))
	ed.duplicate_selection()
	ed.cut_selected()
	assert_eq(MapOps.hash_of(ed.doc), h, "rien n'a changé pendant le glissement")
	assert_eq(ed.doc.objets.size(), n0)
	assert_true(ed._status_error, "message : terminer ou annuler le glissement")
	ed.create_prefab_from_selection()
	assert_true(ed.get_node_or_null("CreatePrefabDialog") == null, "pas de boîte de prefab pendant le glissement")
	var u0 := _undo_count(ed)
	cv._release()
	assert_eq(_pos(ed.doc, c), pc + Vector2(0, 2), "le glissement s'applique tel quel")
	assert_eq(_undo_count(ed), u0 + 1, "une seule étape")
	ed.queue_free()


## Ctrl+X d'une pièce meublée : le presse-papiers prend exactement ce qui est
## supprimé (pièce, contenu, portes de ses bords) ; Ctrl+V rend tout.
func test_cut_room_with_content_pastes_everything() -> void:
	var ed: MapEditor = await _editor()
	var pa := String(ed.doc.pieces[0].id)
	var removed := MapGroup.movers(ed.doc, [pa])
	var counts := [ed.doc.pieces.size(), ed.doc.ouvertures.size(), ed.doc.objets.size()]
	ed.select(pa)
	ed.cut_selected()
	assert_true(ed.doc.find(pa).is_empty(), "pièce coupée")
	assert_eq(ed.doc.objets.size() + ed.doc.ouvertures.size() + ed.doc.pieces.size() + removed.size(), counts[0] + counts[1] + counts[2], "contenu supprimé avec elle")
	assert_eq((ed.clipboard.get("items", []) as Array).size(), removed.size(), "presse-papiers = ce qui a été supprimé")
	# Collé sous la souris au centre d'origine du tout : chaque élément revient.
	ed.paste(MapGroup.bounds_of(ed.doc, ed.clipboard.items).get_center() + Vector2(0.2, -0.3))
	assert_eq([ed.doc.pieces.size(), ed.doc.ouvertures.size(), ed.doc.objets.size()], counts, "tout revient (%s)" % ed.status.text)
	assert_eq(ed.sel_ids().size(), removed.size(), "le tout sélectionné")
	var caisses := _id(ed.doc, "caisses")
	assert_eq(_pos(ed.doc, caisses), Vector2(4, 5.5), "le décor revient à sa place")
	ed.queue_free()


## Créer une prefab : refusé sur plusieurs étages ; la sélection est relue au
## moment de valider (éléments supprimés entre-temps par un autre).
func test_prefab_dialog_rereads_selection_and_refuses_floors() -> void:
	var ed: MapEditor = await _editor()
	var c := _id(ed.doc, "caisses")
	var s := _id(ed.doc, "sacs_sable")
	# Un décor à l'étage 1 : sélection sur deux étages refusée.
	ed.add_floor()
	ed.set_floor(0)
	var up := DecorFree._obj(ed.doc, {"type": "prefab", "prefab": "caisses", "position": [4.0, 5.5], "rot": 0})
	up["altitude"] = 1 * EditorMap.FLOOR_STEP
	ed.changed()
	ed.select_many([c, String(up.id)])
	assert_eq(ed.prefab_tools.create_dialog_for(ed.sel_ids()), null, "deux étages : refusé")
	assert_true(ed._status_error and ed.status.text.contains(Lang.t("étages", "floors")), "message (%s)" % ed.status.text)
	ed.select_many([c, String(up.id)])
	ed.open_context_menu(Vector2(100, 100), Vector2.INF, "")
	assert_true(ed.context_menu.states()[MapContextMenu.PREFAB] != "", "menu : prefab grisée sur deux étages")
	ed.context_menu.hide()
	# Boîte ouverte, puis un autre supprime les sacs : seule la caisse est prise.
	ed.select_many([c, s])
	var d := ed.prefab_tools.create_dialog_for(ed.sel_ids())
	ed.doc.remove(s)
	ed.changed()
	(d.find_child("Replace", true, false) as CheckBox).button_pressed = false
	d.confirmed.emit()
	await wait_frames(1)
	assert_eq(ed.doc.prefabs.size(), 1, "prefab créée avec ce qui reste")
	assert_eq((ed.doc.prefabs.values()[0].parties as Array).size(), 1, "une seule partie (sacs supprimés entre-temps)")
	# Tout supprimé entre-temps : refusé, rien de créé.
	ed.select_mouse()
	ed.select(c)
	var d2 := ed.prefab_tools.create_dialog_for(ed.sel_ids())
	ed.doc.remove(c)
	ed.changed()
	d2.confirmed.emit()
	await wait_frames(1)
	assert_eq(ed.doc.prefabs.size(), 1, "plus rien à grouper : refusé")
	assert_true(ed._status_error, "message de refus")
	ed.queue_free()
