class_name Hub2Text
extends Control
## Texte d'une ligne du hub v2 avec espacement des lettres exact
## (letter-spacing en em des maquettes, dessiné au sous-pixel : un Label ne
## sait qu'un espacement entier). Pour les libellés, titres, nombres ; un
## paragraphe qui revient à la ligne reste un Label (Hub2Style.label).
##
## Valeurs de la maquette (100 %) : `size` en px, `tracking` en em ;
## mises à l'échelle (TAILLE DES MENUS) au dessin. Taille minimale = texte
## (line-height: normal), donc utilisable dans les conteneurs.
##   var t := Hub2Text.new()
##   t.setup("ARSENAL", Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.08)

var text := "":
	set(v):
		text = v
		_changed()
var family := Hub2Style.BARLOW:
	set(v):
		family = v
		_changed()
var weight := 400:
	set(v):
		weight = v
		_changed()
## Taille de la maquette (px à 100 %).
var font_size := 16.0:
	set(v):
		font_size = v
		_changed()
var color := Hub2Style.TEXT:
	set(v):
		color = v
		queue_redraw()
## letter-spacing (em).
var tracking := 0.0:
	set(v):
		tracking = v
		_changed()
## Alignement horizontal dans la largeur du nœud.
var align := HORIZONTAL_ALIGNMENT_LEFT:
	set(v):
		align = v
		queue_redraw()
## Hauteur de ligne imposée (px de la maquette ; 0 : line-height normal).
## line-height: 1 des grands titres -> line_height = font_size.
var line_height := 0.0:
	set(v):
		line_height = v
		_changed()


## Réglage en une ligne (rend rien : chaînage inutile).
func setup(t: String, fam: String, w: int, sz: float, col: Color, track := 0.0) -> void:
	text = t
	family = fam
	weight = w
	font_size = sz
	color = col
	tracking = track


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_changed()


## Police, taille (à l'échelle) et espacement (px) utilisés au dessin.
func get_font() -> Font:
	return Hub2Style.font(family, weight)


func size_px() -> int:
	return Hub2Style.fs(font_size)


func tracking_px() -> float:
	return Hub2Style.tracking_px(tracking, size_px())


## Largeur du texte (espacement final compris, comme le CSS).
func text_width() -> float:
	return Hub2Style.text_width(text, get_font(), size_px(), tracking_px())


func _line_h() -> float:
	if line_height > 0.0:
		return Hub2Style.px(line_height)
	return Hub2Style.line_height(get_font(), size_px())


func _changed() -> void:
	custom_minimum_size = Vector2(ceilf(text_width()), ceilf(_line_h()))
	update_minimum_size()
	queue_redraw()


func _draw() -> void:
	if text == "":
		return
	var f := get_font()
	var s := size_px()
	var w := text_width()
	var x := 0.0
	match align:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = (size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = size.x - w
	# Ligne centrée verticalement dans le nœud (align-items: center) ; dans
	# la ligne, CSS centre la hauteur de la police (demi-interlignage).
	var lh := _line_h()
	var y := Hub2Style.baseline(f, s, roundf((size.y - lh) * 0.5), lh)
	Hub2Style.draw_text(self, f, Vector2(x, y), text, s, color, tracking_px())
