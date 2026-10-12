class_name Hub2ArsenalStat
extends Control
## Statistique de la fiche de l'ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html,
## `sel.stats`) : carré d'icône de 30 px (fond rgba(255,255,255,.06), icône SVG
## 18 px #F2F0EA) puis, à 10 px, le libellé (Chakra Petch 10 px 600 0,14em,
## rgba(242,240,234,.5)) au-dessus de la valeur de BASE (JetBrains Mono 15 px
## 700) suivie à 6 px du modificateur des pièces (JetBrains Mono 13 px 700,
## #4FE3C1 bénéfique / #FF6B57 nuisible, sans unité). Bloc centré sur la
## hauteur du carré (align-items: center).

## {key, label, icon, value, mod, good}
var line: Dictionary = {}:
	set(v):
		line = v
		tooltip_text = String(v.get("label", ""))
		queue_redraw()


## Carré de l'icône, icône et valeur (px de la maquette ; station de
## construction, Station.dc.html : 28, 16, 14).
var square := 30.0
var icon_size := 18.0
var value_size := 15.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	custom_minimum_size = Vector2(0, maxf(Hub2Style.px(square), roundf(_text_h())))


func _text_h() -> float:
	return Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 600, 10) + _row_h()


func _row_h() -> float:
	return maxf(Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, value_size), Hub2ArsenalDraw.line_h(Hub2Style.MONO, 700, 13))


func _draw() -> void:
	var sq := Hub2Style.px(square)
	var top := roundf((size.y - sq) * 0.5)
	draw_rect(Rect2(0, top, sq, sq), Hub2Style.white_a(0.06))
	var ic := Hub2Style.px(icon_size)
	var tex := Hub2ArsenalDraw.svg_icon(String(line.get("icon", "")), ic, Hub2Style.TEXT)
	draw_texture_rect(tex, Rect2(roundf((sq - ic) * 0.5), top + roundf((sq - ic) * 0.5), ic, ic), false)
	var x := sq + Hub2Style.px(10)
	var w := size.x - x
	var lh := Hub2ArsenalDraw.line_h(Hub2Style.CHAKRA, 600, 10)
	var y := roundf((size.y - _text_h()) * 0.5)
	Hub2ArsenalDraw.text(self, String(line.get("label", "")), Hub2Style.CHAKRA, 600, 10, Hub2Style.text_a(0.5), 0.14, x,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 600, 10, y, lh), w)
	y += lh
	# Ligne de base commune (align-items: baseline) : celle de la valeur.
	var base := Hub2ArsenalDraw.baseline(Hub2Style.MONO, 700, value_size, y, _row_h())
	var vw := Hub2ArsenalDraw.text(self, String(line.get("value", "")), Hub2Style.MONO, 700, value_size, Hub2Style.TEXT, 0.0, x, base)
	var mod := String(line.get("mod", ""))
	if mod != "":
		var col: Color = Hub2ArsenalView.GOOD if line.get("good", true) else Hub2ArsenalView.HARMFUL
		Hub2ArsenalDraw.text(self, mod, Hub2Style.MONO, 700, 13, col, 0.0, x + vw + Hub2Style.px(6), base)
