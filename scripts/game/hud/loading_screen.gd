class_name LoadingScreen
extends Control
## Écran de chargement d'une partie (Hud.show_loading) : fond bleu-noir des
## écrans du laboratoire, nom de la carte en cubes (CubeFont), et une rangée
## de cubes qui s'allument tour à tour sous « CHARGEMENT... ».

const CUBES := 7
const CUBE := 14.0
## Un cube de plus s'allume toutes les STEP secondes, puis la rangée repart.
const STEP := 0.12

var title: Label
var _t := 0.0
var _bar: Control


func setup(map_name: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.03, 0.035)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	title = HudStyle.label(map_name, 72, HudStyle.TITLE, "cube")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(CUBES * CUBE * 1.5, CUBE + 4.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar.bind(bar))
	box.add_child(bar)
	var sub := HudStyle.label(Lang.t("CHARGEMENT...", "LOADING..."), 20, HudStyle.TEXT_DIM, "text", 2)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_bar = bar


func _process(delta: float) -> void:
	_t += delta
	if _bar:
		_bar.queue_redraw()


func _draw_bar(bar: Control) -> void:
	var lit := int(_t / STEP) % (CUBES + 3)
	for i in CUBES:
		var r := Rect2(i * CUBE * 1.5, 2.0, CUBE, CUBE)
		bar.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.8))
		var on := i < lit
		CubeFont.draw_cube(bar, r, HudStyle.ROUND if on else HudStyle.ROUND.darkened(0.75))
