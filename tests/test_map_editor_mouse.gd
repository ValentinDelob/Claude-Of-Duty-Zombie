extends TestCase
## Souris de l'éditeur de cartes : case fixe à gauche de la barre rapide,
## outil par défaut, jamais remplacée par un objet de l'inventaire ; Échap
## (après l'annulation du tracé) et ² y reviennent ; la molette y passe ;
## une barre enregistrée avec l'ancien outil « select » est corrigée.

const TMP := "res://tests/_out/test_map_editor_mouse"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	return ed


func _key(ed: MapEditor, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	ed._input(e)


func test_catalog_and_migration() -> void:
	assert_false(MapCatalog.DEFAULT_HOTBAR.has("select"), "la souris n'est pas dans la barre par défaut")
	assert_eq(MapCatalog.DEFAULT_HOTBAR.size(), 9)
	assert_false(MapCatalog.in_category("construction").any(func(it): return it.id == "select"), "souris absente de l'inventaire")
	assert_false(MapCatalog.item("select").is_empty(), "l'outil reste au catalogue")
	var old := MapHotbar.migrate(["select", "piece_rect", "inconnu", 3, "mur"])
	assert_eq(old, ["", "piece_rect", "", "", "mur", "", "", "", ""], "ancien « select » retiré, 9 cases")


func test_mouse_is_default_and_never_lost() -> void:
	var ed: MapEditor = await _editor()
	assert_eq(ed.hot_index, MapEditor.MOUSE, "l'éditeur démarre sur la souris")
	assert_true(ed.mouse_active())
	assert_eq(ed.tool(), "select")
	assert_eq(ed.hotbar_ui._name.text, Lang.t("Souris", "Mouse"))
	assert_true(ed.hotbar_ui.mouse_slot.selected, "case de la souris en surbrillance")
	assert_true(ed.hotbar_ui.mouse_slot._get_drag_data(Vector2.ZERO) == null, "la souris ne se glisse pas")
	assert_false(ed.hotbar_ui.mouse_slot._can_drop_data(Vector2.ZERO, {"map_item": "mur"}), "rien ne se dépose sur la souris")
	# Barre pleine, souris en main : l'objet va dans la dernière case choisie.
	ed.select_slot(3)
	ed.select_mouse()
	ed.pick_item("debris")
	assert_eq(ed.hot_index, 3, "barre pleine : dernière case choisie")
	assert_eq(ed.current_item().id, "debris")
	# Case vide, souris en main : la première case vide.
	ed.hotbar[6] = ""
	ed.select_mouse()
	ed.pick_item("pilier")
	assert_eq(ed.hot_index, 6, "première case vide")
	assert_eq(String(ed.hotbar[6]), "pilier")
	# Case choisie : l'objet la remplace, comme avant.
	ed.select_slot(1)
	ed.pick_item("gomme")
	assert_eq(String(ed.hotbar[1]), "gomme")
	# L'ancien « select » choisi (glissé, MCP) : la souris, aucune case perdue.
	var before := ed.hotbar.duplicate()
	ed.set_hotbar(2, "select")
	assert_eq(ed.hot_index, MapEditor.MOUSE)
	assert_eq(ed.hotbar, before, "barre inchangée")
	# Case vide en main : la souris.
	ed.hotbar[0] = ""
	ed.select_slot(0)
	assert_true(ed.mouse_active(), "case vide : souris")
	ed.queue_free()


func test_keys_and_wheel() -> void:
	var ed: MapEditor = await _editor()
	_key(ed, KEY_4)
	assert_eq(ed.hot_index, 3)
	_key(ed, KEY_QUOTELEFT)
	assert_eq(ed.hot_index, MapEditor.MOUSE, "² : la souris")
	# Molette : souris, puis 1 ; en arrière depuis la souris, la case 9.
	ed.cycle_hotbar(1)
	assert_eq(ed.hot_index, 0)
	ed.cycle_hotbar(-1)
	assert_eq(ed.hot_index, MapEditor.MOUSE)
	ed.cycle_hotbar(-1)
	assert_eq(ed.hot_index, 8)
	ed.cycle_hotbar(1)
	assert_eq(ed.hot_index, MapEditor.MOUSE)
	# Échap : d'abord le tracé en cours, puis la souris.
	_key(ed, KEY_3)
	assert_eq(ed.current_item().id, "piece_poly")
	ed.canvas.poly_pts.append(Vector2(2, 2))
	ed.canvas.poly_pts.append(Vector2(6, 2))
	_key(ed, KEY_ESCAPE)
	assert_true(ed.canvas.poly_pts.is_empty(), "premier Échap : tracé annulé")
	assert_eq(ed.hot_index, 2, "outil gardé")
	_key(ed, KEY_ESCAPE)
	assert_eq(ed.hot_index, MapEditor.MOUSE, "Échap suivant : la souris")
	ed.queue_free()
