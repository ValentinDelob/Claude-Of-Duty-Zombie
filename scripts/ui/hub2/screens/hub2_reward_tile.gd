class_name Hub2RewardTile
extends Control
## Tuile de récompense des contrats (docs/hub_v2/Contrats.dc.html) : 72 × 72,
## fond rgba(255, 255, 255, 0.05), liseré 2 px à la couleur de la rareté,
## lueur intérieure en bas (box-shadow: inset 0 -18px 24px -18px couleur),
## colonne centrée (écart 2) : rendu de l'arme (58 × 40, contain) ou grand
## texte (« XP » Chakra Petch 24 px, « PIÈCE » 15 px, à la couleur), puis la
## légende (JetBrains Mono 11 px 700). Survol ou focus (tabindex) : infobulle
## (Hub2RewardTooltip, posée par l'écran : signal `tip`).
##
## `spec` : fiche de Hub2LabKit (weapon_tile, part_tile, xp_tile) :
## {img (Texture2D ou null), big, color, cap, cap_color, alt, kind, name,
## stats [[libellé, valeur]], note}.

const SIZE := 72.0
const BORDER := 2.0
const IMG := Vector2(58, 40)
const GAP := 2.0
## Lueur intérieure : écart type du flou (24 px / 2), opacité au bord.
const GLOW_SIGMA := 12.0
const GLOW_STRIPS := 24

var spec: Dictionary = {}
## Infobulle alignée à droite de la tuile (contrats temporaires) ou à gauche
## (histoire).
var tip_right := false

var _kbd_focus := false

## Survol / focus : afficher (vrai) ou cacher l'infobulle.
signal tip(tile: Hub2RewardTile, on: bool)


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	texture_filter = HubRenders.FILTER
	custom_minimum_size = Hub2Style.pxv(SIZE, SIZE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_entered.connect(func(): tip.emit(self, true))
	mouse_exited.connect(func():
		if not has_focus():
			tip.emit(self, false))
	focus_entered.connect(func():
		_kbd_focus = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		queue_redraw()
		tip.emit(self, true))
	focus_exited.connect(func():
		queue_redraw()
		tip.emit(self, false))


func setup(s: Dictionary) -> void:
	spec = s
	tooltip_text = ""
	queue_redraw()


func color() -> Color:
	return spec.get("color", Hub2Style.TEXT)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := color()
	draw_rect(r, Hub2Style.white_a(0.05))
	var b := Hub2Style.px(BORDER)
	# Lueur intérieure du bas (dans le cadre, sous le liseré) :
	# 0,5 × erfc(d / (σ√2)) à `d` px du bord.
	var sigma := Hub2Style.px(GLOW_SIGMA)
	var h := minf(sigma * 3.0, size.y - 2.0 * b)
	var step := h / GLOW_STRIPS
	for i in GLOW_STRIPS:
		var d := (i + 0.5) * step
		var a := 0.5 * _erfc(d / (sigma * sqrt(2.0)))
		draw_rect(Rect2(b, size.y - b - (i + 1) * step, size.x - 2.0 * b, step), Color(col, col.a * a))
	draw_rect(Rect2(0, 0, size.x, b), col)
	draw_rect(Rect2(0, size.y - b, size.x, b), col)
	draw_rect(Rect2(0, b, b, size.y - 2.0 * b), col)
	draw_rect(Rect2(size.x - b, b, b, size.y - 2.0 * b), col)
	# Contenu centré : image ou grand texte, puis la légende.
	var cap := String(spec.get("cap", ""))
	var mono := Hub2Style.font(Hub2Style.MONO, 700)
	var cs := Hub2Style.fs(11)
	var cap_h := Hub2Style.line_height(mono, cs)
	var top_h := 0.0
	var tex: Texture2D = spec.get("img")
	var big := String(spec.get("big", ""))
	var big_font := Hub2Style.font(Hub2Style.CHAKRA, 700)
	var big_size := Hub2Style.fs(24.0 if big == "XP" else 15.0)
	if tex:
		top_h = Hub2Style.px(IMG.y)
	elif big != "":
		top_h = big_size  # line-height: 1
	var total := top_h + (Hub2Style.px(GAP) + cap_h if cap != "" else 0.0)
	var y := roundf((size.y - total) * 0.5)
	if tex:
		var box := Hub2Style.pxv(IMG.x, IMG.y)
		var ts := tex.get_size()
		var k := minf(box.x / maxf(ts.x, 1.0), box.y / maxf(ts.y, 1.0))
		var ds := ts * k
		draw_texture_rect(tex, Rect2(Vector2((size.x - ds.x) * 0.5, y + (box.y - ds.y) * 0.5), ds), false)
	elif big != "":
		var w := Hub2Style.text_width(big, big_font, big_size)
		Hub2Style.draw_text(self, big_font, Vector2((size.x - w) * 0.5, Hub2Style.baseline(big_font, big_size, y, top_h)),
				big, big_size, col)
	if cap != "":
		var cy := y + top_h + Hub2Style.px(GAP)
		var cw := Hub2Style.text_width(cap, mono, cs)
		Hub2Style.draw_text(self, mono, Vector2((size.x - cw) * 0.5, Hub2Style.baseline(mono, cs, cy, cap_h)), cap, cs,
				spec.get("cap_color", Hub2Style.TEXT))
	# Focus (manette, clavier) : cadre jaune 2 px autour de la tuile.
	if has_focus() and _kbd_focus:
		var g := Hub2Style.px(3)
		var fr := r.grow(g)
		var w2 := maxf(Hub2Style.px(2), 1.0)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, w2)), Hub2Style.YELLOW)
		draw_rect(Rect2(fr.position.x, fr.end.y - w2, fr.size.x, w2), Hub2Style.YELLOW)
		draw_rect(Rect2(fr.position.x, fr.position.y, w2, fr.size.y), Hub2Style.YELLOW)
		draw_rect(Rect2(fr.end.x - w2, fr.position.y, w2, fr.size.y), Hub2Style.YELLOW)


## Fonction d'erreur complémentaire (approximation d'Abramowitz et Stegun,
## erreur < 1,5e-7).
static func _erfc(x: float) -> float:
	var z := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * z)
	var y := t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
	var e := y * exp(-z * z)
	return e if x >= 0.0 else 2.0 - e
