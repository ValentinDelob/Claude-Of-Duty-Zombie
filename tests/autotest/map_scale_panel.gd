extends AutotestScenario
## Panneau Propriétés d'un décor (format 14, docs/EDITOR_SCALE_ROTATE.md
## § 2.5) dans le vrai éditeur : champ Uniforme (×1,5 : les trois axes),
## cadenas ouvert (X seul), « ↺ ×1 », Rotation Y (+30° : poutre inclinée,
## posée au sol), « ↺ Remettre droit » ; un champ validé = une annulation ;
## prefab qui contient un téléporteur : encadré qui le nomme, champs grisés,
## refus nommé ; valeur refusée remise (trop haut pour le plafond).

const Free := preload("res://tests/test_map_decor_free.gd")
const Scale := preload("res://tests/test_map_scale.gd")

var ed: MapEditor


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var lock0: Variant = MapEditor.pref(MapPanelsScale.PREF_LOCK, true)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	MapEditor.set_pref(MapPanelsScale.PREF_LOCK, true)
	ed.new_map(true)
	var doc := Free.two_rooms()
	doc.pieces[1]["plafond"] = 6.8
	doc.prefabs["coin_tp"] = Scale.GAME_DEF.duplicate(true)
	doc.objets.append({"id": "d81", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [4.0, 4.0]})
	doc.objets.append({"id": "d82", "type": "prefab", "prefab": "poutre", "altitude": 0, "position": [19.0, 5.5]})
	doc.objets.append({"id": "d83", "type": "prefab", "prefab": "map:coin_tp", "altitude": 0, "position": [9.0, 3.0]})
	ed._reset(doc)
	ed.doc.activate_prefabs()
	await frames(3)
	var undo0 := ed.collab.history.undo_count(ed.collab.my_id)

	# Uniforme ×1,5 : les trois axes, une annulation.
	ed.select("d81")
	await _panel()
	_submit("U", "1,5")
	await _panel()
	var c1 := ed.doc.find("d81")
	at.check(MapScale.scale_of(c1).is_equal_approx(Vector3.ONE * 1.5), "Uniforme ×1,5 : %s" % str(MapScale.scale_of(c1)))
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0 + 1, "un champ validé = une annulation")
	var note: Label = ed.panels._scale_fields.get("note")
	at.check(note != null and note.text.begins_with(Lang.t("3,75 × 3,00 × 2,25 m (d'origine 2,50 × 2,00 × 1,50)", "3.75 × 3.00 × 2.25 m (originally 2.50 × 2.00 × 1.50)")),
		"note des dimensions (%s)" % (note.text if note else "?"))
	# Cadenas fermé : X à 2 -> les trois en proportion.
	_submit("SX", "2")
	await _panel()
	at.check(MapScale.scale_of(ed.doc.find("d81")).is_equal_approx(Vector3.ONE * 2.0), "cadenas fermé : les trois axes suivent")
	# Cadenas ouvert : X seul.
	_button_with("", true).pressed.emit()
	await _panel()
	at.check(not bool(MapEditor.pref(MapPanelsScale.PREF_LOCK, true)), "cadenas ouvert (préférence de l'interface)")
	_submit("SX", "1")
	await _panel()
	at.check(MapScale.scale_of(ed.doc.find("d81")).is_equal_approx(Vector3(1, 2, 2)), "cadenas ouvert : X seul (%s)" % str(MapScale.scale_of(ed.doc.find("d81"))))
	# ↺ ×1 : clé retirée.
	_button_with("↺ ×1").pressed.emit()
	await _panel()
	at.check(not ed.doc.find("d81").has("echelle"), "↺ ×1 : échelle retirée")
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0 + 4, "quatre actions, quatre annulations")
	ed.undo()
	await _panel()
	at.check(MapScale.scale_of(ed.doc.find("d81")).is_equal_approx(Vector3(1, 2, 2)), "Ctrl+Z : l'échelle d'avant revient")

	# Rotation Y +30° : poutre inclinée, point le plus bas au sol.
	ed.select("d82")
	await _panel()
	_submit("RY", "+30")
	await _panel()
	var p1 := ed.doc.find("d82")
	at.check(MapScale.incl_of(p1).is_equal_approx(Vector2(0, 30)) and MapVertical.decor_z(p1) == 0.0, "Rotation Y +30° (%s), posée au sol" % str(MapScale.incl_of(p1)))
	var rn: Label = ed.panels._scale_fields.get("rnote")
	at.check(rn != null and rn.text.contains("5,06"), "note : le haut monte à 5,06 m (%s)" % (rn.text if rn else "?"))
	# Valeur refusée (poutre dressée à 80° : 7 m sous 6,80 m) : remise, raison affichée.
	_submit("RY", "80")
	await _panel()
	at.check(MapScale.incl_of(ed.doc.find("d82")).is_equal_approx(Vector2(0, 30)), "80° refusé : l'inclinaison reste")
	at.check(ed.status.text.begins_with(Lang.t("trop haut pour le plafond", "too tall for the ceiling")), "raison : %s" % ed.status.text)
	_button_with(Lang.t("↺ Remettre droit", "↺ Set upright")).pressed.emit()
	await _panel()
	at.check(not ed.doc.find("d82").has("incl"), "↺ Remettre droit")

	# Prefab qui contient un téléporteur : bloqué, nommé.
	ed.select("d83")
	await _panel()
	var warn := _rich()
	at.check(warn != null and warn.get_parsed_text().contains("porte"), "encadré : contient un téléporteur (%s)" % (warn.get_parsed_text() if warn else "?"))
	at.check(not _edit("U").editable and not _edit("SX").editable and not _edit("RX").editable and _edit("RZ").editable, "échelle et inclinaison grisées, rotation Z permise")
	var r := MapPanelsScale.apply(ed, "d83", func(c: Dictionary): MapScale.set_scale(c, Vector3.ONE * 2))
	at.check(not r.ok and String(r.fr) == "Échelle impossible : « Coin téléporteur » contient un téléporteur (objet de jeu à taille fixe)", "refus nommé : %s" % str(r.get("fr", "")))
	_submit("RZ", "90")
	await _panel()
	at.check(MapGeom.rot_of(ed.doc.find("d83")) == 90, "rotation Z du prefab bloqué")
	MapEditor.set_pref(MapPanelsScale.PREF_LOCK, lock0)


func _panel() -> void:
	await frames(3)


func _field(key: String) -> PanelContainer:
	return ed.panels._scale_fields.get(key)


func _edit(key: String) -> LineEdit:
	var f := _field(key)
	if f == null:
		return LineEdit.new()
	var hb := f.get_child(0)
	return hb.get_child(hb.get_child_count() - 1) as LineEdit


func _submit(key: String, text: String) -> void:
	var e := _edit(key)
	e.text = text
	e.text_submitted.emit(text)


func _button_with(text: String, lock := false) -> Button:
	for b in ed.panels._props.find_children("*", "Button", true, false):
		if lock and b.get_child_count() > 0 and b.get_child(0) is MapPanelsScale.LockIcon:
			return b
		if not lock and (b as Button).text == text:
			return b
	at.fail("bouton « %s » introuvable" % text)
	return Button.new()


func _rich() -> RichTextLabel:
	var l := ed.panels._props.find_children("*", "RichTextLabel", true, false)
	return l[0] if not l.is_empty() else null
