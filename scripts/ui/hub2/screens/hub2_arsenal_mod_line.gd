class_name Hub2ArsenalModLine
extends Control
## Effets d'une pièce (Barlow 13 px) : chaque effet dans sa couleur (bonus
## #4FE3C1, malus #FF6B57), séparés par « · ». Jamais coupés : un effet qui
## ne tient plus sur la ligne passe à la suivante (la hauteur suit la
## largeur). `plain` + `color_override` : un texte d'une couleur (emplacement
## libre), qui passe aussi à la ligne aux espaces.

## [[texte, bonus ?], …]
var effects: Array = []:
	set(v):
		effects = v
		_relayout()
var size_css := 13.0
var color_override := Color(0, 0, 0, 0)
var plain := "":
	set(v):
		plain = v
		_relayout()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)


func _ready() -> void:
	_relayout()


func _lh() -> float:
	return Hub2ArsenalDraw.line_h(Hub2Style.BARLOW, 400, size_css)


## Lignes : [[[texte, couleur], …], …] pour la largeur `w`.
func lines_for(w: float) -> Array:
	var f := Hub2Style.font(Hub2Style.BARLOW, 400)
	var s := Hub2Style.fs(size_css)
	var items := []  # [texte, couleur]
	if plain != "":
		for wd in plain.split(" ", false):
			items.append([wd, color_override, " "])
	else:
		for i in effects.size():
			var it: Array = effects[i]
			items.append([String(it[0]), Hub2ArsenalView.GOOD if it[1] else Hub2ArsenalView.HARMFUL, " · "])
	var out := []
	var cur := []
	var cw := 0.0
	for it in items:
		var sep: String = it[2]
		var tw := Hub2Style.text_width(String(it[0]), f, s)
		var sw := Hub2Style.text_width(sep, f, s) if not cur.is_empty() else 0.0
		if not cur.is_empty() and w > 0.0 and cw + sw + tw > w:
			out.append(cur)
			cur = []
			cw = 0.0
			sw = 0.0
		if not cur.is_empty():
			cur.append([sep, Hub2Style.text_a(0.45) if plain == "" else color_override])
		cur.append([String(it[0]), it[1]])
		cw += sw + tw
	if not cur.is_empty():
		out.append(cur)
	return out


func _relayout() -> void:
	var n := maxi(lines_for(size.x).size(), 1) if size.x > 0.0 else 1
	var h := roundf(_lh() * n)
	if not is_equal_approx(custom_minimum_size.y, h):
		custom_minimum_size = Vector2(0, h)
	queue_redraw()


func _draw() -> void:
	var f := Hub2Style.font(Hub2Style.BARLOW, 400)
	var s := Hub2Style.fs(size_css)
	var lh := _lh()
	var y := 0.0
	for line: Array in lines_for(size.x):
		var x := 0.0
		var base := roundf(Hub2ArsenalDraw.baseline(Hub2Style.BARLOW, 400, size_css, y, lh))
		for seg: Array in line:
			x += Hub2Style.draw_text(self, f, Vector2(roundf(x), base), String(seg[0]), s, seg[1])
		y += lh
