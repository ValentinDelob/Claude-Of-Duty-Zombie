class_name Hub2Modal
extends Control
## Fenêtre par-dessus un écran du hub v2 (pas de maquette : style des
## panneaux) : voile rgba(8, 9, 11, 0.7) plein cadre, panneau de verre
## centré (largeur `width`), titre Chakra Petch 20 px 700 0.08em, sous-titre
## Barlow 13 px, puis le contenu (`body`, VBox écart 6). Clic sur le voile ou
## `close()` : fermée (signal `closed`). L'écran qui l'ouvre la ferme sur
## B / Échap (Hub2Panel.back).
##
##   var m := Hub2Modal.new()
##   m.setup("CHANGER DE CARTE", "envoyée à tout le groupe", 460)
##   m.body.add_child(…)
##   panneau.add_child(m)

signal closed

var box: Hub2Box
var body: VBoxContainer
var title_text: Hub2Text
var sub_label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(title: String, sub: String, width := 460.0) -> void:
	var veil := ColorRect.new()
	veil.color = Hub2Style.shade(0.7)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	add_child(Hub2Style.blur_barrier())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	box = Hub2Box.new()
	box.glass(Hub2Style.GLASS_STRONG, Hub2Style.white_a(0.12), 1.0)
	box.pad(22, 24)
	box.custom_minimum_size.x = Hub2Style.px(width)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(box)
	var v := Hub2Ui.vbox(14)
	box.add_child(v)
	var head := Hub2Ui.vbox(4)
	v.add_child(head)
	title_text = Hub2Text.new()
	title_text.setup(title, Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT, 0.08)
	head.add_child(title_text)
	sub_label = Hub2Ui.paragraph(sub, 13, 0.6)
	sub_label.visible = sub != ""
	head.add_child(sub_label)
	body = Hub2Ui.vbox(6)
	v.add_child(body)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


## Ligne choisissable de la fenêtre (comme les lignes de cartes de JOUER) :
## nom (Chakra Petch 16 px 700), sous-titre (Barlow 12 px), note à droite
## (JetBrains Mono 12 px) ; `on` : choisie (fond jaune pâle, liseré jaune).
func add_row(title: String, sub: String, note: String, on: bool) -> Hub2Button:
	var b := Hub2Button.new()
	set_row_on(b, on)
	b.box.pad(10, 14)
	var h := Hub2Ui.hbox(12)
	b.add_content(h)
	var v := Hub2Ui.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := Hub2Text.new()
	t.setup(title, Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.03)
	v.add_child(t)
	if sub != "":
		v.add_child(Hub2Style.label(sub, Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55)))
	if note != "":
		var n := Hub2Text.new()
		n.setup(note, Hub2Style.MONO, 500, 12, Hub2Style.text_a(0.55))
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(n)
	body.add_child(b)
	return b


static func set_row_on(b: Hub2Button, on: bool) -> void:
	b.box.glass(Hub2Style.yellow_a(0.1) if on else Hub2Style.GLASS, Hub2Style.YELLOW if on else Hub2Style.LINE, 1.0, 0.0)
