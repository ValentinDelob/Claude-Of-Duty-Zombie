class_name MenuStyle
extends RefCounted
## Style des menus : boutons « militaires » (texte seul, trait de sang et
## chevron au survol), lignes d'options, titres au pochoir, champs de saisie
## sobres. Tout est dessiné en code (aucune texture externe).

const BUTTON_SIZE := 30
const HOVER := Color(0.92, 0.2, 0.12)
const IDLE := Color(0.72, 0.69, 0.62)
const DISABLED := Color(0.35, 0.33, 0.3)
const FOCUS_TEXT := Color(1.0, 0.93, 0.86)
const DIM_TEXT := Color(0.45, 0.42, 0.38)
const GAUGE_ON := Color(0.62, 0.1, 0.07)

## Sons d'interface (noms des fichiers res://assets/audio/).
const SND_MOVE := "menu_move"
const SND_SELECT := "menu_select"
const SND_BACK := "menu_back"
const VOL_MOVE := -9.0
const VOL_SELECT := -4.0

static var _brush: ImageTexture
static var _title_mat: ShaderMaterial


static func title(text: String, size := 44) -> Label:
	var l := UiStyle.label(text, size, UiStyle.BLOOD, "title")
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	if _title_mat == null:
		_title_mat = ShaderMaterial.new()
		_title_mat.shader = preload("res://assets/shaders/menu_title.gdshader")
	l.material = _title_mat
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


## Petit intitulé de section (« AUDIO », « VIDÉO »...).
static func section(text: String) -> Label:
	var l := UiStyle.label(text, 16, Color(0.62, 0.16, 0.1), "impact")
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
	e.add_theme_color_override("font_placeholder_color", Color(0.4, 0.37, 0.33))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.03, 0.85)
	sb.border_color = Color(0.45, 0.08, 0.06)
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", sb)
	var sbf := sb.duplicate()
	sbf.border_color = HOVER
	sbf.bg_color = Color(0.09, 0.02, 0.02, 0.9)
	e.add_theme_stylebox_override("focus", sbf)
	e.focus_entered.connect(func(): Audio.play_ui(SND_MOVE, VOL_MOVE))
	return e


## Panneau sombre semi-transparent (encadrés du salon...).
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.02, 0.72)
	sb.border_color = Color(0.3, 0.06, 0.05, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Surbrillance d'un élément : trait de pinceau rouge sang (texture
## procédurale), barre vive à gauche. `f` : intensité 0..1.
static func draw_highlight(ci: CanvasItem, r: Rect2, f: float) -> void:
	ci.draw_texture_rect(brush_texture(), r, false, Color(1, 1, 1, f))
	ci.draw_rect(Rect2(r.position.x, r.position.y + 3, 3, r.size.y - 6), Color(HOVER, f))


## Trait de pinceau usé : bords déchiquetés, poils, s'efface vers la droite.
static func brush_texture() -> ImageTexture:
	if _brush:
		return _brush
	var w := 512
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 71
	n.frequency = 0.03
	var fine := FastNoiseLite.new()
	fine.seed = 13
	fine.frequency = 0.25
	for x in w:
		var u := float(x) / w
		# Bords haut et bas irréguliers.
		var top := 6.0 + (n.get_noise_2d(x, 0.0) * 0.5 + 0.5) * 12.0
		var bot := h - 6.0 - (n.get_noise_2d(x, 90.0) * 0.5 + 0.5) * 12.0
		var fade := pow(1.0 - u, 1.6)
		for y in h:
			var edge := clampf(minf(y - top, bot - y) / 4.0, 0.0, 1.0)
			var bristle := 0.65 + 0.35 * (fine.get_noise_2d(x * 0.08, y * 3.0) * 0.5 + 0.5)
			var holes := smoothstep(-0.55, -0.2, n.get_noise_2d(x * 2.0, y * 4.0 + 300.0) + u * 0.4)
			var a := edge * bristle * fade * lerpf(1.0, holes, u)
			var c := Color(0.45, 0.04, 0.03).lerp(Color(0.25, 0.02, 0.02), 1.0 - bristle)
			img.set_pixel(x, y, Color(c, clampf(a * 0.8, 0.0, 1.0)))
	_brush = ImageTexture.create_from_image(img)
	return _brush
