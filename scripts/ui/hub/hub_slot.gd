class_name HubSlot
extends MarginContainer
## Emplacement du hub (classe .slot de la maquette) : encadré enfoncé très
## sombre à contour noir (pièce installée, arme de départ choisie), ou
## emplacement libre en pointillés gris (.slot.empty). Choisissable au
## clavier, à la manette et au clic : anneau jaune de 3 px autour
## (.focus-ring) quand il a le focus ou qu'il est `marked` (pièce visée par un
## retrait en deux appuis). Entrée / A / clic : `activated`. Le contenu est
## dans `box`.

signal activated
## Le focus est arrivé sur l'emplacement.
signal chosen

var empty := false:
	set(v):
		empty = v
		queue_redraw()
## Anneau jaune même sans le focus.
var marked := false:
	set(v):
		marked = v
		queue_redraw()
var hint := ""
var index := 0
## Faux : un clic choisit seulement l'emplacement (Entrée / A, double clic
## l'activent).
var click_activates := true
var box: BoxContainer


## `vertical` : contenu en colonne, centré (emplacements de DÉPART).
func _init(height := 76.0, vertical := false, sep := 10.0) -> void:
	custom_minimum_size = Vector2(0, HubStyle.px(height))
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var b := HubStyle.px(2)
	add_theme_constant_override("margin_left", int(HubStyle.px(10) + b))
	add_theme_constant_override("margin_right", int(HubStyle.px(10) + b))
	add_theme_constant_override("margin_top", int(HubStyle.px(8) + b))
	add_theme_constant_override("margin_bottom", int(HubStyle.px(8) + b))
	box = HubBox.vbox(sep) if vertical else HubBox.hbox(sep)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	focus_entered.connect(func():
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		queue_redraw()
		chosen.emit())
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var b := HubStyle.px(2)
	if has_focus() or marked:
		# .focus-ring : ombre noire décalée de 4 px élargie de 3, anneau jaune de 3 px.
		var t := maxf(HubStyle.px(3), 2.0)
		draw_rect(Rect2(r.position + HubStyle.pxv(4, 4), r.size).grow(t), HubStyle.BLACK)
		draw_rect(r.grow(t), HubStyle.YELLOW)
	if empty:
		draw_rect(r, Color("141516"))
		_dashed(r, b, HubStyle.ASH)
	else:
		HubStyle.draw_box(self, r, HubStyle.GROUP_BG, b, 0.0, HubStyle.HEADER_BG, Color(0, 0, 0, 0), b)


## Contour en pointillés (tirets de 6 px, espaces de 4 px).
func _dashed(r: Rect2, w: float, col: Color) -> void:
	var dash := HubStyle.px(6)
	var gap := HubStyle.px(4)
	var x := 0.0
	while x < r.size.x:
		var l := minf(dash, r.size.x - x)
		draw_rect(Rect2(r.position.x + x, r.position.y, l, w), col)
		draw_rect(Rect2(r.position.x + x, r.end.y - w, l, w), col)
		x += dash + gap
	var y := 0.0
	while y < r.size.y:
		var l := minf(dash, r.size.y - y)
		draw_rect(Rect2(r.position.x, r.position.y + y, w, l), col)
		draw_rect(Rect2(r.end.x - w, r.position.y + y, w, l), col)
		y += dash + gap


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not has_focus():
			grab_focus()
		if click_activates or mb.double_click:
			Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
			activated.emit()
		return
	if event.is_action_pressed("ui_accept"):
		accept_event()
		Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
		activated.emit()
