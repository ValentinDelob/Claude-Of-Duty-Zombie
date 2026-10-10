class_name HudStyle
extends RefCounted
## Style du HUD de jeu, propre au jeu (docs/ART_DIRECTION.md, « HUD ») :
## polices (système pour les textes, police en cubes CubeFont pour les grands
## titres et le compteur de manche), couleurs d'un laboratoire en alerte
## (menthe des écrans de contrôle, orange des alarmes, blanc os). Aucune image
## externe.

## Compteur de manche : menthe des moniteurs du laboratoire.
const ROUND := Color(0.45, 0.95, 0.78)
## Compteur pendant une vague spéciale : orange d'alarme.
const ALERT := Color(1.0, 0.5, 0.12)
## Cubes « chauffés à blanc » d'un compteur qui vient de changer, et grands titres.
const TITLE := Color(0.95, 0.97, 0.93)
## Ombre des grands titres en cubes (bleu-noir des écrans éteints).
const TITLE_SHADOW := Color(0.02, 0.06, 0.07, 0.85)
const TEXT := Color(0.93, 0.92, 0.87)
const TEXT_DIM := Color(0.7, 0.69, 0.64)
## Ferraille gagnée (cuivre) et dépensée.
const POINTS_GAIN := Color(0.98, 0.68, 0.36)
const POINTS_LOSS := Color(0.95, 0.24, 0.18)
## Couleurs des joueurs (ambre, cyan, rose, vert anis), puis extras.
const PLAYER_COLORS := [
	Color(1.0, 0.78, 0.28), Color(0.35, 0.85, 1.0), Color(1.0, 0.45, 0.72), Color(0.6, 0.95, 0.32),
	Color(0.9, 0.9, 0.86), Color(0.72, 0.55, 1.0), Color(1.0, 0.6, 0.4), Color(0.6, 0.62, 0.65),
]

static var _fonts: Dictionary = {}


static func player_color(slot: int) -> Color:
	return PLAYER_COLORS[posmod(slot, PLAYER_COLORS.size())]


## « condensed » : chiffres et noms (Bahnschrift étroite, sinon Arial Narrow,
## Impact) ; « title » : titres des panneaux (Bahnschrift) ; « cube » : grands
## titres en cubes (CubeFont) ; « text » : invites et sous-titres.
static func font(kind := "condensed") -> Font:
	if kind == "cube":
		return CubeFont.font()
	if _fonts.has(kind):
		return _fonts[kind]
	var f := SystemFont.new()
	match kind:
		"condensed":
			f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Impact", "sans-serif"])
			f.font_weight = 700
			f.font_stretch = 75
		"title":
			f.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "sans-serif"])
			f.font_weight = 700
			f.font_stretch = 87
		_:
			f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
			f.font_weight = 500
			f.font_stretch = 87
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	_fonts[kind] = f
	return f


## Étiquette du HUD : ombre portée douce et contour sombre (lisible sur le
## grain et les lumières vives). Police en cubes : liseré déjà cuit dans les
## glyphes (pas de contour), ombre franche décalée.
static func label(text: String, size: int, color := TEXT, kind := "condensed", outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "cube":
		cube_label(l, size)
		return l
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", outline)
	return l


## Réglages d'une étiquette en police en cubes (taille `size`) : filtrage
## avec mipmaps (la police est cuite en grand puis réduite), ombre décalée,
## pas de contour (le liseré noir est dans les glyphes).
static func cube_label(l: Label, size: int) -> void:
	l.add_theme_font_override("font", CubeFont.font())
	l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var off := maxi(2, roundi(size / 20.0))
	l.add_theme_color_override("font_shadow_color", TITLE_SHADOW)
	l.add_theme_constant_override("shadow_offset_x", off)
	l.add_theme_constant_override("shadow_offset_y", off)
	l.add_theme_constant_override("outline_size", 0)
