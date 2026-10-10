class_name HubKey
extends Control
## Touche ou bouton de manette dessiné (classes .key et .pad de la maquette) :
## touche du clavier = pavé gris à contour noir et texte gras ; bouton de
## manette = carré de couleur (A vert, B rouge, X bleu, Y jaune ; LB, RB,
## START gris). Manette PlayStation : mêmes couleurs, symboles ✕ ○ □ △
## dessinés (pas de police nécessaire). Fonctions statiques réutilisées par
## la barre d'invites, la barre du haut et la barre des onglets.

const PAD_COLORS := {
	JOY_BUTTON_A: Color("6FBF4A"), JOY_BUTTON_B: Color("E0503A"),
	JOY_BUTTON_X: Color("4F8FE0"), JOY_BUTTON_Y: Color("E0B31F"),
}
const SHOULDER := Color("8C9196")
const KEY_BG := Color("2A2C2E")
const KEY_HI := Color("5C5957")
const PAD_TEXT := Color("0D0E0F")

## Texte de la touche (clavier) ; vide : bouton de manette `button`.
var key_text := "":
	set(v):
		key_text = v
		_resize()
var button := -1:
	set(v):
		button = v
		_resize()


static func make_key(t: String) -> HubKey:
	var k := HubKey.new()
	k.key_text = t
	return k


static func make_pad(b: int) -> HubKey:
	var k := HubKey.new()
	k.button = b
	return k


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func _resize() -> void:
	custom_minimum_size = Vector2(item_width(key_text, button), HubStyle.px(22) + HubStyle.px(2))
	queue_redraw()


func _draw() -> void:
	draw_item(self, Vector2.ZERO, key_text, button)


## Largeur d'une touche ou d'un bouton (sans l'ombre).
static func item_width(t: String, b: int) -> float:
	if t != "":
		var s := HubStyle.fs(12)
		var w := HubStyle.text_width(t, HubStyle.font("bold"), s) + HubStyle.px(5) * 2 + HubStyle.px(2) * 2
		return maxf(w, HubStyle.px(24))
	if PAD_COLORS.has(b):
		return HubStyle.px(22)
	var s2 := HubStyle.fs(12)
	return HubStyle.text_width(pad_text(b), HubStyle.font("bold"), s2) + HubStyle.px(5) * 2 + HubStyle.px(2) * 2


## Nom court d'un bouton gris (épaules, START) selon la manette courante.
static func pad_text(b: int) -> String:
	return PadNames.button_label(b, Settings.pad_style())


## Dessine la touche `t` (ou le bouton `b`) en haut à gauche `pos` ; rend sa
## largeur.
static func draw_item(ci: CanvasItem, pos: Vector2, t: String, b: int) -> float:
	var h := HubStyle.px(22)
	var w := item_width(t, b)
	var r := Rect2(pos, Vector2(w, h))
	var bd := HubStyle.px(2)
	var s := HubStyle.fs(12)
	var f := HubStyle.font("bold")
	if t != "":
		HubStyle.draw_box(ci, r, KEY_BG, bd, bd, KEY_HI, Color(0, 0, 0, 0), maxf(HubStyle.px(1), 1.0))
		var tw := HubStyle.text_width(t, f, s)
		ci.draw_string(f, Vector2(r.position.x + (w - tw) * 0.5, HubStyle.baseline(f, s, r.position.y, h)),
				t, HORIZONTAL_ALIGNMENT_LEFT, -1, s, HubStyle.PAPER)
		return w
	var col: Color = PAD_COLORS.get(b, SHOULDER)
	HubStyle.draw_box(ci, r, col, bd, bd)
	if PAD_COLORS.has(b) and PadNames.is_playstation(Settings.pad_style()):
		_draw_ps_symbol(ci, r.grow(-bd), b)
		return w
	var label: String = XBOX_LETTERS.get(b, "") if PAD_COLORS.has(b) else pad_text(b)
	var lw := HubStyle.text_width(label, f, s)
	ci.draw_string(f, Vector2(r.position.x + (w - lw) * 0.5, HubStyle.baseline(f, s, r.position.y, h)),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, s, PAD_TEXT)
	return w


const XBOX_LETTERS := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y"}


## Symbole PlayStation (Croix, Rond, Carré, Triangle) dans `r`.
static func _draw_ps_symbol(ci: CanvasItem, r: Rect2, b: int) -> void:
	var c := r.get_center()
	var e := r.size.x * 0.28
	var wdt := maxf(HubStyle.px(2), 1.5)
	match b:
		JOY_BUTTON_A:
			ci.draw_line(c + Vector2(-e, -e), c + Vector2(e, e), PAD_TEXT, wdt)
			ci.draw_line(c + Vector2(-e, e), c + Vector2(e, -e), PAD_TEXT, wdt)
		JOY_BUTTON_B:
			ci.draw_arc(c, e, 0.0, TAU, 16, PAD_TEXT, wdt)
		JOY_BUTTON_X:
			ci.draw_rect(Rect2(c - Vector2(e, e), Vector2(e, e) * 2.0), PAD_TEXT, false, wdt)
		JOY_BUTTON_Y:
			var pts := PackedVector2Array([c + Vector2(0, -e), c + Vector2(e, e * 0.8), c + Vector2(-e, e * 0.8), c + Vector2(0, -e)])
			ci.draw_polyline(pts, PAD_TEXT, wdt)
