class_name HubStyle
extends RefCounted
## Style du hub (docs/HUB_PLAN.md §4.4, maquette docs/hub_mockup/index.html) :
## palette du décor (DECOR_PALETTE), panneaux à bords droits et contour noir de
## 2 px, ombres pleines décalées (sans flou), barres en cubes, polices des
## menus (UiStyle : Bahnschrift, Impact, Stencil, Consolas).
##
## TAILLE DES MENUS (Settings.menu_ui_scale, D15) : même technique que
## l'éditeur de cartes (EditorUi) — le code écrit toujours ses valeurs « à
## 100 % » (celles de la maquette, en pixels logiques 1280 × 720) et les passe
## par px() / fs() ; les polices sont rendues à leur taille finale (mode
## d'étirement canvas_items), jamais une image agrandie. Le hub se reconstruit
## quand le facteur change (HubScreen.rebuild).

# --- Palette (maquette : variables CSS de :root) -----------------------------
const BLACK := Color("000000")
const CASE := Color("212124")
const METAL := Color("3D4042")
const GREY := Color("474C4F")
const ASH := Color("5C5957")
const STEEL := Color("8C9196")
const PAPER := Color("DBD6C2")
const PLASTER := Color("CCCCC2")
const DIM := Color("8E8A7E")
const DIM2 := Color("66635B")
const YELLOW := Color("E0B31F")
const YELLOW_HI := Color("F2CC45")
const YELLOW_LO := Color("A8840F")
const RED := Color("B81A1A")
const RED_HI := Color("E0341F")
const GREEN := Color("8FAD9E")
const ENAMEL := Color("457366")
const RUST := Color("734024")
const BRASS := Color("A88038")
const OK := Color("86C96F")
const BAD := Color("E0503A")
const XP_BLUE := Color("9FD0FF")
## Texte sombre sur fond jaune.
const INK := Color("1A1405")

# --- Cadre -------------------------------------------------------------------
const FRAME_BG := Color("15171A")
const BAR_BG := Color("0D0E0F")
const BAR_EDGE := Color("2A2C2E")
const PANEL_BG := Color(29 / 255.0, 30 / 255.0, 32 / 255.0, 0.95)
const PANEL_HI := Color("3D4042")
const PANEL_LO := Color("111213")
const HEADER_BG := Color("2A2C2E")
const HEADER_RED_BG := Color("3A1512")
const HEADER_RED_TEXT := Color("F0C8C0")
const GROUP_BG := Color("17181A")
const ROW_BG := Color("232427")
const ROW_BG_ALT := Color("26282B")
const ROW_SEL := Color("3B3420")
const TRACK := Color("0F1011")
const STRIPE_GAP := Color(0, 0, 0, 0.55)

## Couleurs de rareté : celles du jeu (GameWeapon.RARITY_COLORS).
static func rarity_color(r: int) -> Color:
	return GameWeapon.rarity_color(r)


# --- Taille des menus --------------------------------------------------------

## Facteur courant (Settings.menu_ui_scale ; 1 = la maquette).
static func factor() -> float:
	return Settings.menu_ui_scale


## Longueur en pixels à la taille des menus (`f` < 0 : facteur courant).
static func px(v: float, f := -1.0) -> float:
	return roundf(v * (factor() if f < 0.0 else f))


## Taille de police à la taille des menus (8 au moins).
static func fs(n: int, f := -1.0) -> int:
	return maxi(8, roundi(n * (factor() if f < 0.0 else f)))


## Vecteur à la taille des menus.
static func pxv(x: float, y: float) -> Vector2:
	return Vector2(px(x), px(y))


# --- Polices -----------------------------------------------------------------

static var _fonts: Dictionary = {}


## Police `kind` (« ui », « bold », « semi », « impact », « stencil », « mono »)
## avec un espacement des lettres de `spacing` px (letter-spacing de la
## maquette, déjà à la taille finale).
static func font(kind := "ui", spacing := 0) -> Font:
	var key := "%s:%d" % [kind, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font
	match kind:
		"impact", "stencil", "mono":
			base = UiStyle.font(kind)
		"bold", "semi":
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
			sf.font_weight = 700 if kind == "bold" else 600
			sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			base = sf
		_:
			base = UiStyle.font("body")
	var out := base
	if spacing != 0:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.spacing_glyph = spacing
		out = fv
	_fonts[key] = out
	return out


## Espacement des lettres « em » de la maquette (letter-spacing: .05em) pour
## une police de `size` px (déjà à l'échelle).
static func em(ratio: float, size: int) -> int:
	return roundi(ratio * size)


## Étiquette de texte (taille `size` à 100 %, mise à l'échelle ici).
## `shadow` : ombre noire pleine de 2 px (classe .t de la maquette).
static func label(text: String, size: int, color := PAPER, kind := "ui", shadow := false, spacing_em := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	var s := fs(size)
	l.add_theme_font_override("font", font(kind, em(spacing_em, s)))
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", BLACK)
		l.add_theme_constant_override("shadow_offset_x", int(px(2)))
		l.add_theme_constant_override("shadow_offset_y", int(px(2)))
		l.add_theme_constant_override("shadow_outline_size", 0)
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Largeur d'un texte dessiné.
static func text_width(text: String, f: Font, size: int) -> float:
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Ordonnée de la ligne de base pour centrer verticalement un texte de
## taille `size` dans une hauteur `h` à partir de `y`.
static func baseline(f: Font, size: int, y: float, h: float) -> float:
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	return y + (h - (asc + desc)) * 0.5 + asc


# --- Nombres -----------------------------------------------------------------

## Nombre au format de la langue : « 2 140 » (espace insécable) en
## français, « 2,140 » en anglais (HUB_PLAN §4.3).
static func num(n: int) -> String:
	var s := str(absi(n))
	# Espace insécable (l'espace fine U+202F manque aux polices des menus).
	var nbsp := String.chr(0xA0)
	var sep := nbsp if not Lang.is_en() else ","
	var out := ""
	while s.length() > 3:
		out = sep + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Dessin ------------------------------------------------------------------

## Boîte de la maquette : ombre pleine décalée `shadow` (px), fond, contour
## noir de `border` px, biseau intérieur (`hi` en haut à gauche, `lo` en bas à
## droite, `bevel` px). Tout est déjà à l'échelle.
static func draw_box(ci: CanvasItem, r: Rect2, bg: Color, border := 2.0, shadow := 4.0,
		hi := Color(0, 0, 0, 0), lo := Color(0, 0, 0, 0), bevel := 2.0) -> void:
	if shadow > 0.0:
		ci.draw_rect(Rect2(r.position + Vector2(shadow, shadow), r.size), BLACK)
	ci.draw_rect(r, BLACK)
	var inner := r.grow(-border)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	ci.draw_rect(inner, bg)
	if hi.a > 0.0:
		ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, bevel)), hi)
		ci.draw_rect(Rect2(inner.position, Vector2(bevel, inner.size.y)), hi)
	if lo.a > 0.0:
		ci.draw_rect(Rect2(inner.position.x, inner.end.y - bevel, inner.size.x, bevel), lo)
		ci.draw_rect(Rect2(inner.end.x - bevel, inner.position.y, bevel, inner.size.y), lo)


## Barre en cubes (classe .bar) : piste sombre, contour noir, remplissage en
## segments de 8 px séparés de 2 px. `ratio` 0..1.
static func draw_bar(ci: CanvasItem, r: Rect2, ratio: float, col := YELLOW, shadow := true) -> void:
	var b := px(2)
	if shadow:
		ci.draw_rect(Rect2(r.position + Vector2(b, b), r.size), BLACK)
	ci.draw_rect(r, BLACK)
	var inner := r.grow(-b)
	ci.draw_rect(inner, TRACK)
	var w := floorf(inner.size.x * clampf(ratio, 0.0, 1.0))
	if w <= 0.0:
		return
	var seg := maxf(px(8), 2.0)
	var gap := maxf(px(2), 1.0)
	var x := 0.0
	while x < w:
		var sw := minf(seg, w - x)
		ci.draw_rect(Rect2(inner.position.x + x, inner.position.y, sw, inner.size.y), col)
		x += seg
		if x < w:
			var gw := minf(gap, w - x)
			ci.draw_rect(Rect2(inner.position.x + x, inner.position.y, gw, inner.size.y), col.lerp(BLACK, 0.55))
			x += gap


## Contour de focus (classe .focus : 3 px jaunes, 2 px autour de la boîte).
static func draw_focus(ci: CanvasItem, r: Rect2) -> void:
	var o := px(2)
	var t := maxf(px(3), 2.0)
	var fr := r.grow(o + t)
	ci.draw_rect(Rect2(fr.position, Vector2(fr.size.x, t)), YELLOW)
	ci.draw_rect(Rect2(fr.position.x, fr.end.y - t, fr.size.x, t), YELLOW)
	ci.draw_rect(Rect2(fr.position, Vector2(t, fr.size.y)), YELLOW)
	ci.draw_rect(Rect2(fr.end.x - t, fr.position.y, t, fr.size.y), YELLOW)


## Texte avec ombre noire pleine de 2 px (classe .t).
static func draw_text(ci: CanvasItem, f: Font, pos: Vector2, text: String, size: int, col: Color,
		shadow := false, max_w := -1.0) -> void:
	if shadow:
		ci.draw_string(f, pos + Vector2(px(2), px(2)), text, HORIZONTAL_ALIGNMENT_LEFT, max_w, size, BLACK,
				TextServer.JUSTIFICATION_NONE)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, max_w, size, col, TextServer.JUSTIFICATION_NONE)
