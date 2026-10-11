class_name Hub2Style
extends RefCounted
## Style du hub v2 (maquettes validées docs/hub_v2/*.dc.html, 1280 × 720 ;
## architecture : docs/HUB_PLAN.md §9). Tous les jetons des maquettes :
## couleurs, polices (Chakra Petch, Barlow, JetBrains Mono, OFL, fournies
## dans assets/fonts/), espacement des lettres (letter-spacing en em), verre
## (fond rgba + flou + liseré 1 px), biseaux (clip-path), formats de nombres.
##
## RÈGLE : le code écrit les valeurs DE LA MAQUETTE (pixels logiques à 100 %)
## et les passe par px() / fs() ; TAILLE DES MENUS (Settings.menu_ui_scale,
## HUB_PLAN D15) multiplie tout, les polices sont rendues à leur taille finale
## (mode d'étirement canvas_items, suréchantillonnage du viewport), jamais
## une image agrandie. Le hub v2 se reconstruit quand le facteur change.
##
## Correspondance CSS -> Godot (à suivre par les écrans) :
##   color: #F2F0EA                         -> TEXT
##   color: rgba(242, 240, 234, 0.6)        -> text_a(0.6)
##   background: rgba(10, 11, 13, 0.62) + backdrop-filter: blur(12px)
##     + border: 1px solid rgba(255,255,255,0.08)  -> Hub2Box (glass)
##   clip-path: polygon(0 0, calc(100% - Npx) 0, 100% Npx, 100% 100%,
##     Npx 100%, 0 calc(100% - Npx))        -> Hub2Box.chamfer_tr = chamfer_bl = N
##   font-family 'Chakra Petch' 700, 16px, letter-spacing .08em, uppercase
##     -> Hub2Text (CHAKRA, 700, 16, tracking 0.08, texte en majuscules)
##   <kbd>                                  -> Hub2Keycap
##   @keyframes hubPulse (.hub-ring)        -> Hub2PulseRings

# --- Couleurs (maquettes) -----------------------------------------------------
## Texte principal #F2F0EA.
const TEXT := Color("F2F0EA")
## Accent jaune (focus, sélection, bouton JOUER, pastilles).
const YELLOW := Color("F5C542")
## Turquoise du labo et de l'histoire.
const TEAL := Color("4FE3C1")
## Mauvais / danger (malus, erreurs) : #FF7A5C, et la variante #FF6B57.
const BAD := Color("FF7A5C")
const BAD_ALT := Color("FF6B57")
## Encre sombre sur fond clair ou jaune (#0B0B0C).
const INK := Color("0B0B0C")
## Fond de page des maquettes (sous l'image du fond) : #101317 ; LABO : #0B0C0E.
const PAGE_BG := Color("101317")
## Bleu clair de l'XP (récapitulatif).
const XP_BLUE := Color("9FD0FF")
## Verre standard des panneaux : rgba(10, 11, 13, 0.62) ; plus opaque : 0.7.
const GLASS := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.62)
const GLASS_STRONG := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.7)
## Barre du haut : rgba(8, 9, 11, 0.72), flou 16 px.
const TOP_BAR_BG := Color(8 / 255.0, 9 / 255.0, 11 / 255.0, 0.72)
## Infobulles : rgba(8, 9, 11, 0.94).
const TOOLTIP_BG := Color(8 / 255.0, 9 / 255.0, 11 / 255.0, 0.94)
## Liseré standard des panneaux : rgba(255, 255, 255, 0.08).
const LINE := Color(1, 1, 1, 0.08)
## Fond jaune pâle des éléments jaunes (pavé du niveau, bouton CONTRATS).
const YELLOW_TINT := Color(245 / 255.0, 197 / 255.0, 66 / 255.0, 0.12)
## Fond de la touche (kbd) : rgba(242, 240, 234, 0.92).
const KEYCAP_BG := Color(242 / 255.0, 240 / 255.0, 234 / 255.0, 0.92)

## Rareté (OwnedWeapon.Rarity : commune, rare, épique, légendaire, unique).
const RARITY := [Color("C9C7BE"), Color("4D9BFF"), Color("B56CFF"), Color("FF9A1F"), Color("FF4D5E")]

## Flou des panneaux (backdrop-filter: blur(12px)) et de la barre du haut (16).
const BLUR := 12.0
const BLUR_TOP_BAR := 16.0

# --- Cadre (maquettes TopBar, Prompts, <main>) ---------------------------------
const SCREEN := Vector2(1280, 720)
const TOP_BAR_H := 72.0
const PROMPTS_H := 48.0
## Marges latérales de la barre du haut, des invites et de <main>.
const SIDE := 28.0
## <main> : haut des onglets (96), des sous-écrans avec fil d'Ariane (92), bas
## (60 au-dessus du bord).
const MAIN_TOP := 96.0
const MAIN_TOP_SUB := 92.0
const MAIN_BOTTOM := 60.0
## Fil d'Ariane -> contenu (gap: 14px).
const CRUMB_GAP := 14.0

# --- Polices ------------------------------------------------------------------
## Familles : titres et libellés, texte, nombres.
const CHAKRA := "chakra"
const BARLOW := "barlow"
const MONO := "mono"
const FONT_FILES := {
	"chakra:500": "res://assets/fonts/chakra_petch/ChakraPetch-Medium.ttf",
	"chakra:600": "res://assets/fonts/chakra_petch/ChakraPetch-SemiBold.ttf",
	"chakra:700": "res://assets/fonts/chakra_petch/ChakraPetch-Bold.ttf",
	"barlow:400": "res://assets/fonts/barlow/Barlow-Regular.ttf",
	"barlow:500": "res://assets/fonts/barlow/Barlow-Medium.ttf",
	"barlow:600": "res://assets/fonts/barlow/Barlow-SemiBold.ttf",
}
## JetBrains Mono : une seule police variable (axe wght), toute graisse.
const MONO_FILE := "res://assets/fonts/jetbrains_mono/JetBrainsMono-Variable.ttf"
## Graisses chargées par les maquettes (Google Fonts : Chakra Petch
## 500;600;700, Barlow 400;500;600, JetBrains Mono 500;700) ; une autre est
## ramenée à la plus proche, comme le navigateur : un nombre JetBrains Mono
## sans graisse (400) s'affiche donc en 500 dans la maquette, et ici aussi.
const WEIGHTS := {"chakra": [500, 600, 700], "barlow": [400, 500, 600], "mono": [500, 700]}

static var _fonts: Dictionary = {}


# --- Taille des menus ---------------------------------------------------------

## Facteur courant (Settings.menu_ui_scale ; 1 = la maquette).
static func factor() -> float:
	return Settings.menu_ui_scale


## Longueur de la maquette en pixels à la taille des menus (`f` < 0 :
## facteur courant). Arrondie au pixel : bords nets.
static func px(v: float, f := -1.0) -> float:
	return roundf(v * (factor() if f < 0.0 else f))


## Vecteur de la maquette à la taille des menus.
static func pxv(x: float, y: float, f := -1.0) -> Vector2:
	return Vector2(px(x, f), px(y, f))


## Taille de police de la maquette à la taille des menus (6 au moins).
static func fs(n: float, f := -1.0) -> int:
	return maxi(6, roundi(n * (factor() if f < 0.0 else f)))


## letter-spacing de la maquette (`em`) en pixels pour une police de `size`
## pixels (déjà à l'échelle) ; décimal (Hub2Text le dessine au sous-pixel).
static func tracking_px(em: float, size: int) -> float:
	return em * size


# --- Couleurs -----------------------------------------------------------------

## rgba(242, 240, 234, a) : texte secondaire.
static func text_a(a: float) -> Color:
	return Color(TEXT, a)


## rgba(255, 255, 255, a) : liserés et séparateurs.
static func white_a(a: float) -> Color:
	return Color(1, 1, 1, a)


## rgba(8, 9, 11, a) : voiles sombres (fond assombri, dégradés des invites).
static func shade(a: float) -> Color:
	return Color(8 / 255.0, 9 / 255.0, 11 / 255.0, a)


## Jaune ou turquoise translucide (rgba(245, 197, 66, a), rgba(79, 227, 193, a)).
static func yellow_a(a: float) -> Color:
	return Color(YELLOW, a)


static func teal_a(a: float) -> Color:
	return Color(TEAL, a)


## Couleur d'une rareté (OwnedWeapon.Rarity).
static func rarity_color(r: int) -> Color:
	return RARITY[clampi(r, 0, RARITY.size() - 1)]


# --- Polices ------------------------------------------------------------------

## Graisse fournie la plus proche de `weight` pour la famille.
static func nearest_weight(family: String, weight: int) -> int:
	var best := 0
	for w: int in WEIGHTS.get(family, WEIGHTS[BARLOW]):
		# À égalité (400 entre 300 et 500…), la plus grasse, comme CSS pour
		# une demande de 400 ou plus.
		if best == 0 or absi(w - weight) < absi(best - weight) or (absi(w - weight) == absi(best - weight) and w > best):
			best = w
	return best


## Police `family` (CHAKRA, BARLOW, MONO) de graisse `weight` (CSS). Sans
## espacement des lettres : Hub2Text et draw_text l'ajoutent au sous-pixel.
static func font(family: String, weight := 400) -> Font:
	return font_spaced(family, weight, 0)


## Police avec un espacement des lettres entier `spacing` (px, déjà à
## l'échelle) : pour un Label (FontVariation n'accepte que des entiers).
## Préférer Hub2Text pour un libellé en capitales espacées (sous-pixel).
static func font_spaced(family: String, weight: int, spacing: int) -> Font:
	var w := nearest_weight(family, weight)
	var key := "%s:%d:%d" % [family, w, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var out: Font
	if family == MONO:
		var fv := FontVariation.new()
		fv.base_font = load(MONO_FILE)
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
		fv.spacing_glyph = spacing
		out = fv
	else:
		var base: Font = load(FONT_FILES["%s:%d" % [family, w]])
		if spacing == 0:
			out = base
		else:
			var fv2 := FontVariation.new()
			fv2.base_font = base
			fv2.spacing_glyph = spacing
			out = fv2
	_fonts[key] = out
	return out


## Étiquette (Label) : `size` px de la maquette (mis à l'échelle ici),
## `tracking` = letter-spacing en em (arrondi au pixel entier : pour un
## libellé court en capitales, Hub2Text est exact). Le texte est pris tel quel
## (text-transform: uppercase -> le passer en majuscules soi-même).
static func label(text: String, family := BARLOW, weight := 400, size := 16.0, color := TEXT,
		tracking := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	var s := fs(size)
	l.add_theme_font_override("font", font_spaced(family, weight, roundi(tracking_px(tracking, s))))
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Hauteur d'une ligne (line-height: normal) d'une police à `size` px.
static func line_height(f: Font, size: int) -> float:
	return f.get_ascent(size) + f.get_descent(size)


## Ordonnée de la ligne de base d'un texte centré verticalement dans une
## hauteur `h` à partir de `y` (align-items: center).
static func baseline(f: Font, size: int, y: float, h: float) -> float:
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	return y + (h - (asc + desc)) * 0.5 + asc


## Largeur d'un texte avec `tracking` px ajoutés après chaque caractère
## (letter-spacing CSS : aussi après le dernier).
static func text_width(text: String, f: Font, size: int, tracking := 0.0) -> float:
	if text == "":
		return 0.0
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + tracking * text.length()


## Dessine `text` sur `ci` à la ligne de base `pos` avec `tracking` px
## d'espacement des lettres au sous-pixel près (crénage de la police gardé).
## Rend la largeur dessinée (espacement final compris, comme le CSS).
static func draw_text(ci: CanvasItem, f: Font, pos: Vector2, text: String, size: int, color: Color,
		tracking := 0.0) -> float:
	if text == "":
		return 0.0
	var vp := ci.get_viewport()
	var over := vp.get_oversampling() if vp else 1.0
	if absf(tracking) < 0.01:
		ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var ts := TextServerManager.get_primary_interface()
	var line := TextLine.new()
	line.add_string(text, f, size)
	var rid := line.get_rid()
	var glyphs: Array = ts.shaped_text_get_glyphs(rid)
	var x := 0.0
	var left := 0  # glyphes restants dans la grappe (caractère) en cours
	for g: Dictionary in glyphs:
		if left <= 0:
			left = maxi(int(g.count), 1)  # « count » : porté par le 1er glyphe
		var gp := pos + Vector2(x, 0) + (g.offset as Vector2)
		if (g.font_rid as RID).is_valid():
			ts.font_draw_glyph(g.font_rid, ci.get_canvas_item(), g.font_size, gp, g.index, color, over)
		x += float(g.advance)
		left -= 1
		if left == 0:
			x += tracking  # letter-spacing : après chaque caractère
	return x


# --- Nombres ------------------------------------------------------------------

## Nombre au format de la langue : « 8 420 » (espace insécable) en français,
## « 8,420 » en anglais.
static func num(n: int) -> String:
	var s := str(absi(n))
	var sep := String.chr(0xA0) if not Lang.is_en() else ","
	var out := ""
	while s.length() > 3:
		out = sep + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Courbes (animations CSS) -------------------------------------------------

## cubic-bezier(x1, y1, x2, y2) des transitions CSS au temps `t` (0..1).
static func cubic_bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0 or t >= 1.0:
		return t
	# x(s) = t résolu par Newton puis dichotomie.
	var s := t
	for i in 8:
		var xs := _bez(s, x1, x2) - t
		var d := _bez_d(s, x1, x2)
		if absf(xs) < 1e-5:
			return _bez(s, y1, y2)
		if absf(d) < 1e-6:
			break
		s -= xs / d
	var lo := 0.0
	var hi := 1.0
	s = t
	for i in 30:
		var xs2 := _bez(s, x1, x2)
		if absf(xs2 - t) < 1e-5:
			break
		if xs2 < t:
			lo = s
		else:
			hi = s
		s = (lo + hi) * 0.5
	return _bez(s, y1, y2)


## ease-out CSS : cubic-bezier(0, 0, 0.58, 1).
static func ease_out(t: float) -> float:
	return cubic_bezier(t, 0.0, 0.0, 0.58, 1.0)


static func _bez(s: float, p1: float, p2: float) -> float:
	var u := 1.0 - s
	return 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s


static func _bez_d(s: float, p1: float, p2: float) -> float:
	var u := 1.0 - s
	return 3.0 * u * u * p1 + 6.0 * u * s * (p2 - p1) + 3.0 * s * s * (1.0 - p2)


# --- Divers -------------------------------------------------------------------

## Barrière de flou : un verre placé APRÈS ce nœud floute aussi ce qui a été
## dessiné avant lui (copie de l'écran refaite). À n'utiliser que si un verre
## doit flouter un autre verre (coûte une copie de l'écran).
static func blur_barrier() -> BackBufferCopy:
	var b := BackBufferCopy.new()
	b.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	return b
