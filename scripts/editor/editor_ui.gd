class_name EditorUi
extends RefCounted
## TAILLE DE L'INTERFACE DE L'ÉDITEUR DE CARTES (Settings.editor_ui_scale :
## OPTIONS > JEU > INTERFACE, ou Ctrl + / Ctrl - / Ctrl 0 dans l'éditeur).
##
## Un seul facteur, appliqué à tout l'éditeur et à rien d'autre :
##   - le thème de l'éditeur (MapEditor.make_theme) est construit à la bonne
##     taille : polices, marges, bordures, plus les constantes, icônes et
##     styles du thème par défaut de Godot pour les contrôles utilisés
##     (base_theme) ;
##   - scale_tree / scale_control : taille minimale, tailles de police,
##     constantes (séparations, marges, contours) et styles propres
##     (StyleBoxFlat) de chaque contrôle de l'éditeur sont multipliés par le
##     facteur. Le code écrit donc toujours ses valeurs « à 100 % » ; la valeur
##     d'origine est gardée en métadonnée : un changement de taille en direct
##     repart toujours d'elle (jamais d'échelle cumulée), et une valeur remise
##     par le code après coup devient la nouvelle valeur d'origine ;
##   - le dessin par code (vue 2D : règles, cotes, longueurs, étiquettes ;
##     cases de la barre rapide ; lignes de la liste des objets) passe par
##     px() et fs().
## Contrôle exclu (taille déjà calculée avec px(), ou écran étranger à
## l'éditeur comme les options) : métadonnée SKIP, pour lui et son contenu.
##
## Pourquoi pas Window.content_scale_factor : il changerait aussi l'échelle du
## plan 2D (son zoom, en pixels par mètre, suivrait la taille de l'interface),
## de l'écran d'options ouvert par-dessus l'éditeur et de tout ce qui vit dans
## la fenêtre, en se cumulant avec le mode d'étirement canvas_items du jeu.
## Ici seul l'éditeur change, le plan garde son zoom, et les textes restent
## nets : les polices sont rendues à leur taille finale (canvas_items), jamais
## une image agrandie.

const SKIP := &"editor_ui_skip"
## Taille minimale fixée par le code (déjà à l'échelle), le reste est mis à
## l'échelle normalement (panneaux latéraux : MapEditor.side_width).
const KEEP_MIN := &"editor_ui_keep_min"
const MIN_FONT := 6
## Taille du texte courant de l'éditeur à 100 %.
const BODY_FONT := 14
const _MIN0 := &"_ui_min0"
const _MIN1 := &"_ui_min1"
const _ITEMS := &"_ui_items"
const _SB0 := &"_ui_sb0"
const FONT_ITEMS := ["font_size"]
const CONST_ITEMS := ["separation", "h_separation", "v_separation", "outline_size", "shadow_offset_x", "shadow_offset_y",
	"margin_left", "margin_top", "margin_right", "margin_bottom", "line_spacing"]
const STYLE_ITEMS := ["panel", "normal", "hover", "pressed", "disabled", "focus"]
## Types du thème par défaut repris (à l'échelle) dans le thème de l'éditeur.
const THEME_TYPES := ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "SpinBox",
	"ItemList", "PopupMenu", "PopupPanel", "TabContainer", "TabBar", "VScrollBar", "HScrollBar", "ScrollContainer",
	"Label", "BoxContainer", "HBoxContainer", "VBoxContainer", "GridContainer", "FlowContainer", "HFlowContainer",
	"VSeparator", "HSeparator", "Window", "AcceptDialog", "ConfirmationDialog", "TooltipLabel", "TooltipPanel",
	"ColorPickerButton", "PanelContainer", "Panel", "MarginContainer", "TextureRect"]
## Constantes qui ne sont pas des longueurs (jamais mises à l'échelle).
const NOT_PIXELS := ["minimum_character_width", "align_to_largest_stylebox", "center_grabber"]

static var _icon_cache: Dictionary = {}


## Facteur courant (réglage du joueur, borné par Settings).
static func factor() -> float:
	return Settings.editor_ui_scale


## Longueur en pixels à la taille de l'interface (`f` < 0 : facteur courant).
static func px(v: float, f := -1.0) -> float:
	return roundf(v * (factor() if f < 0.0 else f))


## Taille de police à la taille de l'interface (6 au moins).
static func fs(n: int, f := -1.0) -> int:
	return maxi(MIN_FONT, roundi(n * (factor() if f < 0.0 else f)))


static func _scale_int(v: int, f: float) -> int:
	# 0 et 1 (bordures fines, drapeaux) ne bougent pas.
	return v if absi(v) <= 1 else roundi(v * f)


## Contrôle exclu ou interne, ou dans un contrôle exclu ou interne (jusqu'à
## `root`).
static func skipped(n: Node, root: Node) -> bool:
	var p := n
	while p != null and p != root:
		if p.has_meta(SKIP) or is_internal(p):
			return true
		p = p.get_parent()
	return false


## Nœud interne d'un contrôle de Godot (liste d'un menu, champ d'un SpinBox,
## barres de défilement...) : jamais touché, le thème (à l'échelle) s'en
## charge. Les enfants internes sont rangés avant et après les enfants
## ordinaires.
static func is_internal(n: Node) -> bool:
	var p := n.get_parent()
	if p == null:
		return false
	var count := p.get_child_count(false)
	if count == 0:
		return true
	var first := p.get_child(0, false).get_index(true)
	var i := n.get_index(true)
	return i < first or i >= first + count


## Met à l'échelle `f` tous les contrôles ordinaires sous `n` (fenêtres
## comprises ; ni nœuds internes, ni SubViewport, ni nœuds 3D de l'aperçu).
static func scale_tree(n: Node, f: float) -> void:
	if n.has_meta(SKIP):
		return
	if n is Control:
		scale_control(n as Control, f)
	for c in n.get_children(false):
		if c is Control or c is Window:
			scale_tree(c, f)


## Met à l'échelle `f` un contrôle (depuis ses valeurs d'origine). Rien n'est
## réécrit quand la valeur ne change pas (un style modifié prévient tous les
## contrôles qui l'utilisent).
static func scale_control(c: Control, f: float) -> void:
	var cur := c.custom_minimum_size
	if not c.has_meta(KEEP_MIN) and (c.has_meta(_MIN0) or cur != Vector2.ZERO):
		var base: Vector2 = c.get_meta(_MIN0) if c.has_meta(_MIN0) and c.get_meta(_MIN1) == cur else cur
		var v := (base * f).round()
		c.set_meta(_MIN0, base)
		c.set_meta(_MIN1, v)
		if v != cur:
			c.custom_minimum_size = v
	var items: Dictionary = c.get_meta(_ITEMS, {})
	var touched := false
	for n in FONT_ITEMS:
		if c.has_theme_font_size_override(n):
			var key: String = "f:" + n
			var now := c.get_theme_font_size(n)
			var b: int = items[key][0] if items.has(key) and items[key][1] == now else now
			var v := maxi(MIN_FONT, roundi(b * f))
			items[key] = [b, v]
			touched = true
			if v != now:
				c.add_theme_font_size_override(n, v)
	for n in CONST_ITEMS:
		if c.has_theme_constant_override(n):
			var key: String = "c:" + n
			var now := c.get_theme_constant(n)
			var b: int = items[key][0] if items.has(key) and items[key][1] == now else now
			var v := _scale_int(b, f)
			items[key] = [b, v]
			touched = true
			if v != now:
				c.add_theme_constant_override(n, v)
	if touched:
		c.set_meta(_ITEMS, items)
	for n in STYLE_ITEMS:
		if c.has_theme_stylebox_override(n):
			scale_stylebox(c.get_theme_stylebox(n), f)


## Marges, bordures, arrondis et ombre d'un style, depuis ses valeurs d'origine.
static func scale_stylebox(sb: StyleBox, f: float) -> void:
	if sb == null:
		return
	if not sb.has_meta(_SB0):
		var b := {"cm": [], "bw": [], "cr": [], "em": [], "sh": 0}
		for side in 4:
			b.cm.append(sb.get_content_margin(side))
		if sb is StyleBoxFlat:
			var fl := sb as StyleBoxFlat
			for side in 4:
				b.bw.append(fl.get_border_width(side))
				b.em.append(fl.get_expand_margin(side))
			for corner in 4:
				b.cr.append(fl.get_corner_radius(corner))
			b.sh = fl.shadow_size
		sb.set_meta(_SB0, b)
	var base: Dictionary = sb.get_meta(_SB0)
	for side in 4:
		var m: float = base.cm[side]
		var v := roundf(m * f) if m >= 0.0 else m
		if sb.get_content_margin(side) != v:
			sb.set_content_margin(side, v)
	if sb is StyleBoxFlat:
		var fl := sb as StyleBoxFlat
		for side in 4:
			var bw := _scale_int(int(base.bw[side]), f)
			if fl.get_border_width(side) != bw:
				fl.set_border_width(side, bw)
			var em := roundf(float(base.em[side]) * f)
			if fl.get_expand_margin(side) != em:
				fl.set_expand_margin(side, em)
		for corner in 4:
			var cr := _scale_int(int(base.cr[corner]), f)
			if fl.get_corner_radius(corner) != cr:
				fl.set_corner_radius(corner, cr)
		var sh := _scale_int(int(base.sh), f)
		if fl.shadow_size != sh:
			fl.shadow_size = sh


## Icône du thème par défaut à l'échelle `f` (image redimensionnée une fois,
## gardée en cache ; telle quelle si l'image n'est pas lisible, sans rendu).
static func scaled_icon(tex: Texture2D, f: float) -> Texture2D:
	if tex == null or is_equal_approx(f, 1.0):
		return tex
	var key := "%d:%.2f" % [tex.get_instance_id(), f]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var out := tex
	var img := tex.get_image()
	if img != null and not img.is_empty():
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.resize(maxi(1, roundi(img.get_width() * f)), maxi(1, roundi(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(img)
	_icon_cache[key] = out
	return out


## Thème de base de l'éditeur : les éléments du thème par défaut de Godot
## (constantes, icônes, styles, polices) des contrôles utilisés, à l'échelle.
static func base_theme(f: float) -> Theme:
	var d := ThemeDB.get_default_theme()
	var t := Theme.new()
	var dfs := maxi(1, d.default_font_size)
	for type in THEME_TYPES:
		for n in d.get_constant_list(type):
			var v := d.get_constant(n, type)
			t.set_constant(n, type, v if n in NOT_PIXELS else _scale_int(v, f))
		for n in d.get_icon_list(type):
			t.set_icon(n, type, scaled_icon(d.get_icon(n, type), f))
		for n in d.get_stylebox_list(type):
			var sb: StyleBox = d.get_stylebox(n, type).duplicate()
			scale_stylebox(sb, f)
			t.set_stylebox(n, type, sb)
		for n in d.get_font_size_list(type):
			var v := d.get_font_size(n, type)
			if v > 0:
				t.set_font_size(n, type, fs(roundi(float(v) * BODY_FONT / dfs), f))
	return t
