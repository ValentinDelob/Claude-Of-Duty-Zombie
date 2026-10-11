class_name Hub2Keycap
extends Control
## Touche du hub v2 (<kbd> de Prompts.dc.html) : pavé clair
## rgba(242, 240, 234, 0.92), 24 px de haut, 24 px de large au moins,
## padding 0 6 px, texte JetBrains Mono 11 px 700 #0B0B0C. Une seule touche
## peut porter plusieurs noms (« LB RB »). Manette PlayStation : les boutons
## de face sont dessinés en symboles (✕ ○ □ △), sans police.
##
## `label` : texte affiché ; `pad_button` >= 0 : bouton de face de la manette
## PlayStation à dessiner en symbole (sinon le texte).

const H := 24.0
const MIN_W := 24.0
const PAD_X := 6.0
const FONT_SIZE := 11.0

var label := "":
	set(v):
		label = v
		_changed()
## Bouton de face PlayStation dessiné en symbole (-1 : texte).
var ps_symbol := -1:
	set(v):
		ps_symbol = v
		_changed()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_changed()


## Largeur de la touche pour `t` (px à l'échelle).
static func width_for(t: String) -> float:
	var f := Hub2Style.font(Hub2Style.MONO, 700)
	var s := Hub2Style.fs(FONT_SIZE)
	var w := Hub2Style.text_width(t, f, s) + Hub2Style.px(PAD_X) * 2.0
	return maxf(ceilf(w), Hub2Style.px(MIN_W))


func _changed() -> void:
	var w := Hub2Style.px(MIN_W) if ps_symbol >= 0 else width_for(label)
	custom_minimum_size = Vector2(w, Hub2Style.px(H))
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(size.x, Hub2Style.px(H)))
	r.position.y = roundf((size.y - r.size.y) * 0.5)
	draw_keycap(self, r, label, ps_symbol)


## Dessine une touche dans `r` sur `ci` (aussi utilisé par Hub2Prompts, sans
## nœud par invite) : texte `t`, ou symbole PlayStation `sym` (>= 0).
static func draw_keycap(ci: CanvasItem, r: Rect2, t: String, sym := -1) -> void:
	ci.draw_rect(r, Hub2Style.KEYCAP_BG)
	if sym >= 0:
		_draw_symbol(ci, r, sym)
		return
	var f := Hub2Style.font(Hub2Style.MONO, 700)
	var s := Hub2Style.fs(FONT_SIZE)
	var tw := Hub2Style.text_width(t, f, s)
	Hub2Style.draw_text(ci, f, Vector2(r.position.x + roundf((r.size.x - tw) * 0.5),
			Hub2Style.baseline(f, s, r.position.y, r.size.y)), t, s, Hub2Style.INK)


static func _draw_symbol(ci: CanvasItem, r: Rect2, b: int) -> void:
	var c := r.get_center()
	var e := Hub2Style.px(5)
	var w := maxf(Hub2Style.px(1.6), 1.2)
	match b:
		JOY_BUTTON_A:
			ci.draw_line(c + Vector2(-e, -e), c + Vector2(e, e), Hub2Style.INK, w, true)
			ci.draw_line(c + Vector2(-e, e), c + Vector2(e, -e), Hub2Style.INK, w, true)
		JOY_BUTTON_B:
			ci.draw_arc(c, e, 0.0, TAU, 24, Hub2Style.INK, w, true)
		JOY_BUTTON_X:
			ci.draw_rect(Rect2(c - Vector2(e, e) * 0.9, Vector2(e, e) * 1.8), Hub2Style.INK, false, w)
		JOY_BUTTON_Y:
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -e), c + Vector2(e, e * 0.75),
					c + Vector2(-e, e * 0.75), c + Vector2(0, -e)]), Hub2Style.INK, w, true)
