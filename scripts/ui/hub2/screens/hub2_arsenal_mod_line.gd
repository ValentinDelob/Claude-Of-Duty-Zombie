class_name Hub2ArsenalModLine
extends Control
## Ligne des effets d'une pièce (Barlow 13 px) : chaque effet dans sa
## couleur (bonus #4FE3C1, malus #FF6B57), séparés par « · », coupée avec
## « … » si la place manque. Une seule ligne (hauteur line-height: normal) ;
## `color_override` : toute la ligne d'une couleur (emplacement libre).

## [[texte, bonus ?], …]
var effects: Array = []:
	set(v):
		effects = v
		queue_redraw()
var size_css := 13.0
var color_override := Color(0, 0, 0, 0)
var plain := "":
	set(v):
		plain = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(0, roundf(Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, size_css)))


func _draw() -> void:
	var y := Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, size_css, 0.0, size.y)
	if plain != "":
		Hub2ArsenalDraw.text(self, plain, Hub2Style.BARLOW, 400, size_css, color_override, 0.0, 0.0, y, size.x)
		return
	draw_effects(self, effects, 0.0, y, size.x, size_css)


## Effets `eff` dessinés sur `ci` à partir de (x, ligne de base y) dans `w` px.
static func draw_effects(ci: CanvasItem, eff: Array, x: float, y: float, w: float, size_css: float) -> void:
	var f := Hub2Style.font(Hub2Style.BARLOW, 400)
	var s := Hub2Style.fs(size_css)
	var sep := " · "
	var cx := x
	var end := x + w
	for i in eff.size():
		var it: Array = eff[i]
		if i > 0:
			var sw := Hub2Style.text_width(sep, f, s)
			if cx + sw >= end:
				return
			Hub2Style.draw_text(ci, f, Vector2(roundf(cx), roundf(y)), sep, s, Hub2Style.text_a(0.45))
			cx += sw
		var t := String(it[0])
		var col: Color = Hub2ArsenalView.GOOD if it[1] else Hub2ArsenalView.HARMFUL
		var room := end - cx
		var tt := Hub2ArsenalDraw.ellipsize(t, f, s, 0.0, room)
		if room <= 0.0:
			return
		Hub2Style.draw_text(ci, f, Vector2(roundf(cx), roundf(y)), tt, s, col)
		cx += Hub2Style.text_width(tt, f, s)
		if tt != t:
			return
