class_name PerkIcons
extends Control
## Icônes des atouts du joueur local (dessinées, aucune image externe).

const SIZE := 42.0
const GAP := 8.0

var perks: PackedStringArray = []
var _pop := {}  # perk -> temps restant de l'animation d'apparition


func _ready() -> void:
	custom_minimum_size = Vector2((SIZE + GAP) * PerkDB.PERKS.size(), SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_perks(list: PackedStringArray) -> void:
	for p in list:
		if not p in perks:
			_pop[p] = 0.6
	perks = list.duplicate()
	queue_redraw()


func _process(delta: float) -> void:
	if _pop.is_empty():
		return
	for k in _pop.keys():
		_pop[k] -= delta
		if _pop[k] <= 0.0:
			_pop.erase(k)
	queue_redraw()


func _draw() -> void:
	for i in perks.size():
		var id: String = perks[i]
		var s := SIZE * (1.0 + 0.5 * maxf(_pop.get(id, 0.0), 0.0))
		var c := Vector2(i * (SIZE + GAP) + SIZE * 0.5, SIZE * 0.5)
		var col := PerkDB.color(id)
		var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_rect(r, col.darkened(0.55))
		draw_rect(r, col, false, 2.0)
		_symbol(id, c, s * 0.34, col.lightened(0.35))


func _symbol(id: String, c: Vector2, k: float, col: Color) -> void:
	match id:
		"titan":  # bouclier
			draw_colored_polygon(PackedVector2Array([c + Vector2(-k, -k), c + Vector2(k, -k), c + Vector2(k, 0.1 * k), c + Vector2(0, k * 1.1), c + Vector2(-k, 0.1 * k)]), col)
		"rapid":  # éclair
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.2 * k, -k * 1.1), c + Vector2(-0.7 * k, 0.15 * k), c + Vector2(-0.05 * k, 0.15 * k), c + Vector2(-0.3 * k, k * 1.1), c + Vector2(0.75 * k, -0.2 * k), c + Vector2(0.1 * k, -0.2 * k)]), col)
		"twin":  # deux balles
			for dx in [-0.45, 0.45]:
				var x: float = c.x + dx * k
				draw_rect(Rect2(Vector2(x - 0.25 * k, c.y - 0.3 * k), Vector2(0.5 * k, 1.2 * k)), col)
				draw_colored_polygon(PackedVector2Array([Vector2(x - 0.25 * k, c.y - 0.3 * k), Vector2(x + 0.25 * k, c.y - 0.3 * k), Vector2(x, c.y - k)]), col)
		"lazarus":  # croix
			draw_rect(Rect2(c + Vector2(-0.25 * k, -k), Vector2(0.5 * k, 2.0 * k)), col)
			draw_rect(Rect2(c + Vector2(-k, -0.25 * k), Vector2(2.0 * k, 0.5 * k)), col)
		"stride":  # chevrons
			for dx in [-0.5, 0.35]:
				var o: Vector2 = c + Vector2(dx * k, 0)
				draw_polyline(PackedVector2Array([o + Vector2(-0.35 * k, -0.8 * k), o + Vector2(0.35 * k, 0), o + Vector2(-0.35 * k, 0.8 * k)]), col, 4.0)
		"nova":  # flèche plongeante sur une étoile d'explosion
			var star := PackedVector2Array()
			for j in 16:
				var r := k * (1.0 if j % 2 == 0 else 0.5)
				var a := TAU * j / 16.0
				star.append(c + Vector2(cos(a), sin(a) * 0.55) * r + Vector2(0, 0.45 * k))
			draw_colored_polygon(star, col.darkened(0.25))
			draw_rect(Rect2(c + Vector2(-0.14 * k, -k), Vector2(0.28 * k, 0.9 * k)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.45 * k, -0.2 * k), c + Vector2(0.45 * k, -0.2 * k), c + Vector2(0, 0.35 * k)]), col)
		"deadeye":  # réticule sur une tête
			draw_arc(c, k * 0.72, 0.0, TAU, 20, col, 3.0)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * k * 0.35, c + d * k * 1.05, col, 3.0)
			draw_circle(c, k * 0.14, col)
		_:
			draw_circle(c, k * 0.6, col)
