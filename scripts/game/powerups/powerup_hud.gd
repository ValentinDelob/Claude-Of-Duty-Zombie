class_name PowerupHud
extends Control
## Partie du HUD dédiée aux bonus : icônes des bonus temporisés en bas au
## centre (clignotent à la fin), annonce du bonus ramassé (gros texte qui
## monte et s'estompe), éclair blanc de la nuke. Dessins procéduraux.

const ICON := 58.0
const GAP := 14.0
## Distance du bas de l'écran au bas des icônes.
const BOTTOM := 96.0

var game: Game
var _announce: Label
var _flash: ColorRect


## Ancrages posés AVANT l'ajout sous le CanvasLayer (sinon taille nulle).
func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 1.0, 0.96, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_announce = UiStyle.label("", 46, Color(0.92, 0.95, 0.85), "title")
	_announce.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.offset_left = -500
	_announce.offset_right = 500
	_announce.offset_top = -250
	_announce.offset_bottom = -190
	_announce.add_theme_color_override("font_outline_color", Color(0.05, 0.25, 0.05, 0.9))
	_announce.add_theme_constant_override("outline_size", 8)
	_announce.modulate.a = 0.0
	add_child(_announce)


## Texte « façon BO1 » à la prise d'un bonus.
func announce(type: String) -> void:
	_announce.text = PowerupRules.display_name(type)
	_announce.modulate.a = 1.0
	_announce.scale = Vector2.ONE
	_announce.pivot_offset = Vector2(500, 30)
	_announce.offset_top = -250
	_announce.offset_bottom = -190
	var tw := _announce.create_tween().set_parallel(true)
	tw.tween_property(_announce, "offset_top", -330.0, 2.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(_announce, "offset_bottom", -270.0, 2.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(_announce, "modulate:a", 0.0, 1.6).set_delay(1.0)


func nuke_flash() -> void:
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", 0.95, 0.12)
	tw.tween_interval(0.25)
	tw.tween_property(_flash, "color:a", 0.0, 1.4).set_ease(Tween.EASE_IN)


## Bonus temporisés affichés (ordre fixe), pour le dessin et les tests.
func shown_icons() -> Array:
	var out := []
	if game == null or game.powerups == null:
		return out
	for type in PowerupRules.TIMED:
		if game.powerups.is_active(type):
			out.append(type)
	return out


var _drawn := false


func _process(_delta: float) -> void:
	# Redessin seulement quand des icônes sont (ou étaient) affichées.
	var any := game != null and game.powerups != null and not game.powerups.timers.is_empty()
	if any or _drawn:
		_drawn = any
		queue_redraw()


func _draw() -> void:
	var list := shown_icons()
	if list.is_empty():
		return
	var total := list.size() * ICON + (list.size() - 1) * GAP
	var x0 := (size.x - total) * 0.5
	var y := size.y - BOTTOM - ICON
	for i in list.size():
		var type: String = list[i]
		var left: float = game.powerups.timers.get(type, 0.0)
		if not PowerupRules.hud_icon_visible(left):
			continue
		var r := Rect2(Vector2(x0 + i * (ICON + GAP), y), Vector2(ICON, ICON))
		_icon(type, r)


func _icon(type: String, r: Rect2) -> void:
	var c := r.get_center()
	var k := r.size.x * 0.34
	var green := Color(0.35, 1.0, 0.4)
	# Halo vert et cadre.
	draw_circle(c, r.size.x * 0.62, Color(0.2, 0.9, 0.25, 0.14))
	draw_rect(r, Color(0.02, 0.06, 0.02, 0.75))
	draw_rect(r, green, false, 2.0)
	match type:
		PowerupRules.INSTA_KILL:  # crâne
			var bone := Color(0.9, 0.87, 0.76)
			draw_circle(c + Vector2(0, -0.15 * k), k * 0.85, bone)
			draw_rect(Rect2(c + Vector2(-0.5 * k, 0.35 * k), Vector2(k, 0.55 * k)), bone)
			for dx in [-0.36, 0.36]:
				draw_circle(c + Vector2(dx * k, -0.1 * k), k * 0.24, Color(0.05, 0.05, 0.05))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.12 * k), c + Vector2(-0.12 * k, 0.35 * k), c + Vector2(0.12 * k, 0.35 * k)]), Color(0.05, 0.05, 0.05))
			for j in 4:
				draw_line(c + Vector2((-0.3 + j * 0.2) * k, 0.55 * k), c + Vector2((-0.3 + j * 0.2) * k, 0.9 * k), Color(0.05, 0.05, 0.05), 1.5)
		PowerupRules.DOUBLE_POINTS:  # x2
			var gold := UiStyle.GOLD
			var f := UiStyle.font("impact")
			draw_string(f, Vector2(r.position.x, c.y + k * 0.62), "x2", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.x * 0.56), gold)
		PowerupRules.FIRE_SALE:  # étiquette de prix
			var red := Color(0.9, 0.12, 0.06)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-k, 0), c + Vector2(-0.45 * k, -0.6 * k), c + Vector2(k, -0.6 * k), c + Vector2(k, 0.6 * k), c + Vector2(-0.45 * k, 0.6 * k)]), red)
			draw_circle(c + Vector2(-0.55 * k, 0), k * 0.12, Color(0.95, 0.92, 0.85))
			draw_string(UiStyle.font("impact"), Vector2(c.x - 0.35 * k, c.y + 0.3 * k), "10", HORIZONTAL_ALIGNMENT_CENTER, 1.3 * k, int(k * 0.9), Color(1, 0.96, 0.88))
		_:
			draw_circle(c, k * 0.6, green)
