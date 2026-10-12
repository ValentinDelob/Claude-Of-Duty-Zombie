class_name EvacDoorMarker
extends Control
## Repère de la porte d'évacuation (maquette docs/hub_v2/Evacuation.dc.html),
## affiché quand le joueur local a voté ÉVACUER pendant la fenêtre : étiquette
## « ÉVACUATION · N m » (distance du joueur à la porte, turquoise sur fond
## sombre, liseré turquoise) et flèche vers le bas, qui flottent doucement
## (5 px, 1,4 s) au-dessus de la porte. Projeté depuis la position de la
## porte (EvacDoor.marker_point) ; hors de l'écran ou derrière la caméra,
## il reste collé au bord, la flèche tournée vers la porte (place()).

## Flottement (@keyframes evBob : 0 -> -5 px -> 0, ease-in-out, 1,4 s).
const BOB_PX := 5.0
const BOB_PERIOD := 1.4
## Fond rgba(6, 22, 19, 0.85).
const LABEL_BG := Color(6 / 255.0, 22 / 255.0, 19 / 255.0, 0.85)
## Flèche (svg 18 × 12, path M1 1h16L9 11z) et écart avec l'étiquette.
const ARROW := Vector2(18, 12)
const GAP := 4.0
## Marge au bord de l'écran quand le repère y est collé.
const EDGE := 16.0

var game: Game
## Dernier placement (tests) : {pos, on_screen, dir} (place()).
var placed := {}
var _text := ""


func setup(g: Game) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Placement d'un repère dont le point projeté est `p` (`behind` : derrière la
## caméra) dans une vue de taille `view`, `half` : demi-taille du repère plus
## la marge. À l'écran : {pos = p, on_screen = true}. Sinon (ou derrière, la
## direction retournée) : collé au bord sur la droite centre -> point, `dir`
## direction (unitaire) vers la porte. Pure (tests).
static func place(p: Vector2, behind: bool, view: Vector2, half: Vector2) -> Dictionary:
	var c := view * 0.5
	var lim := (c - half).max(Vector2.ONE)
	var d := p - c
	if behind:
		d = -d
		if d.length() < 1.0:
			d = Vector2(0, 1)
	if not behind and absf(d.x) <= lim.x and absf(d.y) <= lim.y:
		return {"pos": p, "on_screen": true, "dir": Vector2.DOWN}
	var t := minf(lim.x / maxf(absf(d.x), 0.001), lim.y / maxf(absf(d.y), 0.001))
	return {"pos": c + d * t, "on_screen": false, "dir": d.normalized()}


## Flottement à `t` secondes (0 à -BOB_PX px, doux aux extrémités).
static func bob(t: float) -> float:
	return -BOB_PX * 0.5 * (1.0 - cos(TAU * fposmod(t, BOB_PERIOD) / BOB_PERIOD))


func _process(_delta: float) -> void:
	var door: EvacDoor = game.evac if game else null
	var p: Player = game.local_player if game else null
	var cam := get_viewport().get_camera_3d()
	var show := door != null and door.is_open and p != null and cam != null \
			and GameState.state != GameState.State.GAME_OVER and door.local_vote() == EvacRules.Vote.LEAVE
	if visible != show:
		visible = show
	if not show:
		return
	var dist := p.global_position.distance_to(door.global_position)
	_text = Lang.t("ÉVACUATION · %d m", "EVACUATION · %d m") % roundi(dist)
	var pt := door.marker_point()
	var box := _label_size()
	var half := Vector2(box.x * 0.5, box.y + Hub2Style.px(GAP) + Hub2Style.px(ARROW.y)) + Vector2.ONE * Hub2Style.px(EDGE)
	placed = place(cam.unproject_position(pt), cam.is_position_behind(pt), size, half)
	queue_redraw()


func _font() -> Font:
	return Hub2Style.font(Hub2Style.CHAKRA, 700)


## Étiquette : padding 4 px 10 px, liseré 1 px, Chakra Petch 13 / 700 / .14em.
func _label_size() -> Vector2:
	var s := Hub2Style.fs(13)
	var tw := Hub2Style.text_width(_text, _font(), s, Hub2Style.tracking_px(0.14, s))
	return Vector2(ceilf(tw) + Hub2Style.px(10) * 2.0 + Hub2Style.px(1) * 2.0,
			ceilf(Hub2Style.line_height(_font(), s)) + Hub2Style.px(4) * 2.0 + Hub2Style.px(1) * 2.0)


func _draw() -> void:
	if placed.is_empty():
		return
	var box := _label_size()
	var aw := Hub2Style.px(ARROW.x)
	var ah := Hub2Style.px(ARROW.y)
	var y_bob := roundf(Hub2Style.px(bob(Time.get_ticks_msec() / 1000.0)))
	var pos: Vector2 = placed.pos
	var label_pos: Vector2
	if placed.on_screen:
		# Pointe de la flèche (9, 11 du svg) sur la porte, étiquette au-dessus.
		var tip := pos + Vector2(0, y_bob)
		label_pos = Vector2(roundf(tip.x - box.x * 0.5), roundf(tip.y - Hub2Style.px(11) - Hub2Style.px(GAP) - box.y))
		var ax := label_pos.x + roundf((box.x - aw) * 0.5)
		var ay := label_pos.y + box.y + Hub2Style.px(GAP)
		_arrow(Vector2(ax, ay), aw, ah, Vector2.DOWN)
	else:
		# Collé au bord : étiquette centrée sur le point, flèche vers la porte.
		var dir: Vector2 = placed.dir
		var c := pos + Vector2(0, y_bob)
		label_pos = (c - box * 0.5).round()
		var reach := absf(dir.x) * box.x * 0.5 + absf(dir.y) * box.y * 0.5 + Hub2Style.px(GAP) + ah * 0.5
		var ac := c + dir * reach
		_arrow(ac - Vector2(aw, ah) * 0.5, aw, ah, dir)
	_draw_label(label_pos, box)


func _draw_label(at: Vector2, box: Vector2) -> void:
	var b := Hub2Style.px(1)
	draw_rect(Rect2(at + Vector2(b, b), box - Vector2(b, b) * 2.0), LABEL_BG)
	draw_rect(Rect2(at, Vector2(box.x, b)), Hub2Style.TEAL)
	draw_rect(Rect2(at + Vector2(0, box.y - b), Vector2(box.x, b)), Hub2Style.TEAL)
	draw_rect(Rect2(at + Vector2(0, b), Vector2(b, box.y - b * 2.0)), Hub2Style.TEAL)
	draw_rect(Rect2(at + Vector2(box.x - b, b), Vector2(b, box.y - b * 2.0)), Hub2Style.TEAL)
	var s := Hub2Style.fs(13)
	var f := _font()
	Hub2Style.draw_text(self, f, Vector2(at.x + b + Hub2Style.px(10), Hub2Style.baseline(f, s, at.y + b, box.y - b * 2.0)),
			_text, s, Hub2Style.TEAL, Hub2Style.tracking_px(0.14, s))


## Flèche du svg (M1 1 h16 L9 11 z dans 18 × 12) dans le carré `at` / `w` × `h`,
## pointée vers `dir` (bas : comme la maquette).
func _arrow(at: Vector2, w: float, h: float, dir: Vector2) -> void:
	var k := Vector2(w / ARROW.x, h / ARROW.y)
	var pts := PackedVector2Array([Vector2(1, 1) * k, Vector2(17, 1) * k, Vector2(9, 11) * k])
	var center := Vector2(w, h) * 0.5
	var rot := Vector2.DOWN.angle_to(dir)
	for i in pts.size():
		pts[i] = at + center + (pts[i] - center).rotated(rot)
	draw_colored_polygon(pts, Hub2Style.TEAL)
