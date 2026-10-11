class_name MenuStyle
extends RefCounted
## Style des menus, propre au jeu et en harmonie avec le hub et le HUD
## (docs/ART_DIRECTION.md « Menus ») : grands titres en police en cubes
## (CubeFont), boutons en texte seul avec une barre de sélection en paliers
## (bloc jaune des bandes de danger, bande sombre, filet jaune qui s'éteint
## par marches, cube à la place du chevron), intitulés de section menthe
## (moniteurs du laboratoire), champs de saisie à bord droit. Tout est
## dessiné en code (aucune texture externe).

const BUTTON_SIZE := 30
## Sélection (barre, flèches, jauges actives) : jaune des bandes de danger.
const HOVER := UiStyle.ACCENT
const IDLE := Color(0.74, 0.73, 0.68)
const DISABLED := Color(0.36, 0.36, 0.34)
const FOCUS_TEXT := Color(1.0, 0.98, 0.92)
const DIM_TEXT := Color(0.46, 0.46, 0.43)
const GAUGE_ON := UiStyle.ACCENT_LO
## Fonds et bords sombres (bleu-noir des écrans éteints, gris métal du hub).
const FIELD_BG := Color(0.04, 0.045, 0.05, 0.86)
const FIELD_BORDER := Color("3D4042")
## Éclat bref d'une validation (texte, valeurs).
const FLASH := Color(1.0, 0.92, 0.6)
## Grands titres (CubeFont) : blanc os des titres du HUD.
const TITLE := Color(0.95, 0.97, 0.93)

## Sons d'interface (noms des fichiers res://assets/audio/).
const SND_MOVE := "menu_move"
const SND_SELECT := "menu_select"
const SND_BACK := "menu_back"
const VOL_MOVE := -9.0
const VOL_SELECT := -4.0


## Grand titre d'écran en police en cubes (ombre franche décalée, liseré
## noir cuit dans les glyphes : HudStyle.cube_label).
static func title(text: String, size := 44) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TITLE)
	HudStyle.cube_label(l, size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(label: String, cb: Callable, hint := "") -> Button:
	var b := MenuActionButton.new()
	b.label = label
	b.hint = hint
	b.pressed.connect(func():
		Audio.play_ui(SND_SELECT, VOL_SELECT)
		b.flash()
		cb.call())
	return b


## Petit intitulé de section (« AUDIO », « VIDÉO »...) : menthe des moniteurs.
static func section(text: String) -> Label:
	var l := UiStyle.label(text, 16, UiStyle.MINT.darkened(0.15), "impact")
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func line_edit(value: String, placeholder := "", max_len := 32) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(360, 44)
	e.add_theme_font_override("font", UiStyle.font("mono"))
	e.add_theme_font_size_override("font_size", 24)
	e.add_theme_color_override("font_color", UiStyle.BONE)
	e.add_theme_color_override("caret_color", HOVER)
	e.add_theme_color_override("font_placeholder_color", DIM_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = FIELD_BG
	sb.border_color = FIELD_BORDER
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", sb)
	var sbf := sb.duplicate()
	sbf.border_color = HOVER
	sbf.bg_color = Color(0.07, 0.065, 0.05, 0.92)
	e.add_theme_stylebox_override("focus", sbf)
	e.focus_entered.connect(func(): Audio.play_ui(SND_MOVE, VOL_MOVE))
	return e


## Panneau sombre semi-transparent, bord droit gris métal.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.04, 0.74)
	sb.border_color = FIELD_BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Surbrillance d'un élément (`f` : intensité 0..1) : bande sombre, bloc
## jaune à gauche, filet jaune en bas qui s'éteint par paliers de 16 px vers
## la droite (pas de dégradé lisse : des marches, comme les cubes).
static func draw_highlight(ci: CanvasItem, r: Rect2, f: float) -> void:
	if f <= 0.001:
		return
	ci.draw_rect(r, Color(0.02, 0.025, 0.03, 0.62 * f))
	ci.draw_rect(Rect2(r.position.x, r.position.y + 3, 5, r.size.y - 6), Color(HOVER, f))
	var step := 16.0
	var n := int(ceil((r.size.x - 8.0) / step))
	for i in n:
		var k := 1.0 - float(i) / maxf(n, 1)
		var a := snappedf(k, 0.25) * f
		if a <= 0.0:
			break
		var x := r.position.x + 8.0 + i * step
		ci.draw_rect(Rect2(x, r.end.y - 3, minf(step - 2.0, r.end.x - x), 2), Color(HOVER, a * 0.85))


## Petit cube en relief (à la place d'un chevron), centré sur `c`.
static func draw_marker(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	CubeFont.draw_cube(ci, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)).abs(), col)
