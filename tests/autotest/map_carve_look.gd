extends AutotestScenario
## @rendu : DÉCOUPE DES PIÈCES de l'éditeur de cartes (MapCarve,
## docs/MAP_AUTHORING.md § 3, « Pièce tracée sur une autre »), en français
## puis en anglais : pièce rectangle tracée au milieu d'une autre (partie
## retirée hachurée en orange pendant le tracé), boîte « Découper des pièces »
## au relâcher, résultat (anneau coupé en deux morceaux reliés par des
## passages libres, contenu passé à la nouvelle pièce ; vues Dessus, Avant et
## 3D) ; puis une pièce à cheval sur deux pièces (deux hachures, porte retirée)
## et sa boîte. Carte en mémoire (rien d'écrit dans le dossier des cartes).
## Captures : tests/_out/shots/map_carve_look_*.png.

var ed: MapEditor


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var lang0 := String(Settings.language)
	for lang in ["fr", "en"]:
		Settings.language = lang
		tree().change_scene_to_file(MapEditor.SCENE)
		if not await until(func(): return tree().current_scene is MapEditor and tree().current_scene != ed, 6.0, "éditeur ouvert"):
			break
		ed = tree().current_scene
		await frames(3)
		ed.new_map(true)
		ed.doc = _map()
		ed.collab.reset_doc(ed.doc)
		ed.changed()
		await frames(2)
		ed.views.frame_all()
		ed.pick_item("piece_rect")
		await frames(2)
		var cv := ed.canvas
		# 1. Tracé en cours au milieu de l'atelier : partie retirée hachurée.
		cv.drag = {"kind": "create", "start": Vector2(7, 5)}
		cv.mouse_m = Vector2(11, 9)
		cv.queue_redraw()
		await frames(2)
		var res := cv._creation(ed.current_item(), Vector2(7, 5), cv.trace_end())
		at.check(res.get("ok", false) and res.has("carve"), "découpe prévue pendant le tracé (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("trace_" + lang)
		# 2. Relâcher : la boîte.
		cv._finish_create(cv.trace_end())
		var d: ConfirmationDialog = ed.carve_dialog
		await frames(3)
		at.check(d != null and d.visible, "boîte « Découper des pièces » (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("confirmation_" + lang)
		# Entrée : Découper (le bouton a le focus).
		var n0: int = ed.collab.history.entries.size()
		if d != null:
			at.check(d.get_ok_button().has_focus(), "Découper a le focus (Entrée)")
			d.get_ok_button().pressed.emit()
		await frames(3)
		at.check(ed.doc.pieces.size() == 4, "nouvelle pièce + atelier en deux morceaux (%d pièces)" % ed.doc.pieces.size())
		at.check(ed.collab.history.entries.size() == n0 + 1, "une seule étape d'annulation")
		# 3. Résultat : dessus, avant et 3D.
		ed.views.set_layout("4")
		await frames(3)
		ed.views.frame_all()
		await seconds(0.8)
		await at.screenshot("resultat_" + lang)
		ed.views.set_layout("1")
		await frames(2)
		# 4. Annuler : tout revient d'un coup.
		ed.undo()
		await frames(2)
		at.check(ed.doc.pieces.size() == 2, "Ctrl+Z : tout est défait")
		# 5. Pièce à cheval sur l'atelier et le couloir (porte au milieu).
		ed.views.frame_all()
		cv.drag = {"kind": "create", "start": Vector2(13, 3)}
		cv.mouse_m = Vector2(19, 7)
		cv.queue_redraw()
		await frames(2)
		await seconds(0.3)
		await at.screenshot("deux_pieces_" + lang)
		cv._finish_create(cv.trace_end())
		d = ed.carve_dialog
		await frames(3)
		at.check(d != null and d.visible and d.dialog_text.contains(Lang.t("Ouvertures retirées", "Openings removed")), "boîte : porte retirée (%s)" % (d.dialog_text if d != null else ""))
		await seconds(0.3)
		await at.screenshot("deux_pieces_confirmation_" + lang)
		if d != null:
			d.get_cancel_button().pressed.emit()
		await frames(2)
		at.check(ed.doc.pieces.size() == 2, "Annuler : rien de créé")
	Settings.language = lang0


## Atelier (14 × 10 m) avec des caisses, couloir à l'est, porte entre les deux.
static func _map() -> EditorMap:
	var doc := EditorMap.blank("decoupe", "DÉCOUPE", "CUT")
	var za := doc.add_zone("Atelier", "Workshop")
	var zc := doc.add_zone("Couloir", "Corridor")
	doc.pieces.append({"id": "p1", "nom": "Atelier", "etage": 0, "zone": String(za.id), "contour": [[2, 2], [16, 2], [16, 12], [2, 12]]})
	doc.pieces.append({"id": "p2", "nom": "Couloir", "etage": 0, "zone": String(zc.id), "contour": [[16, 2], [20, 2], [20, 12], [16, 12]]})
	doc.ouvertures.append({"id": "o1", "type": "porte", "etage": 0, "position": [16, 4.75], "largeur": 2, "prix": 750})
	doc.ouvertures.append({"id": "o2", "type": "fenetre", "etage": 0, "position": [5.25, 12]})
	doc.objets.append({"id": "c1", "type": "caisse", "etage": 0, "position": [9.0, 7.0]})
	doc.objets.append({"id": "c2", "type": "caisse", "etage": 0, "position": [4.0, 4.0]})
	doc.objets.append({"id": "b1", "type": "baril", "etage": 0, "position": [13.5, 10.5]})
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [4.0, 9.0]})
	doc.depart = String(za.id)
	return doc
