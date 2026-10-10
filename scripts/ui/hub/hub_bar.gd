class_name HubBar
extends Control
## Barre en cubes du hub (classe .bar de la maquette : 12 px de haut, ou 10
## pour .bar.thin) : piste sombre à contour noir et ombre, remplissage en
## segments. `ratio` 0..1, `color` du remplissage (jaune, vert quand c'est
## complet…).

var ratio := 0.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
var color := HubStyle.YELLOW:
	set(v):
		color = v
		queue_redraw()
var thin := false:
	set(v):
		thin = v
		_resize()
## Largeur minimale à 100 % (0 : s'étire).
var min_width := 0.0:
	set(v):
		min_width = v
		_resize()


static func make(r: float, c := HubStyle.YELLOW, is_thin := false, w := 0.0) -> HubBar:
	var b := HubBar.new()
	b.ratio = r
	b.color = c
	b.thin = is_thin
	b.min_width = w
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resize()


func _resize() -> void:
	custom_minimum_size = Vector2(HubStyle.px(min_width), HubStyle.px(10 if thin else 12))
	queue_redraw()


func _draw() -> void:
	HubStyle.draw_bar(self, Rect2(Vector2.ZERO, size), ratio, color)
