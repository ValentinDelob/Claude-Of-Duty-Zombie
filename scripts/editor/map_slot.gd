class_name MapSlot
extends Control
## Case d'inventaire de l'éditeur de cartes (barre rapide ou inventaire) :
## icône dessinée par code, numéro, surbrillance. Glisser une case de
## l'inventaire vers la barre rapide y range l'objet (glisser-déposer Godot).

signal clicked(slot: MapSlot)

var item_id := ""
## Index dans la barre rapide (-1 : case de l'inventaire).
var index := -1
var selected := false
var ed: MapEditor
## Case fixe (la souris de la barre rapide) : ni glissée, ni remplacée.
var fixed := false
## Touche affichée dans le coin (case fixe ; les cases de la barre montrent
## leur numéro).
var key_label := ""


func _init(size_px := 48.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_item(id: String) -> void:
	item_id = id
	var it := MapCatalog.item(id)
	if it.is_empty():
		tooltip_text = Lang.t("Case vide : glissez-y un objet de l'inventaire (E)", "Empty slot: drag an item from the inventory (E)")
	else:
		var t := MapCatalog.name_of(it)
		var hint := Lang.t(String(it.get("hint_fr", "")), String(it.get("hint_en", "")))
		if hint != "":
			t += "\n" + hint
		if int(it.get("price", 0)) > 0:
			t += "\n" + Lang.t("Prix en jeu : %d", "In-game price: %d") % int(it.price)
		if fixed:
			t += "\n" + Lang.t("Toujours là : clic, touche ² ou Échap", "Always there: click, ` key or Esc")
		tooltip_text = t
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.07, 0.07, 0.08, 0.92))
	draw_rect(r.grow(-2), Color(0.16, 0.16, 0.17, 0.95))
	MapIcons.draw(self, MapCatalog.item(item_id), r.grow(-3))
	draw_rect(r, Color(1.0, 0.85, 0.3) if selected else Color(0.35, 0.35, 0.38), false, 3.0 if selected else 1.0)
	var corner := str(index + 1) if index >= 0 else key_label
	if corner != "":
		var font := UiStyle.font("impact")
		var at := Vector2(EditorUi.px(4.0), EditorUi.px(14.0))
		draw_string_outline(font, at, corner, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), 3, Color.BLACK)
		draw_string(font, at, corner, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), Color(1, 1, 1, 0.8))


func _gui_input(event: InputEvent) -> void:
	# Clic au relâchement : un glisser-déposer ne compte pas comme un clic.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not get_viewport().gui_is_dragging():
			clicked.emit(self)
		accept_event()


func _get_drag_data(_pos: Vector2) -> Variant:
	if item_id == "" or fixed:
		return null
	var p := MapSlot.new(EditorUi.px(44.0))
	p.set_item(item_id)
	set_drag_preview(p)
	return {"map_item": item_id, "from_slot": index}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return index >= 0 and data is Dictionary and data.has("map_item")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var from := int(data.get("from_slot", -1))
	if from >= 0 and from != index:
		# D'une case de la barre à une autre : échange.
		var here := item_id
		ed.hotbar[from] = here
	ed.set_hotbar(index, String(data.map_item))
