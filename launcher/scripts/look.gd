extends RefCounted
## Identité visuelle du lanceur (maquettes validées le 30/09/2026) : bunker des
## années 60, caisses au pochoir, dossier classé, lampes d'alerte, grain de
## film. Thème Godot réutilisable (Look.theme()), palette et styles nommés :
## le menu principal du jeu pourra reprendre les mêmes. Aucun logo pour
## l'instant : le nom seul, au pochoir.

## Palette.
const INK := Color("0e100c")        # nuit du bunker (fond)
const CONCRETE := Color("1a1d17")   # béton : panneaux
const STEEL := Color("2a2f26")      # tôle : bords
const PAPER := Color("e6d9ba")      # papier du dossier : texte principal
const DIM := Color("9c9580")        # texte secondaire
const ALARM := Color("d2381f")      # lampe d'alerte : action principale, erreur
const NEON := Color("57e3cf")       # lueur : en cours, canal snapshot
const BRASS := Color("c49a4a")      # laiton : stable, installé

## Polices du système les plus proches des maquettes (pochoir condensé,
## étiquettes condensées, machine à écrire) ; repli si absentes.
static func display_font() -> SystemFont:
	return _font(["Impact", "Bahnschrift Condensed", "Arial Narrow", "sans-serif"], 700)


static func body_font() -> SystemFont:
	return _font(["Bahnschrift SemiCondensed", "Bahnschrift", "Arial Narrow", "Segoe UI", "sans-serif"], 400)


static func file_font() -> SystemFont:
	return _font(["Courier New", "Consolas", "monospace"], 400)


static func _font(names: Array, weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


## Boîte pleine, bord facultatif.
static func box(bg: Color, pad := 0, border := Color(0, 0, 0, 0), width := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	if width > 0:
		b.border_color = border
		b.set_border_width_all(width)
	return b


## Thème commun : textes, listes, boutons, menus déroulants, barres.
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = 18
	th.set_color("font_color", "Label", PAPER)
	th.set_color("default_color", "RichTextLabel", PAPER)
	# Liste des versions.
	th.set_color("font_color", "ItemList", PAPER)
	th.set_color("font_selected_color", "ItemList", PAPER)
	th.set_color("font_hovered_color", "ItemList", PAPER)
	var sel := box(Color(ALARM, 0.16), 0)
	sel.border_color = ALARM
	sel.border_width_left = 4
	th.set_stylebox("selected", "ItemList", sel)
	th.set_stylebox("selected_focus", "ItemList", sel)
	th.set_stylebox("hovered", "ItemList", box(Color(PAPER, 0.05)))
	th.set_stylebox("panel", "ItemList", box(Color(0, 0, 0, 0), 4))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_constant("v_separation", "ItemList", 12)
	th.set_constant("h_separation", "ItemList", 10)
	# Boutons (sobres) et menus déroulants.
	for t in ["Button", "OptionButton"]:
		th.set_color("font_color", t, DIM)
		th.set_color("font_hover_color", t, PAPER)
		th.set_color("font_pressed_color", t, INK)
		th.set_color("font_focus_color", t, PAPER)
		th.set_color("font_disabled_color", t, Color(DIM, 0.5))
		th.set_stylebox("normal", t, box(Color(0, 0, 0, 0), 10, STEEL, 2))
		th.set_stylebox("hover", t, box(Color(PAPER, 0.06), 10, STEEL, 2))
		th.set_stylebox("pressed", t, box(PAPER, 10, PAPER, 2))
		th.set_stylebox("disabled", t, box(Color(0, 0, 0, 0), 10, Color(STEEL, 0.5), 2))
		th.set_stylebox("focus", t, box(Color(0, 0, 0, 0), 10, NEON, 2))
	th.set_constant("outline_size", "Label", 0)
	# Défilement discret.
	th.set_stylebox("grabber", "VScrollBar", box(STEEL))
	th.set_stylebox("grabber_highlight", "VScrollBar", box(DIM))
	th.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0)))
	return th


## Bouton d'action : JOUER (alerte, lueur) ou secondaire (fond transparent).
static func action_button(b: Button, main: bool) -> void:
	b.add_theme_font_override("font", display_font())
	b.add_theme_font_size_override("font_size", 38 if main else 18)
	var c := ALARM if main else Color(0, 0, 0, 0)
	var edge := Color("f06a4f") if main else STEEL
	b.add_theme_color_override("font_color", PAPER if main else DIM)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_pressed_color", PAPER)
	b.add_theme_color_override("font_disabled_color", DIM)
	var n := box(c, 12, edge, 3 if main else 2)
	if main:
		n.shadow_color = Color(ALARM, 0.45)
		n.shadow_size = 18
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", box(c.lightened(0.12) if main else Color(PAPER, 0.06), 12, edge, 3 if main else 2))
	b.add_theme_stylebox_override("pressed", box(c.darkened(0.2) if main else Color(PAPER, 0.1), 12, edge, 3 if main else 2))
	b.add_theme_stylebox_override("disabled", box(STEEL if main else Color(0, 0, 0, 0), 12, STEEL, 2))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 12, NEON, 2))


## Interrupteur de canal : bouton enfoncé en laiton (stable) ou en lueur (snapshot).
static func switch_button(b: Button, snapshot: bool) -> void:
	var on := NEON if snapshot else BRASS
	b.toggle_mode = true
	b.add_theme_font_override("font", body_font())
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", PAPER)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", INK)
	b.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), 10))
	b.add_theme_stylebox_override("hover", box(Color(PAPER, 0.06), 10))
	b.add_theme_stylebox_override("pressed", box(on, 10))
	b.add_theme_stylebox_override("hover_pressed", box(on.lightened(0.1), 10))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 10, NEON, 2))


## Barre de progression rayée (lueur quand ça avance, alerte en cas d'échec).
static func progress(p: ProgressBar, failed := false) -> void:
	p.add_theme_stylebox_override("background", box(CONCRETE, 0, STEEL, 1))
	var fill := StyleBoxTexture.new()
	fill.texture = _stripes(ALARM if failed else NEON)
	fill.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	fill.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	p.add_theme_stylebox_override("fill", fill)


static func _stripes(c: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, c if (x + y) % 16 < 8 else c.darkened(0.25))
	return ImageTexture.create_from_image(img)


## Voile de grain de film et de vignette (au-dessus de tout, ignore la souris).
static func grain_overlay() -> ColorRect:
	var r := ColorRect.new()
	r.name = "Grain"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.07;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float n = hash(cell + floor(TIME * 18.0) * 1.37) - 0.5;
	float d = distance(UV, vec2(0.5, 0.42));
	float v = smoothstep(0.55, 1.05, d);
	COLOR = vec4(vec3(0.5 + n), abs(n) * strength * 2.0);
	COLOR = mix(COLOR, vec4(0.0, 0.0, 0.0, 0.55), v);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	return r
