class_name Hub2RecapPanel
extends Hub2Panel
## Récapitulatif d'après partie (docs/hub_v2/Recap.dc.html), ouvert au retour
## au hub v2 après une partie (MainMenu) ; données : Hub2RecapModel
## (Router.last_match et le profil).
##
##   - en-tête : « RETOUR AU LABO · <CARTE> », ÉVACUÉ (turquoise) ou la
##     défaite, manche atteinte, zombies éliminés, durée ;
##   - XP (560 px) : pavé du niveau, barre et « +N XP » qui grimpent (départ
##     0,7 s, 3,8 s, ease-out cubique) ; à chaque passage de niveau : pavé qui
##     saute (1 -> 1,45 -> 1), deux anneaux (jaune puis turquoise 0,18 s
##     après), éclair doré, « NIVEAU N ! », barre turquoise repartie de 0 ;
##     détail de l'XP (lignes qui entrent une à une), DÉBLOQUÉ ;
##   - butin gardé (armes : rendus, NEUF, rareté ; échantillons ×n ; contrat
##     prêt ; RIEN DE PERDU) ou perdu (§4.16 : ce qui est perdu) ; carte
##     perso : POUR LE FUN, aucune progression ;
##   - pied : CONTINUER (A) -> LABO (salon coop
##     ouvert : JOUER).
## A / Entrée pendant l'animation : la termine d'un coup ; ensuite :
## CONTINUER. Sons : tic de l'XP (ui_xp_tick), passage de niveau (level_up).
## Sans barre du haut ni invites ; voile 0.62 ; <main> 48 / 40 / 48 / 64.

## Fin de toutes les animations (s) : XP (0,7 + 3,8) + « NIVEAU N ! » (2,2).
const END_TIME := 8.0
## Durées des @keyframes (s).
const POP_TIME := 0.7
const RING_TIME := 1.1
const RING_B_DELAY := 0.18
const TEXT_TIME := 2.2
const FLASH_TIME := 0.9
const ROW_TIME := 0.4
## Tic de l'XP : un toutes les TICK_GAP s au plus pendant que l'XP grimpe.
const TICK_GAP := 0.07

var model: Hub2RecapModel
## Temps de l'animation (s depuis l'affichage) ; figé (tests) : `frozen`.
var t := 0.0
var frozen := false
var playing := false
var _last_tick := -1.0
var _last_gain := 0
var _ups: Array = []  # [[niveau, temps]]
var _ups_sounded := 0

var _main: VBoxContainer
var title_text: Hub2Text
var level_badge: Hub2Box
var badge_wrap: Control
var badge_level: Hub2Text
var badge_label: Hub2Text
var rings: Control
var bar_track: Control
var xp_line: Hub2Text
var gained_text: Hub2Text
var level_text: Hub2Text
var level_glow: TextureRect
var flash: ColorRect
var row_nodes: Array = []  # [Control, délai]
var unlocked_box: Control
var continue_button: Hub2Button
var xp_section: Hub2Box


func veil() -> Dictionary:
	return {"color": Hub2Style.shade(0.62)}


func shows_top_bar() -> bool:
	return false


func shows_prompts() -> bool:
	return false


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Continuer", "Continue")]]


## <main> du récapitulatif : left 48, right 48, top 40, bottom 64.
func content_margins() -> Vector4:
	return Vector4(Hub2Style.px(48), Hub2Style.px(40), Hub2Style.px(48), Hub2Style.px(64))


func build() -> void:
	set_process(false)


func shown() -> void:
	load_last()
	play()


func hidden() -> void:
	set_process(false)
	playing = false


func first_focus() -> Control:
	return continue_button


## B / Échap : CONTINUER.
func back() -> bool:
	go_on()
	return true


## A / Entrée pendant l'animation : la termine (consommé).
func handle_input(event: InputEvent) -> bool:
	if animating() and _is_accept(event):
		finish()
		return true
	return false


## Avant les contrôles : A / Entrée pendant l'animation ne valide pas
## CONTINUER (qui a le focus), il termine l'animation.
func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and animating() and _is_accept(event):
		finish()
		get_viewport().set_input_as_handled()


static func _is_accept(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		return true
	var jb := event as InputEventJoypadButton
	return jb != null and jb.pressed and jb.button_index == JOY_BUTTON_A


## Données de la dernière partie (Router.last_match) et du profil.
func load_last() -> void:
	set_model(Hub2RecapModel.new().read(Router.last_match, profile()))
	# Vu : un retour au hub plus tard (partie quittée…) ne le remontre pas.
	if not Router.last_match.is_empty():
		Router.last_match["recap_seen"] = true
	# Coop : « je suis revenu au salon » dès le récapitulatif (l'hôte attend
	# tout le groupe avant de relancer, LobbyReturn).
	if Hub2PlayPanel.in_lobby():
		Net.lobby_return.report_in_lobby()


func set_model(m: Hub2RecapModel) -> void:
	model = m
	_ups.clear()
	for u in model.level_ups():
		_ups.append([int(u[0]), model.time_of_gain(int(u[1]))])
	_rebuild()
	# Écran déjà affiché (nouvelles données) : le focus revient à CONTINUER.
	if is_visible_in_tree() and hub:
		hub.focus_later(continue_button)


## Joue l'animation depuis le début (affichage du récapitulatif).
func play() -> void:
	t = 0.0
	_last_tick = -1.0
	_last_gain = 0
	_ups_sounded = 0
	playing = true
	set_process(not frozen)
	apply_time(0.0)


## Termine l'animation d'un coup (état final, sans les effets passés).
func finish() -> void:
	t = END_TIME
	_ups_sounded = _ups.size()
	_last_gain = model.gained if model else 0
	apply_time(t)
	playing = false
	set_process(false)


func animating() -> bool:
	return playing and t < END_TIME


func _process(delta: float) -> void:
	if frozen or not playing:
		return
	t += delta
	_sounds()
	apply_time(t)
	if t >= END_TIME:
		playing = false
		set_process(false)


func _sounds() -> void:
	if model == null:
		return
	var g := model.gained_at(t)
	if g != _last_gain and t - _last_tick >= TICK_GAP:
		_last_tick = t
		_last_gain = g
		Audio.play_2d("ui_xp_tick", -6.0, 0.0, "UI", 1.0 + 0.45 * Hub2RecapModel.xp_progress(t))
	while _ups_sounded < _ups.size() and t >= float(_ups[_ups_sounded][1]):
		_ups_sounded += 1
		Audio.play_ui("level_up", 0.0)


## CONTINUER : LABO (salon coop encore ouvert : JOUER).
func go_on() -> void:
	if hub == null:
		return
	Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
	hub.call("open", "play" if Hub2PlayPanel.in_lobby() else "lab")


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	row_nodes.clear()
	# Éclair doré (plein écran, sous le contenu).
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://assets/shaders/hub2_radial.gdshader")
	fm.set_shader_parameter("color", Color(Hub2Style.YELLOW, 0.55))
	fm.set_shader_parameter("center", Vector2(0.3, 0.42))
	flash.material = fm
	flash.resized.connect(_flash_size)
	flash.visible = false
	add_child(flash)
	_main = Hub2Ui.vbox(22)
	add_main(_main)
	_build_header()
	var row := Hub2Ui.hbox(22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_child(row)
	row.add_child(_build_xp())
	var loot := _scroller(_build_loot())
	loot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(loot)
	_build_footer()


func _flash_size() -> void:
	var s := flash.size
	var c := Vector2(0.3, 0.42) * s
	# radial-gradient(circle …) : rayon = distance au coin le plus loin ; 60 %.
	var far := 0.0
	for k in [Vector2.ZERO, Vector2(s.x, 0), Vector2(0, s.y), s]:
		far = maxf(far, c.distance_to(k))
	var m := flash.material as ShaderMaterial
	m.set_shader_parameter("rect_size", s)
	m.set_shader_parameter("radius", far * 0.6)


func _build_header() -> void:
	var h := Hub2Ui.hbox(24)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	_main.add_child(h)
	var col := Hub2Ui.vbox(4)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(col)
	var k := Hub2Text.new()
	k.setup(model.kicker(), Hub2Style.CHAKRA, 600, 13, Hub2Style.text_a(0.6), 0.24)
	col.add_child(k)
	title_text = Hub2Text.new()
	title_text.setup(model.title(), Hub2Style.CHAKRA, 700, 64, Hub2Style.TEAL if model.evacuated else Hub2Style.BAD, 0.04)
	title_text.line_height = 64
	col.add_child(title_text)
	var stats_pad := MarginContainer.new()
	stats_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_pad.add_theme_constant_override("margin_bottom", int(Hub2Style.px(8)))
	stats_pad.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(stats_pad)
	var stats := Hub2Ui.hbox(28)
	stats_pad.add_child(stats)
	for s in [[Lang.t("Manche atteinte", "Round reached"), str(model.round_reached)],
			[Lang.t("Zombies éliminés", "Zombies killed"), Hub2Style.num(model.kills)],
			[Lang.t("Durée", "Duration"), model.duration_text()]]:
		var v := Hub2Ui.vbox(0)
		stats.add_child(v)
		v.add_child(Hub2Style.label(String(s[0]), Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55)))
		var n := Hub2Text.new()
		n.setup(String(s[1]), Hub2Style.MONO, 700, 24, Hub2Style.TEXT)
		v.add_child(n)


## Panneau de l'XP (560 px, rgba(10, 11, 13, 0.7), flou 12, padding 24 26,
## écart 18).
func _build_xp() -> Control:
	xp_section = Hub2Box.new()
	xp_section.glass(Hub2Style.GLASS_STRONG)
	xp_section.pad(24, 26)
	# 560 px (maquette) ; TAILLE DES MENUS plus grande : au plus 48 % de
	# <main>, le butin garde sa place.
	var main_w := Hub2Style.SCREEN.x - 2.0 * Hub2Style.px(48)
	xp_section.custom_minimum_size.x = minf(Hub2Style.px(560), roundf(main_w * 0.48))
	var v := Hub2Ui.vbox(18)
	xp_section.add_child(v)
	var top := Hub2Ui.hbox(22)
	v.add_child(top)
	# Pavé du niveau (92 × 92, biseaux 14) et ses anneaux.
	badge_wrap = Control.new()
	badge_wrap.custom_minimum_size = Hub2Style.pxv(92, 92)
	badge_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(badge_wrap)
	rings = Control.new()
	rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rings.set_anchors_preset(Control.PRESET_FULL_RECT)
	rings.draw.connect(_draw_rings)
	badge_wrap.add_child(rings)
	level_badge = Hub2Box.new()
	level_badge.chamfer(14)
	level_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_badge.resized.connect(func(): level_badge.pivot_offset = level_badge.size * 0.5)
	badge_wrap.add_child(level_badge)
	var bv := Hub2Ui.vbox(2)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	level_badge.add_child(bv)
	badge_label = Hub2Text.new()
	badge_label.setup(Lang.t("NIV.", "LVL"), Hub2Style.CHAKRA, 700, 12, Hub2Style.YELLOW, 0.16)
	badge_label.align = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(badge_label)
	badge_level = Hub2Text.new()
	badge_level.setup("", Hub2Style.MONO, 700, 38, Hub2Style.YELLOW)
	badge_level.line_height = 38
	badge_level.align = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(badge_level)
	# Expérience : titre et XP, barre, « +N XP ».
	var right := Hub2Ui.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	var hr := Hub2Ui.hbox(8)
	right.add_child(hr)
	hr.add_child(Hub2Ui.section(Lang.t("EXPÉRIENCE", "EXPERIENCE"), 13, 600, 0.6, 0.18))
	hr.add_child(Hub2Ui.spring())
	xp_line = Hub2Text.new()
	xp_line.setup("", Hub2Style.MONO, 500, 13, Hub2Style.text_a(0.75))
	hr.add_child(xp_line)
	bar_track = Control.new()
	bar_track.custom_minimum_size = Vector2(0, Hub2Style.px(14))
	bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_track.draw.connect(_draw_bar)
	right.add_child(bar_track)
	gained_text = Hub2Text.new()
	gained_text.setup("", Hub2Style.MONO, 700, 30, Hub2Style.YELLOW)
	right.add_child(gained_text)
	# Détail de l'XP (liseré haut, padding-top 12, écart 2 ; lignes 7 0).
	var det := Hub2Box.new()
	det.flat(Color(0, 0, 0, 0), Hub2Style.LINE, 0.0)
	det.border = Vector4(0, 1, 0, 0)
	det.border_color = Hub2Style.LINE
	det.pad(13, 0, 0, 0)
	# Défile (sans barre) si le panneau est trop court (TAILLE DES MENUS) ;
	# prend la place libre : DÉBLOQUÉ reste en bas (margin-top: auto).
	v.add_child(_scroller(det))
	var rv := Hub2Ui.vbox(2)
	det.add_child(rv)
	var i := 0
	var rows: Array = model.rows
	if not model.progress:
		rows = []
	for r in rows:
		var line := MarginContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("margin_top", int(Hub2Style.px(7)))
		line.add_theme_constant_override("margin_bottom", int(Hub2Style.px(7)))
		var lh := Hub2Ui.hbox(8)
		line.add_child(lh)
		var lt := Hub2Style.label(String(r.label), Hub2Style.BARLOW, 400, 15, Hub2Style.text_a(0.8))
		lh.add_child(lt)
		lh.add_child(Hub2Ui.spring())
		var lx := Hub2Text.new()
		lx.setup("+" + Hub2Style.num(int(r.xp)), Hub2Style.MONO, 700, 15, Hub2Style.YELLOW)
		lh.add_child(lx)
		rv.add_child(line)
		row_nodes.append([line, 0.15 * i])
		i += 1
	if not model.progress:
		var fun := Hub2Ui.paragraph(ProgressGate.rule_text(), 15, 0.8)
		var fm := MarginContainer.new()
		fm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fm.add_theme_constant_override("margin_top", int(Hub2Style.px(7)))
		fm.add_child(fun)
		rv.add_child(fm)
		row_nodes.append([fm, 0.0])
	elif rows.is_empty():
		rv.add_child(Hub2Ui.paragraph(Lang.t("Aucune XP cette fois.", "No XP this time."), 15, 0.6))
	# DÉBLOQUÉ (margin-top: auto : en bas du panneau).
	if model.unlocked != "":
		var u := Hub2Box.new()
		u.flat(Hub2Style.teal_a(0.1), Hub2Style.teal_a(0.4), 1.0)
		u.pad(12, 14)
		var uh := Hub2Ui.hbox(12)
		u.add_child(uh)
		var ul := Hub2Text.new()
		ul.setup(Lang.t("DÉBLOQUÉ", "UNLOCKED"), Hub2Style.CHAKRA, 700, 12, Hub2Style.TEAL, 0.16)
		ul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		uh.add_child(ul)
		var ut := Hub2Ui.paragraph(model.unlocked, 14, 1.0, 1.2)
		ut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uh.add_child(ut)
		v.add_child(u)
		unlocked_box = u
	else:
		unlocked_box = null
	# « NIVEAU N ! » (position: absolute; left 26; right 26; top 128).
	level_glow = TextureRect.new()
	level_glow.texture = _glow_texture()
	level_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	level_glow.stretch_mode = TextureRect.STRETCH_SCALE
	level_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_glow.visible = false
	level_text = Hub2Text.new()
	level_text.setup("", Hub2Style.CHAKRA, 700, 30, Hub2Style.YELLOW, 0.22)
	level_text.align = HORIZONTAL_ALIGNMENT_CENTER
	level_text.visible = false
	var over := Control.new()
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_section.add_child(over)
	over.add_child(level_glow)
	over.add_child(level_text)
	over.resized.connect(func(): _place_level_text(over))
	return xp_section


## Lueur du texte (text-shadow: 0 0 24px rgba(245, 197, 66, 0.7)) :
## approchée par une tache floue sous le texte.
static func _glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(Hub2Style.YELLOW, 0.32), Color(Hub2Style.YELLOW, 0.14), Color(Hub2Style.YELLOW, 0.0)])
	var t2 := GradientTexture2D.new()
	t2.gradient = g
	t2.fill = GradientTexture2D.FILL_RADIAL
	t2.fill_from = Vector2(0.5, 0.5)
	t2.fill_to = Vector2(1.0, 0.5)
	t2.width = 128
	t2.height = 32
	return t2


## Position du « NIVEAU N ! » dans le panneau (le panneau est un
## MarginContainer : `over` le couvre entier, padding compris).
func _place_level_text(over: Control) -> void:
	# `over` est posé dans le padding (24 26) : top 128 du panneau = 104 ici,
	# left / right 26 = bords du contenu.
	var lh := Hub2Style.line_height(Hub2Style.font(Hub2Style.CHAKRA, 700), Hub2Style.fs(30))
	_level_y = Hub2Style.px(128) - Hub2Style.px(24)
	level_text.position = Vector2(0, _level_y)
	level_text.size = Vector2(over.size.x, lh)
	level_text.pivot_offset = level_text.size * 0.5
	var gw := Hub2Style.px(320)
	level_glow.size = Vector2(gw, lh + Hub2Style.px(48))
	level_glow.position = Vector2((over.size.x - gw) * 0.5, _level_y - Hub2Style.px(24))


var _level_y := 0.0


## Liste défilante sans barre visible (molette) autour de `c` : remplit la
## place donnée, ne demande aucune hauteur minimale (à 100 % tout tient, rien
## ne défile ; à 130 % le bas défile au lieu de passer sous le pied de page).
static func _scroller(c: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(c)
	return s


## Butin (flex: 1, écart 14).
func _build_loot() -> Control:
	var v := Hub2Ui.vbox(14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h2 := Hub2Text.new()
	h2.setup(model.loot_title(), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT if model.kept else Hub2Style.text_a(0.8), 0.08)
	v.add_child(h2)
	var lost := not model.kept
	# Armes : grille de 3 colonnes (écart 10), 2 rangées au plus.
	var ws: Array = model.weapons
	var grid := Hub2Ui.vbox(10)
	v.add_child(grid)
	var shown := mini(ws.size(), 6)
	if ws.is_empty():
		var none := Control.new()
		none.custom_minimum_size = Vector2(0, Hub2Style.px(64))
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		none.add_child(Hub2Ui.dashed_frame(Hub2Style.white_a(0.15)))
		var nl := Hub2Style.label(Lang.t("Aucune arme rapportée", "No weapon brought back") if model.kept or model.progress
				else Lang.t("Aucune arme", "No weapon"), Hub2Style.BARLOW, 400, 14, Hub2Style.text_a(0.5))
		nl.set_anchors_preset(Control.PRESET_FULL_RECT)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none.add_child(nl)
		grid.add_child(none)
	var row: HBoxContainer = null
	for i in shown:
		if i % 3 == 0:
			row = Hub2Ui.hbox(10)
			grid.add_child(row)
		var card := _weapon_card(ws[i], lost, i == 5 and ws.size() > 6, ws.size() - 5)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		row_nodes.append([card, 0.3 + 0.15 * i])
	if row and row.get_child_count() < 3:
		for k in 3 - row.get_child_count():
			var pad := Control.new()
			pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(pad)
	# Échantillons.
	var sb := Hub2Box.new()
	sb.glass()
	sb.pad(14, 16)
	v.add_child(sb)
	var sv := Hub2Ui.vbox(8)
	sb.add_child(sv)
	var title := "%s · %d" % [Lang.t("ÉCHANTILLONS", "SAMPLES"), model.sample_total()]
	if model.parts > 0:
		title += " · %s · %d" % [Lang.t("PIÈCES", "PARTS"), model.parts]
	sv.add_child(Hub2Ui.section(title))
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("h_separation", int(Hub2Style.px(14)))
	flow.add_theme_constant_override("v_separation", int(Hub2Style.px(14)))
	sv.add_child(flow)
	var j := 0
	for s in model.samples:
		var chip := _sample_chip(s, lost)
		flow.add_child(chip)
		row_nodes.append([chip, 0.8 + 0.1 * j])
		j += 1
	if model.samples.is_empty():
		sv.add_child(Hub2Style.label(Lang.t("Aucun échantillon", "No samples"), Hub2Style.BARLOW, 400, 14, Hub2Style.text_a(0.5)))
	# Contrat prêt et état du butin.
	var bottom := Hub2Ui.hbox(10)
	v.add_child(bottom)
	if model.contract_ready != "":
		bottom.add_child(_note_box(Lang.t("CONTRAT", "CONTRACT"), Lang.t("%s : prêt à remettre", "%s: ready to hand in") % model.contract_ready,
				Hub2Style.YELLOW, Hub2Style.yellow_a(0.1), Hub2Style.YELLOW, Hub2Style.TEXT))
	var o := model.outcome()
	var col := Hub2Style.TEAL
	match String(o[2]):
		"lost":
			col = Hub2Style.BAD
		"fun":
			col = Color("D7B3FF")
		"challenge":
			col = Hub2Style.TEAL
	bottom.add_child(_note_box(String(o[0]), String(o[1]), col, Hub2Style.GLASS, Hub2Style.LINE, Hub2Style.text_a(0.75)))
	return v


## Carte d'une arme (padding 12 14, liseré haut 3 px de la rareté, NEUF).
func _weapon_card(w: Dictionary, lost: bool, more: bool, more_n: int) -> Control:
	var rc := Hub2Style.rarity_color(int(w.rarity))
	var b := Hub2Box.new()
	b.glass()
	b.border = Vector4(1, 3, 1, 1)
	b.pad(15, 14, 12, 14)
	var v := Hub2Ui.vbox(4)
	b.add_child(v)
	var img := Hub2Render.new()
	img.texture = HubRenders.weapon(String(w.id))
	img.custom_minimum_size = Vector2(0, Hub2Style.px(62))
	img.shadow = Vector3(0, 6, 8)
	img.shadow_color = Color(0, 0, 0, 0.6)
	v.add_child(img)
	var n := Hub2Style.label(String(w.name), Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	n.custom_minimum_size.x = Hub2Style.px(40)
	v.add_child(n)
	var rar := Hub2Text.new()
	rar.setup("%s · %s %d" % [GameWeapon.rarity_name(int(w.rarity)).to_upper(), Lang.t("NIV.", "LVL"), int(w.lvl)],
			Hub2Style.CHAKRA, 700, 12, rc, 0.12)
	v.add_child(Hub2Ui.clipped(rar))
	# Liseré haut de la rareté (border-top: 3px) par-dessus le liseré 1 px.
	var top := ColorRect.new()
	top.color = rc
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(b)
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = Hub2Style.px(3)
	wrap.add_child(top)
	b.minimum_size_changed.connect(func(): wrap.custom_minimum_size = b.get_combined_minimum_size())
	wrap.custom_minimum_size = b.get_combined_minimum_size()
	var tag_text := ""
	var tag_bg := Hub2Style.YELLOW
	var tag_fg := Hub2Style.INK
	if lost:
		tag_text = Lang.t("PERDU", "LOST") if model.progress and not model.challenge else Lang.t("NON GARDÉ", "NOT KEPT")
		tag_bg = Hub2Style.BAD
	elif w.new:
		tag_text = Lang.t("NEUF", "NEW")
	else:
		tag_text = Lang.t("AMÉLIORÉE", "UPGRADED")
		tag_bg = Hub2Style.TEAL
	if more:
		tag_text = "+%d" % more_n
		tag_bg = Hub2Style.TEXT
	var tag := Hub2Ui.tag(tag_text, tag_fg, Color(0, 0, 0, 0), tag_bg, 10, 0.12, 1, 6)
	tag.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tag.offset_right = -Hub2Style.px(8)
	tag.offset_left = tag.offset_right
	tag.offset_top = Hub2Style.px(6)
	wrap.add_child(tag)
	if lost:
		b.modulate.a = 0.55
	return wrap


## Échantillon : padding 4, fond rgba(255, 255, 255, 0.05), rendu 52 px,
## quantité « ×3 » en bas à droite (-4, -4).
func _sample_chip(s: Dictionary, lost: bool) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = Hub2Style.pxv(60, 60)
	var bg := ColorRect.new()
	bg.color = Hub2Style.white_a(0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bg)
	var img := Hub2Render.new()
	img.texture = HubRenders.sample(String(s.id))
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.offset_left = Hub2Style.px(4)
	img.offset_top = Hub2Style.px(4)
	img.offset_right = -Hub2Style.px(4)
	img.offset_bottom = -Hub2Style.px(4)
	if lost:
		img.tint = Color(1, 1, 1, 0.45)
	wrap.add_child(img)
	var q := Hub2Box.new()
	q.flat(Hub2Style.TEXT)
	q.pad(1, 5)
	var qt := Hub2Text.new()
	qt.setup("×%d" % int(s.qty), Hub2Style.MONO, 700, 12, Hub2Style.INK)
	qt.align = HORIZONTAL_ALIGNMENT_CENTER
	q.add_child(qt)
	q.custom_minimum_size.x = Hub2Style.px(22)
	q.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	q.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	q.grow_vertical = Control.GROW_DIRECTION_BEGIN
	q.offset_right = Hub2Style.px(4)
	q.offset_bottom = Hub2Style.px(4)
	q.offset_left = q.offset_right
	q.offset_top = q.offset_bottom
	wrap.add_child(q)
	wrap.tooltip_text = String(s.name)
	return wrap


## Bloc « CONTRAT » / « RIEN DE PERDU » (flex: 1, padding 12 16, écart 12).
func _note_box(label: String, text: String, label_col: Color, bg: Color, line: Color, text_col: Color) -> Control:
	var b := Hub2Box.new()
	b.flat(bg, line, 1.0)
	b.pad(12, 16)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Hub2Ui.hbox(12)
	b.add_child(h)
	var l := Hub2Text.new()
	l.setup(label, Hub2Style.CHAKRA, 700, 12, label_col, 0.14)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var t2 := Hub2Ui.paragraph(text, 14, 1.0, 1.2)
	t2.add_theme_color_override("font_color", text_col)
	t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(t2)
	return b


## Pied : CONTINUER A (à droite).
func _build_footer() -> void:
	var f := Hub2Ui.hbox(12)
	f.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	f.offset_left = Hub2Style.px(48)
	f.offset_right = -Hub2Style.px(48)
	f.offset_bottom = -Hub2Style.px(18)
	f.offset_top = f.offset_bottom - Hub2Style.px(46)
	f.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(f)
	f.add_child(Hub2Ui.spring())
	continue_button = Hub2Button.new()
	continue_button.box.flat(Hub2Style.YELLOW)
	continue_button.box.chamfer(12)
	continue_button.box.pad(0, 28)
	continue_button.custom_minimum_size.y = Hub2Style.px(46)
	var h := Hub2Ui.hbox(12)
	continue_button.add_content(h)
	var ct := Hub2Text.new()
	ct.setup(Lang.t("CONTINUER", "CONTINUE"), Hub2Style.CHAKRA, 700, 18, Hub2Style.INK, 0.14)
	ct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ct)
	var key := Hub2Text.new()
	key.setup(Hub2Input.keycap_text(Hub2Input.keys_of(Hub2Input.ACCEPT), Hub2Input.pads_of(Hub2Input.ACCEPT), Settings.using_pad),
			Hub2Style.MONO, 500, 11, Color(Hub2Style.INK, 0.7))
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(key)
	continue_button.pressed.connect(go_on)
	f.add_child(continue_button)


# --------------------------------------------------------------------------
# Animation (état complet au temps `time`)
# --------------------------------------------------------------------------

## Pose tout l'écran au temps `time` (s depuis l'affichage) : XP, barre,
## pavé, anneaux, éclair, « NIVEAU N ! », lignes, DÉBLOQUÉ.
func apply_time(time: float) -> void:
	if model == null or level_badge == null:
		return
	t = time
	var s := model.state_at(time)
	var up := int(s.levels) > 0
	badge_level.text = str(int(s.level))
	if up:
		level_badge.flat(Hub2Style.YELLOW)
		badge_label.color = Hub2Style.INK
		badge_level.color = Hub2Style.INK
	else:
		level_badge.flat(Hub2Style.YELLOW_TINT, Hub2Style.YELLOW, 2.0)
		badge_label.color = Hub2Style.YELLOW
		badge_level.color = Hub2Style.YELLOW
	xp_line.text = Hub2RecapModel.xp_line(s, model.xp_start + int(s.gained))
	gained_text.text = "+%s XP" % Hub2Style.num(int(s.gained))
	bar_color = Hub2Style.TEAL if up else Hub2Style.YELLOW
	bar_pct = float(s.pct)
	bar_track.queue_redraw()
	# Dernier passage de niveau commencé : pop, anneaux, éclair, texte.
	var last := -1.0
	var last_lvl := 0
	for u in _ups:
		if time >= float(u[1]):
			last = float(u[1])
			last_lvl = int(u[0])
	var dt := time - last if last >= 0.0 else -1.0
	level_badge.scale = Vector2.ONE * (pop_scale(dt) if dt >= 0.0 else 1.0)
	_ring_dt = dt
	rings.queue_redraw()
	var fa := flash_alpha(dt) if dt >= 0.0 else 0.0
	flash.visible = fa > 0.001
	flash.modulate.a = fa
	var ts := level_text_state(dt) if dt >= 0.0 else {"opacity": 0.0}
	level_text.visible = float(ts.opacity) > 0.001
	level_glow.visible = level_text.visible
	if level_text.visible:
		level_text.text = Lang.t("NIVEAU %d !", "LEVEL %d!") % last_lvl
		level_text.modulate.a = float(ts.opacity)
		level_glow.modulate.a = float(ts.opacity)
		level_text.tracking = float(ts.tracking)
		level_text.scale = Vector2.ONE * float(ts.scale)
		level_text.position.y = _level_y + Hub2Style.px(float(ts.y))
	# Lignes qui entrent (rowIn : 0,4 s, ease-out, -12 px -> 0).
	for rn in row_nodes:
		var c: Control = rn[0]
		var k := row_in(time - float(rn[1]))
		c.modulate.a = k
		_slide(c, (1.0 - k) * -Hub2Style.px(12))
	# DÉBLOQUÉ : après le passage de niveau, quand l'XP a fait 75 %.
	if unlocked_box:
		var from := -1.0
		if not _ups.is_empty():
			from = maxf(float(_ups[0][1]), Hub2RecapModel.XP_DELAY + 0.75 * Hub2RecapModel.XP_DURATION + 0.0001)
		var on := from >= 0.0 and time >= from
		var k2 := row_in(time - from) if on else 0.0
		unlocked_box.modulate.a = k2
		_slide(unlocked_box, (1.0 - k2) * -Hub2Style.px(12))


## Décalage horizontal (transform: translateX) d'un élément posé par un
## conteneur : seulement au dessin (transformation de son élément de
## canevas), la mise en page ne bouge pas ; un nouveau placement par le
## conteneur rend la position exacte (décalage 0 en fin d'animation).
static func _slide(c: Control, dx: float) -> void:
	RenderingServer.canvas_item_set_transform(c.get_canvas_item(), Transform2D(0.0, c.position + Vector2(dx, 0.0)))


var _ring_dt := -1.0
## Barre d'XP : remplissage (0..1) et couleur (jaune ; turquoise après un
## passage de niveau).
var bar_pct := 0.0
var bar_color := Hub2Style.YELLOW


## Barre (14 px, piste rgba(255, 255, 255, 0.1), overflow: hidden) :
## remplissage et sa lueur (box-shadow: 0 0 14px, couleur à 0.6 / 0.7),
## visible dans la piste après le bout de la barre.
func _draw_bar() -> void:
	var s := bar_track.size
	bar_track.draw_rect(Rect2(Vector2.ZERO, s), Hub2Style.white_a(0.1))
	var w := roundf(s.x * bar_pct)
	if w <= 0.0:
		return
	var glow_a := 0.7 if bar_color == Hub2Style.TEAL else 0.6
	var g := Hub2Style.px(14)
	var steps := 8
	for i in steps:
		var x0 := w + g * i / steps
		var x1 := minf(w + g * (i + 1) / steps, s.x)
		if x0 >= s.x:
			break
		var a := glow_a * 0.5 * (1.0 - (i + 0.5) / steps)
		bar_track.draw_rect(Rect2(x0, 0, x1 - x0, s.y), Color(bar_color, a))
	bar_track.draw_rect(Rect2(0, 0, w, s.y), bar_color)


func _draw_rings() -> void:
	if _ring_dt < 0.0:
		return
	var c := rings.size * 0.5
	var w := Hub2Style.px(2)
	for i in 2:
		var st := ring_state(i, _ring_dt)
		var sc: float = st[0]
		var a: float = st[1]
		if a <= 0.001:
			continue
		var col := Color(Hub2Style.TEAL if i == 1 else Hub2Style.YELLOW, a)
		# transform: scale autour du centre du pavé (transform-origin: 50 % 50 %),
		# liseré compris, comme le CSS.
		rings.draw_set_transform(c, 0.0, Vector2(sc, sc))
		var r := Rect2(-c, rings.size)
		rings.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), col)
		rings.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), col)
		rings.draw_rect(Rect2(r.position.x, r.position.y + w, w, r.size.y - 2.0 * w), col)
		rings.draw_rect(Rect2(r.end.x - w, r.position.y + w, w, r.size.y - 2.0 * w), col)
	rings.draw_set_transform(Vector2.ZERO)


# --------------------------------------------------------------------------
# Courbes des @keyframes (pures, testées)
# --------------------------------------------------------------------------

## lvlPop (0,7 s, cubic-bezier(.2, 1.6, .4, 1) par segment) : 1 -> 1,45 (35 %)
## -> 1 ; `dt` : temps depuis le passage de niveau.
static func pop_scale(dt: float) -> float:
	if dt < 0.0 or dt >= POP_TIME:
		return 1.0
	var p := dt / POP_TIME
	if p < 0.35:
		return lerpf(1.0, 1.45, Hub2Style.cubic_bezier(p / 0.35, 0.2, 1.6, 0.4, 1.0))
	return lerpf(1.45, 1.0, Hub2Style.cubic_bezier((p - 0.35) / 0.65, 0.2, 1.6, 0.4, 1.0))


## lvlRing (1,1 s, ease-out, forwards ; anneau b : 0,18 s plus tard) :
## [échelle 1 -> 3,2, opacité 1 -> 0] de l'anneau `i` (0 jaune, 1 turquoise)
## ; [1, 0] hors de son animation.
static func ring_state(i: int, dt: float) -> Array:
	var d := dt - (RING_B_DELAY if i == 1 else 0.0)
	if dt < 0.0 or d < 0.0 or d > RING_TIME:
		return [1.0, 0.0]
	var e := Hub2Style.ease_out(d / RING_TIME)
	return [lerpf(1.0, 3.2, e), lerpf(1.0, 0.0, e)]


## Rectangle de l'anneau `i` dans le repère du panneau (tests : centré sur
## le pavé du niveau).
func ring_rect(i: int) -> Rect2:
	var st := ring_state(i, _ring_dt)
	var g := rings.get_global_rect()
	var s: Vector2 = g.size * float(st[0])
	var xf := get_global_transform().affine_inverse()
	return Rect2(xf * (g.get_center() - s * 0.5), s)


## lvlFlash (0,9 s, ease-out) : opacité 0,55 -> 0.
static func flash_alpha(dt: float) -> float:
	if dt < 0.0 or dt >= FLASH_TIME:
		return 0.0
	return lerpf(0.55, 0.0, Hub2Style.ease_out(dt / FLASH_TIME))


## lvlText (2,2 s, ease-out par segment) : {opacity, y (px), scale, tracking
## (em)} ; 0 % : 0, 14, 0,9, 0,6 ; 25 % : 1, 0, 1, 0,22 ; 80 % : opacité 1 ;
## 100 % : opacité 0 (espacement ramené à « normal »).
static func level_text_state(dt: float) -> Dictionary:
	if dt < 0.0 or dt >= TEXT_TIME:
		return {"opacity": 0.0, "y": 0.0, "scale": 1.0, "tracking": 0.0}
	var p := dt / TEXT_TIME
	var out := {}
	if p < 0.25:
		var e := Hub2Style.ease_out(p / 0.25)
		out = {"opacity": e, "y": lerpf(14.0, 0.0, e), "scale": lerpf(0.9, 1.0, e), "tracking": lerpf(0.6, 0.22, e)}
	else:
		var e2 := Hub2Style.ease_out((p - 0.25) / 0.75)
		var op := 1.0
		if p >= 0.8:
			op = lerpf(1.0, 0.0, Hub2Style.ease_out((p - 0.8) / 0.2))
		out = {"opacity": op, "y": 0.0, "scale": 1.0, "tracking": lerpf(0.22, 0.0, e2)}
	return out


## rowIn (0,4 s, ease-out) : 0 -> 1 ; `dt` : temps depuis le début de la ligne.
static func row_in(dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if dt >= ROW_TIME:
		return 1.0
	return Hub2Style.ease_out(dt / ROW_TIME)
