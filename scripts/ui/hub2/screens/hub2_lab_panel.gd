class_name Hub2LabPanel
extends Hub2Panel
## LABO, accueil du hub v2 (docs/hub_v2/Main.dc.html) :
##   - Dr Brown en grand (rendu Blender characters/scientist_hero, left 70,
##     bottom 6, 640 px de haut, ombre portée 0 20px 30px rgba(0,0,0,.6)) ;
##   - colonne de droite (right 28, top 108, 560 px, écart 20) : en-tête
##     (LABORATOIRE DE QUARANTAINE, Dr Brown, rôle), sa réplique du moment
##     (verre, filet turquoise ; Hub2LabKit.lab_line : contrat expiré, étape
##     d'histoire prête, contrat prêt, retour de partie, étape en cours…),
##     CONTRATS (jaune ; avancement de l'histoire « Histoire · chapitre 2,
##     étape 3 sur 5 » ; anneaux pulsés et « 1 TERMINÉ / récompense à
##     récupérer » SEULEMENT quand un contrat est prêt à remettre, sinon le
##     nombre de contrats en cours) et ÉCHANGES (nombre d'échanges possibles
##     maintenant), qui ouvrent les sous-écrans.
## Lecture seule du profil.

const HERO_LEFT := 70.0
const HERO_BOTTOM := 6.0
const HERO_H := 640.0
const COL_W := 560.0
const COL_RIGHT := 28.0
const COL_TOP := 108.0
## Flou de l'ombre portée du héros (niveau de mipmap de son rendu).
const SHADOW_LOD := 5.0

var hero: TextureRect
var hero_shadow: TextureRect
var col: VBoxContainer
var line_label: Label
var contracts_button: Hub2Button
var exchanges_button: Hub2Button
var rings: Hub2PulseRings
var story_label: Label
var ready_box: VBoxContainer
var ready_tag: Hub2Text
var ready_sub: Label
var active_label: Hub2Text
var exchanges_label: Hub2Text
## Réplique affichée (sans guillemets ; tests).
var line_text := ""


## Icône des entrées (svg de la maquette, viewBox 24, trait 2 carré).
class LineIcon extends Control:
	var paths: Array = []
	var color := Hub2Style.INK

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := Hub2Style.px(28) / 24.0
		var o := (size - Vector2(24, 24) * k) * 0.5
		var w := maxf(2.0 * k, 1.0)
		for p in paths:
			var pts := PackedVector2Array()
			for v in p:
				pts.append(o + (v as Vector2) * k)
			# stroke-linecap: square : le trait dépasse d'une demi-épaisseur.
			if pts.size() >= 2:
				var a := pts[0] - (pts[1] - pts[0]).normalized() * w * 0.5
				var b := pts[pts.size() - 1] + (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized() * w * 0.5
				pts[0] = a
				pts[pts.size() - 1] = b
			draw_polyline(pts, color, w, true)


## Réplique sur verre avec un filet turquoise à gauche (top 18, bottom 18,
## 3 px) : le filet est posé hors du MarginContainer du verre.
class LineBox extends Control:
	var box: Hub2Box
	var bar: ColorRect

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		box = Hub2Box.new()
		box.glass()
		box.pad(18, 20, 18, 22)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(box)
		bar = ColorRect.new()
		bar.color = Hub2Style.TEAL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_bottom = 1.0
		bar.offset_top = Hub2Style.px(18)
		bar.offset_bottom = -Hub2Style.px(18)
		bar.offset_left = Hub2Style.px(1)
		bar.offset_right = Hub2Style.px(1) + Hub2Style.px(3)
		add_child(bar)
		box.minimum_size_changed.connect(update_minimum_size)
		resized.connect(update_minimum_size)

	func _get_minimum_size() -> Vector2:
		if box == null:
			return Vector2.ZERO
		# Hauteur selon la largeur (texte replié).
		return Vector2(0, box.get_combined_minimum_size().y)


func veil() -> Dictionary:
	# linear-gradient(90deg, rgba(8, 9, 11, 0) 35%, rgba(8, 9, 11, 0.75) 70%)
	return {"stops": [[0.35, Hub2Style.shade(0.0)], [0.7, Hub2Style.shade(0.75)]]}


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Ouvrir", "Open")], [Hub2Input.TABS, Lang.t("Onglets", "Tabs")],
		[Hub2Input.PLAY, Lang.t("Jouer", "Play")]]


func help() -> String:
	if Hub2LabKit.ready_total(profile()) > 0:
		return _ready_help()
	return Lang.t("Dr Brown cherche l’antidote : ses contrats et ses échanges sont ici.",
			"Dr Brown is working on the antidote: his contracts and trades are here.")


static func _ready_help() -> String:
	return Lang.t("Un contrat est terminé : la récompense t’attend au bureau des contrats.",
			"A contract is done: your reward is waiting at the contracts desk.")


func build() -> void:
	_build_hero()
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", int(Hub2Style.px(20)))
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_right = -Hub2Style.px(COL_RIGHT)
	col.offset_left = -Hub2Style.px(COL_RIGHT) - Hub2Style.px(COL_W)
	col.offset_top = Hub2Style.px(COL_TOP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var kicker := Hub2Text.new()
	kicker.setup(Lang.t("LABORATOIRE DE QUARANTAINE", "QUARANTINE LAB"), Hub2Style.CHAKRA, 600, 13, Hub2Style.TEAL, 0.24)
	head.add_child(kicker)
	var name_t := Hub2Text.new()
	name_t.setup("Dr Brown", Hub2Style.CHAKRA, 700, 52, Hub2Style.TEXT, 0.02)
	name_t.line_height = 52
	head.add_child(name_t)
	var role := Hub2Style.label(Lang.t("Virologue. Il cherche l’antidote, et il a besoin de vous pour ça.",
			"Virologist. He is looking for the antidote, and he needs you for it."), Hub2Style.BARLOW, 400, 17, Hub2Style.text_a(0.7))
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(role)
	# Réplique : 19 px 500, line-height 1.45 (demi-interlignage en haut et
	# en bas, comme le CSS).
	var lb := LineBox.new()
	col.add_child(lb)
	line_label = Hub2Style.label("", Hub2Style.BARLOW, 500, 19, Hub2Style.TEXT)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f := Hub2Style.font(Hub2Style.BARLOW, 500)
	var extra := maxf(Hub2Style.px(19 * 1.45) - Hub2Style.line_height(f, Hub2Style.fs(19)), 0.0)
	line_label.add_theme_constant_override("line_spacing", int(roundf(extra)))
	var lm := MarginContainer.new()
	lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lm.add_theme_constant_override("margin_top", int(roundf(extra * 0.5)))
	lm.add_theme_constant_override("margin_bottom", int(roundf(extra * 0.5)))
	lm.add_child(line_label)
	lb.box.add_child(lm)
	# CONTRATS : toujours jaune (entrée principale), anneaux quand prêt.
	contracts_button = _card(col, Lang.t("CONTRATS", "CONTRACTS"), true)
	contracts_button.pressed.connect(func(): hub.call("open", "contracts"))
	story_label = contracts_button.get_meta("sub")
	var right: HBoxContainer = contracts_button.get_meta("row")
	ready_box = VBoxContainer.new()
	ready_box.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	ready_box.alignment = BoxContainer.ALIGNMENT_CENTER
	ready_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Hub2Box.new()
	tag.flat(Hub2Style.YELLOW)
	tag.pad(4, 10)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_END
	ready_tag = Hub2Text.new()
	ready_tag.setup("", Hub2Style.CHAKRA, 700, 13, Hub2Style.INK, 0.12)
	tag.add_child(ready_tag)
	ready_box.add_child(tag)
	ready_sub = Hub2Style.label("", Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.6))
	ready_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ready_box.add_child(ready_sub)
	right.add_child(ready_box)
	active_label = Hub2Text.new()
	active_label.setup("", Hub2Style.MONO, 500, 14, Hub2Style.YELLOW)
	active_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(active_label)
	rings = Hub2PulseRings.new()
	rings.scale_to = Vector2(1.12, 1.35)
	contracts_button.add_child(rings)
	exchanges_button = _card(col, Lang.t("ÉCHANGES", "EXCHANGES"), false)
	exchanges_button.pressed.connect(func(): hub.call("open", "exchanges"))
	(exchanges_button.get_meta("sub") as Label).text = Lang.t("Des objets précis contre vos échantillons",
			"Specific items for your samples")
	exchanges_button.hint = Lang.t("Le catalogue de Dr Brown : un objet précis contre des échantillons.",
			"Dr Brown's catalogue: a specific item for samples.")
	exchanges_label = Hub2Text.new()
	exchanges_label.setup("", Hub2Style.MONO, 500, 14, Hub2Style.TEAL)
	exchanges_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(exchanges_button.get_meta("row") as HBoxContainer).add_child(exchanges_label)
	contracts_button.focus_neighbor_bottom = contracts_button.get_path_to(exchanges_button)
	exchanges_button.focus_neighbor_top = exchanges_button.get_path_to(contracts_button)
	col.minimum_size_changed.connect(_fit)
	resized.connect(_fit)
	refresh()


## Dr Brown : hauteur 640 (bornée à la place sous la barre du haut à une
## grande taille des menus), largeur selon l'image ; ombre portée floue.
func _build_hero() -> void:
	var tex := HubRenders.character(HubRenders.SCIENTIST_HERO)
	hero_shadow = TextureRect.new()
	hero_shadow.texture = tex
	hero_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_shadow.texture_filter = HubRenders.FILTER
	hero_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float lod = 5.0;\nuniform float alpha = 0.6;\n" \
		+ "void fragment() { COLOR = vec4(0.0, 0.0, 0.0, textureLod(TEXTURE, UV, lod).a * alpha); }\n"
	sm.shader = sh
	sm.set_shader_parameter("lod", SHADOW_LOD)
	hero_shadow.material = sm
	add_child(hero_shadow)
	hero = TextureRect.new()
	hero.texture = tex
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.texture_filter = HubRenders.FILTER
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero)
	resized.connect(_place_hero)
	_place_hero()


func _place_hero() -> void:
	if hero == null:
		return
	var ts := hero.texture.get_size() if hero.texture else Vector2(1400, 1800)
	var bottom := Hub2Style.px(HERO_BOTTOM)
	var h := Hub2Style.px(HERO_H)
	var room := (size.y if size.y > 0.0 else Hub2Style.px(720)) - bottom - Hub2Style.px(Hub2Style.TOP_BAR_H)
	h = minf(h, maxf(room, Hub2Style.px(200)))
	var w := roundf(h * ts.x / maxf(ts.y, 1.0))
	var y := (size.y if size.y > 0.0 else 720.0) - bottom - h
	hero.position = Vector2(Hub2Style.px(HERO_LEFT), y)
	hero.size = Vector2(w, h)
	hero_shadow.position = hero.position + Vector2(0, Hub2Style.px(20))
	hero_shadow.size = hero.size
	# L'ombre ne sort pas de l'écran (elle s'arrête au bord, comme overflow).
	var over := hero_shadow.position.y + hero_shadow.size.y - size.y
	if size.y > 0.0 and over > 0.0:
		hero_shadow.size.y -= over


## Colonne dans l'écran : relevée (jusque sous la barre du haut) si la
## réplique ou une grande taille des menus la font descendre sous les
## invites.
func _fit() -> void:
	if col == null or size.y <= 0.0:
		return
	var h := col.get_combined_minimum_size().y
	var limit := size.y - Hub2Style.px(Hub2Style.PROMPTS_H) - Hub2Style.px(8)
	var top := Hub2Style.px(COL_TOP)
	if top + h > limit:
		top = maxf(limit - h, Hub2Style.px(Hub2Style.TOP_BAR_H) + Hub2Style.px(8))
	col.offset_top = top
	col.offset_bottom = top + h


## Entrée du LABO (<a> de la maquette) : padding 18 22, écart 18, carré
## d'icône 52 px, titre Chakra Petch 24 px 700 0.1em, ligne Barlow 15 px 80 %.
## Métadonnées : "row" (rangée, pour la partie droite), "sub" (ligne).
func _card(parent: Control, title: String, yellow: bool) -> Hub2Button:
	var b := Hub2Button.new()
	if yellow:
		b.box.glass(Hub2Style.YELLOW_TINT, Hub2Style.YELLOW, 2.0)
	else:
		b.box.glass(Hub2Style.GLASS, Hub2Style.white_a(0.12), 1.0)
	b.box.pad(18, 22)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(18)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(row)
	var icon := Hub2Box.new()
	var glyph := LineIcon.new()
	if yellow:
		icon.flat(Hub2Style.YELLOW)
		glyph.color = Hub2Style.INK
		glyph.paths = [[Vector2(6, 2), Vector2(15, 2), Vector2(19, 6), Vector2(19, 22), Vector2(6, 22), Vector2(6, 2)],
			[Vector2(14, 2), Vector2(14, 7), Vector2(19, 7)], [Vector2(9, 12), Vector2(16, 12)], [Vector2(9, 16), Vector2(16, 16)]]
	else:
		icon.flat(Hub2Style.teal_a(0.14), Hub2Style.teal_a(0.5), 1.0)
		glyph.color = Hub2Style.TEAL
		glyph.paths = [[Vector2(4, 8), Vector2(18, 8), Vector2(14, 4)], [Vector2(20, 16), Vector2(6, 16), Vector2(10, 20)]]
	icon.custom_minimum_size = Hub2Style.pxv(52, 52)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_child(glyph)
	row.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var t := Hub2Text.new()
	t.setup(title, Hub2Style.CHAKRA, 700, 24, Hub2Style.TEXT, 0.1)
	v.add_child(t)
	var sub := Hub2Style.label("", Hub2Style.BARLOW, 400, 15, Hub2Style.text_a(0.8))
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	b.set_meta("row", row)
	b.set_meta("sub", sub)
	parent.add_child(b)
	return b


func first_focus() -> Control:
	return contracts_button


## Profil changé : réplique, état des contrats, échanges possibles.
func refresh() -> void:
	var pr := profile()
	if pr == null or contracts_button == null:
		return
	var expired: PackedStringArray = hub.get("expired_notice") if hub and "expired_notice" in hub else PackedStringArray()
	line_text = Hub2LabKit.lab_line(pr, expired, Router.last_match)
	line_label.text = Hub2LabKit.quoted(line_text)
	story_label.text = Hub2LabKit.story_line(pr)
	var ready := Hub2LabKit.ready_total(pr)
	rings.running = ready > 0
	ready_box.visible = ready > 0
	ready_tag.text = Lang.t("%d TERMINÉ%s" % [ready, "S" if ready > 1 else ""], "%d DONE" % ready)
	ready_sub.text = Lang.t("récompense%s à récupérer" % ("s" if ready > 1 else ""),
			"reward%s to collect" % ("s" if ready > 1 else ""))
	var going := HubContractsView.active(pr).size() + (0 if StoryRules.is_complete(pr) else 1)
	active_label.visible = ready == 0
	active_label.text = Lang.t("%d en cours", "%d ongoing") % going
	contracts_button.hint = _ready_help() if ready > 0 else Lang.t("Les contrats de Dr Brown : l’histoire et les contrats temporaires.",
			"Dr Brown's contracts: the story and timed contracts.")
	var n := ExchangeRules.listed(pr, HubContractsView.data(), HubContractsView.today(), true).size()
	exchanges_label.text = Lang.t("%d possible%s" % [n, "s" if n > 1 else ""], "%d available" % n)
	if hub and contracts_button.has_focus():
		hub.call("set_hint", contracts_button.hint)


func badge() -> bool:
	return Hub2LabKit.ready_total(profile()) > 0
