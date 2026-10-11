class_name UiStyle
extends RefCounted
## Polices et couleurs de l'interface (menus, éditeur), propres au jeu :
## palette du « laboratoire en alerte » commune au HUD (HudStyle) et au hub
## (HubStyle) : blanc os, jaune des bandes de danger, menthe des moniteurs,
## orange et rouge des alarmes. Polices système (non redistribuées) avec
## repli : Bahnschrift (condensée), Impact, puis sans-serif ; les grands
## titres et le logo sont en police en cubes (CubeFont, MenuStyle.title).

const BONE := Color(0.86, 0.84, 0.76)
const DIM := Color(0.56, 0.55, 0.5)
## Valeurs mises en avant (niveau, statistiques) : laiton.
const GOLD := Color(0.95, 0.78, 0.35)
## Jaune des bandes de danger (sélection, jauges) : HubStyle.YELLOW.
const ACCENT := Color("E0B31F")
const ACCENT_HI := Color("F2CC45")
const ACCENT_LO := Color("A8840F")
## Menthe des moniteurs du laboratoire (intitulés de section) : HudStyle.ROUND.
const MINT := Color(0.45, 0.95, 0.78)
## Rouge-orange d'alarme (logo, avertissements) : HubStyle.RED_HI.
const ALERT := Color("E0341F")

static var _fonts: Dictionary = {}


## Police `kind` : « body » (texte courant), « impact » (boutons, noms),
## « title » (titres en police système : grasse et condensée), « mono »
## (valeurs, saisie). Plus de police pochoir dans le jeu.
static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f := SystemFont.new()
	match kind:
		"title", "impact":
			f.font_names = PackedStringArray(["Impact", "Bahnschrift", "Arial Black", "sans-serif"])
		"mono":
			f.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		_:
			f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_fonts[kind] = f
	return f


static func label(text: String, size: int, color := BONE, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
