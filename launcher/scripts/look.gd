extends RefCounted
## Identité visuelle du lanceur (maquettes validées le 30/09/2026) : bunker des
## années 60, caisses au pochoir, dossier classé, lampes d'alerte. Thème Godot
## réutilisable (Look.theme()), palette, tailles et styles nommés : le menu
## principal du jeu pourra reprendre les mêmes. Aucun logo pour l'instant :
## le nom seul, au pochoir ; aucun effet par-dessus l'interface.
##
## Tailles : celles des maquettes telles qu'on les voit sur un écran 1920 × 1080
## (cadre de ≈ 1190 px de large). Sur un autre écran, tout est multiplié par
## screen_factor() (4K : × 2) : même rendu quelle que soit la résolution.
## Jamais étirée avec la fenêtre (agrandie : plus de place, pas de textes plus
## gros).

## Palette.
const INK := Color("0e100c")        # nuit du bunker (fond)
const CONCRETE := Color("1a1d17")   # béton : panneaux
const STEEL := Color("2a2f26")      # tôle : bords
const PAPER := Color("e6d9ba")      # papier du dossier : texte principal
const DIM := Color("9c9580")        # texte secondaire
const ALARM := Color("d2381f")      # lampe d'alerte : action principale, erreur
const NEON := Color("57e3cf")       # lueur : en cours, canal snapshot
const BRASS := Color("c49a4a")      # laiton : stable, installé

## Tailles de texte (px, base 1280 × 720).
const SIZE_BODY := 16        # texte courant, notes, liste, état
const SIZE_SMALL := 13       # dates, étiquettes, boutons discrets
const SIZE_SWITCH := 15      # interrupteur de canal
const SIZE_TITLE := 36       # titre des notes
const SIZE_NAME_TOP := 18    # « CLAUDE OF DUTY »
const SIZE_NAME := 49        # « ZOMBIE »
const SIZE_PLAY := 37        # JOUER
const SIZE_FIELD := 16       # titre d'un bloc des réglages
const SIZE_HELP := 13        # aide d'un bloc des réglages
## Bandeaux et marges (px).
const HEAD_H := 128
const FOOT_H := 100
const LIST_W := 305
const GUTTER := 35           # marge gauche / droite de l'en-tête, des notes, du pied
const BORDER := 2
## Fenêtre au démarrage et taille minimale, en pixels des maquettes.
const WINDOW := Vector2i(1190, 690)
const WINDOW_MIN := Vector2i(900, 560)
## Écran de référence des maquettes.
const REF_SCREEN := Vector2(1920, 1080)


## Échelle de l'interface pour un écran de cette taille (pixels physiques) :
## celle qui garde la même part de l'écran qu'en 1920 × 1080 (4K : 2 ;
## 2560 × 1440 : 1,33). Ne dépend pas du réglage d'échelle de Windows ;
## bornée (écran inconnu ou minuscule).
static func screen_factor(screen: Vector2i) -> float:
	if screen.x <= 0 or screen.y <= 0:
		return 1.0
	var f := minf(screen.x / REF_SCREEN.x, screen.y / REF_SCREEN.y)
	return clampf(snappedf(f, 0.05), 0.6, 4.0)

## Polices du système les plus proches des maquettes (pochoir condensé,
## étiquettes condensées, machine à écrire) ; repli si absentes.
static func display_font() -> SystemFont:
	return _font(["Impact", "Bahnschrift Condensed", "Arial Narrow", "sans-serif"], 700)


static func body_font() -> SystemFont:
	return _font(["Bahnschrift Condensed", "Bahnschrift SemiCondensed", "Arial Narrow", "Segoe UI", "sans-serif"], 400)


static func label_font() -> SystemFont:
	return _font(["Bahnschrift SemiBold Condensed", "Bahnschrift Condensed", "Arial Narrow", "sans-serif"], 600)


static func file_font() -> SystemFont:
	return _font(["Courier New", "Consolas", "monospace"], 400)


static func _font(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


## Police espacée (étiquettes en capitales, comme les maquettes).
static func spaced(f: Font, px: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = f
	v.spacing_glyph = px
	return v


## Boîte pleine, bord facultatif, marges intérieures (horizontale, verticale).
static func box(bg: Color, pad_h := 0, pad_v := -1, border := Color(0, 0, 0, 0), width := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.content_margin_left = pad_h
	b.content_margin_right = pad_h
	b.content_margin_top = pad_h if pad_v < 0 else pad_v
	b.content_margin_bottom = pad_h if pad_v < 0 else pad_v
	if width > 0:
		b.border_color = border
		b.set_border_width_all(width)
	return b


## Thème commun : textes, listes, boutons, menus déroulants.
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = SIZE_BODY
	th.set_color("font_color", "Label", PAPER)
	th.set_color("default_color", "RichTextLabel", PAPER)
	# Liste des versions : ligne choisie teintée d'alerte, filet à gauche.
	th.set_color("font_color", "ItemList", PAPER)
	th.set_color("font_selected_color", "ItemList", PAPER)
	th.set_color("font_hovered_color", "ItemList", PAPER)
	var sel := box(Color(ALARM, 0.14), 12, 9)
	sel.border_color = ALARM
	sel.border_width_left = 4
	th.set_stylebox("selected", "ItemList", sel)
	th.set_stylebox("selected_focus", "ItemList", sel)
	th.set_stylebox("hovered", "ItemList", box(Color(PAPER, 0.05), 12, 9))
	th.set_stylebox("panel", "ItemList", box(Color(0, 0, 0, 0), 0))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_constant("v_separation", "ItemList", 18)
	th.set_constant("h_separation", "ItemList", 12)
	th.set_font_size("font_size", "ItemList", SIZE_BODY)
	# Boutons discrets (étiquettes à bord de tôle) et menus déroulants.
	var chip := spaced(label_font(), 2)
	for t in ["Button", "OptionButton"]:
		th.set_font("font", t, chip)
		th.set_font_size("font_size", t, SIZE_SMALL)
		th.set_color("font_color", t, DIM)
		th.set_color("font_hover_color", t, PAPER)
		th.set_color("font_pressed_color", t, INK)
		th.set_color("font_hover_pressed_color", t, INK)
		th.set_color("font_focus_color", t, PAPER)
		th.set_color("font_disabled_color", t, Color(DIM, 0.5))
		th.set_stylebox("normal", t, box(Color(0, 0, 0, 0), 12, 9, STEEL, BORDER))
		th.set_stylebox("hover", t, box(Color(PAPER, 0.06), 12, 9, STEEL, BORDER))
		th.set_stylebox("pressed", t, box(PAPER, 12, 9, PAPER, BORDER))
		th.set_stylebox("hover_pressed", t, box(PAPER, 12, 9, PAPER, BORDER))
		th.set_stylebox("disabled", t, box(Color(0, 0, 0, 0), 12, 9, Color(STEEL, 0.5), BORDER))
		th.set_stylebox("focus", t, box(Color(0, 0, 0, 0), 12, 9, NEON, BORDER))
	# Menus déroulants ouverts et défilement discret.
	th.set_stylebox("panel", "PopupMenu", box(CONCRETE, 8, 6, STEEL, BORDER))
	th.set_color("font_color", "PopupMenu", PAPER)
	th.set_font_size("font_size", "PopupMenu", SIZE_SMALL)
	th.set_stylebox("grabber", "VScrollBar", box(STEEL))
	th.set_stylebox("grabber_highlight", "VScrollBar", box(DIM))
	th.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0)))
	return th


## JOUER : fond d'alerte, bord clair, lueur.
static func play_button(b: Button) -> void:
	b.add_theme_font_override("font", spaced(display_font(), 3))
	b.add_theme_font_size_override("font_size", SIZE_PLAY)
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_pressed_color", PAPER)
	b.add_theme_color_override("font_disabled_color", DIM)
	var edge := Color("f06a4f")
	var n := box(ALARM, 40, 11, edge, 3)
	n.shadow_color = Color(ALARM, 0.4)
	n.shadow_size = 12
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", box(ALARM.lightened(0.1), 40, 11, edge, 3))
	b.add_theme_stylebox_override("pressed", box(ALARM.darkened(0.2), 40, 11, edge, 3))
	b.add_theme_stylebox_override("disabled", box(STEEL, 40, 11, STEEL, 3))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 40, 11, NEON, 2))


## Interrupteur de canal : bouton enfoncé en laiton (stable) ou en lueur (snapshot).
static func switch_button(b: Button, snapshot: bool) -> void:
	var on := NEON if snapshot else BRASS
	b.toggle_mode = true
	b.add_theme_font_override("font", spaced(label_font(), 2))
	b.add_theme_font_size_override("font_size", SIZE_SWITCH)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", INK)
	b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), 8, 12))
	b.add_theme_stylebox_override("hover", box(Color(PAPER, 0.06), 8, 12))
	b.add_theme_stylebox_override("pressed", box(on, 8, 12))
	b.add_theme_stylebox_override("hover_pressed", box(on.lightened(0.1), 8, 12))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 8, 12, NEON, BORDER))


## Barre de progression rayée (lueur quand ça avance, alerte en cas d'échec).
static func progress(p: ProgressBar, failed := false) -> void:
	p.add_theme_stylebox_override("background", box(CONCRETE, 0, 0, STEEL, 1))
	var fill := StyleBoxTexture.new()
	fill.texture = _stripes(ALARM if failed else NEON)
	fill.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	fill.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	p.add_theme_stylebox_override("fill", fill)


static func _stripes(c: Color) -> ImageTexture:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 18:
			img.set_pixel(x, y, c if (x + y) % 18 < 9 else c.darkened(0.22))
	return ImageTexture.create_from_image(img)
