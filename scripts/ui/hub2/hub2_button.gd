class_name Hub2Button
extends BaseButton
## Bouton du hub v2 : un BaseButton (focus clavier / manette, clic, `pressed`)
## qui ne dessine rien lui-même : son aspect vient de ses enfants (en général
## un Hub2Box `box` plein cadre et des Hub2Text), comme un <button> / <a>
## stylé des maquettes. Les maquettes ne dessinent pas le focus : un cadre
## jaune de 2 px (#F5C542) le montre à la manette et au clavier
## (`show_focus`, désactivable), jamais à la souris.
##
##   var b := Hub2Button.new()
##   b.box.glass()                       # fond du bouton
##   b.box.pad(18, 22)
##   b.box.add_child(contenu)
##   b.hint = Lang.t("…", "…")           # aide dans la barre d'invites
##   b.pressed.connect(…)

## Fond et conteneur du contenu (MarginContainer : padding CSS).
var box: Hub2Box
## Aide affichée dans la barre d'invites quand le bouton a le focus.
var hint := ""
## Cadre de focus (manette, clavier).
var show_focus := true

var _ring: Control
var _mouse_focus := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box = Hub2Box.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.flat(Color(0, 0, 0, 0))
	add_child(box)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	box.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return box.get_combined_minimum_size() if box else Vector2.ZERO


func _on_focus(on: bool) -> void:
	if on:
		# Focus pris au clic : pas de cadre (seulement manette / clavier).
		_mouse_focus = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var hub := _hub()
		if hub and hint != "":
			hub.call("set_hint", hint)
	else:
		var hub2 := _hub()
		if hub2 and hint != "":
			hub2.call("set_hint", "")
	_ring.queue_redraw()


func _hub() -> Node:
	var n := get_parent()
	while n and not n.has_method("refresh_prompts"):
		n = n.get_parent()
	return n


func _draw_ring() -> void:
	if not (show_focus and has_focus() and not _mouse_focus):
		return
	var w := maxf(Hub2Style.px(2), 1.0)
	var r := Rect2(Vector2.ZERO, size)
	_ring.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), Hub2Style.YELLOW)
	_ring.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), Hub2Style.YELLOW)
	_ring.draw_rect(Rect2(r.position.x, r.position.y, w, r.size.y), Hub2Style.YELLOW)
	_ring.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), Hub2Style.YELLOW)


## Le contenu ajouté après la création passe au-dessus du fond mais sous le
## cadre de focus.
func add_content(c: Control) -> void:
	box.add_child(c)
