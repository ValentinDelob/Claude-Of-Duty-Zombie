class_name Hub2PulseRings
extends Control
## Anneaux jaunes pulsés (@keyframes hubPulse de Main.dc.html et
## Contrats.dc.html, .hub-ring) : trois cadres de 2 px #F5C542 de la taille de
## l'élément, qui grandissent depuis le centre de 1 à `scale_to` (Main :
## 1.12 × 1.35 ; Contrats : 1.1 × 1.5) en s'effaçant (opacité 0.9 -> 0),
## ease-out, 1,8 s, décalés de 0,6 s. Le liseré grandit avec le cadre
## (transform: scale du CSS).
##
## Usage : enfant de l'élément signalé, ancré plein cadre, dessiné derrière
## lui (`show_behind_parent`), comme les <span class="hub-ring"> placés avant
## le bouton :
##   var rings := Hub2PulseRings.new()
##   rings.scale_to = Vector2(1.12, 1.35)
##   bouton.add_child(rings)

const PERIOD := 1.8
const DELAY := 0.6
const COUNT := 3
const LINE := 2.0
const OPACITY := 0.9

var scale_to := Vector2(1.12, 1.35)
var color := Hub2Style.YELLOW
## Arrêt : rien n'est dessiné.
var running := true:
	set(v):
		running = v
		queue_redraw()

## Temps écoulé (s) ; départ en régime établi (les trois anneaux en route).
var t := PERIOD


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if running and is_visible_in_tree():
		t += delta
		queue_redraw()


## Échelle et opacité de l'anneau `i` au temps `time` (tests).
static func ring_state(i: int, time: float, to: Vector2) -> Array:
	var p := fposmod(time - DELAY * i, PERIOD) / PERIOD
	var e := Hub2Style.ease_out(p)
	return [Vector2.ONE.lerp(to, e), lerpf(OPACITY, 0.0, e)]


func _draw() -> void:
	if not running:
		return
	var c := size * 0.5
	var w := Hub2Style.px(LINE)
	for i in COUNT:
		var st := ring_state(i, t, scale_to)
		var sc: Vector2 = st[0]
		var a: float = st[1]
		if a <= 0.001:
			continue
		# Cadre de la taille de l'élément, liseré à l'intérieur (border-box),
		# mis à l'échelle autour du centre.
		draw_set_transform(c, 0.0, sc)
		var r := Rect2(-c, size)
		var col := Color(color, color.a * a)
		draw_rect(Rect2(r.position, Vector2(r.size.x, w)), col)
		draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), col)
		draw_rect(Rect2(r.position.x, r.position.y + w, w, r.size.y - 2.0 * w), col)
		draw_rect(Rect2(r.end.x - w, r.position.y + w, w, r.size.y - 2.0 * w), col)
	draw_set_transform(Vector2.ZERO)
