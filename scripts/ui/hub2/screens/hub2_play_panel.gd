class_name Hub2PlayPanel
extends Hub2Panel
## JOUER du hub v2 (docs/hub_v2/Partie.dc.html en solo, PartieCoop.dc.html
## pour le salon coop ; logique reprise de l'ancien onglet PARTIE :
## HubPlayPanel, HubPlayLobby, HubLoadoutPanel).
##
## Trois vues, qui suivent l'état du réseau (sync) :
##   - SOLO (Partie.dc.html) : à gauche SOLO / COOP, DÉFI DE LA SEMAINE
##     (carte turquoise biseautée : WeeklyChallenge, temps restant, objectif,
##     récompense), CARTES DU JEU, puis CARTES PERSONNALISÉES « POUR LE FUN »
##     (cartes de l'éditeur, aucune progression : ProgressGate) ; à droite
##     l'aperçu de la carte (vue en jeu pré-rendue pour les cartes du jeu,
##     plan pour les cartes perso), son nom (40 px) et ses vagues spéciales et
##     de boss, ÉQUIPEMENT (rendus des armes de départ, X · MODIFIER : choix
##     des armes de départ), LANCER ;
##   - COOP sans salon (pas de maquette, même style) : nom, HÉBERGER (port),
##     REJOINDRE (adresse « IP:port ») ; erreurs de connexion sur place ;
##   - SALON (PartieCoop.dc.html, Hub2LobbyView) dès que la session est
##     ouverte ; le panneau reste en vie pendant qu'on parcourt les onglets.
## Voile 0.35 (solo) ou 0.45 (coop).

const SOLO := "solo"
const COOP := "coop"
const LOBBY := "lobby"
## Identifiant de la carte « défi de la semaine » dans la sélection.
const WEEKLY := HubPlayWeekly.ROW_ID
## Invite propre : armes de départ (X).
const PROMPT_LOADOUT := "loadout"

## Dernier choix SOLO / COOP (retour au hub, autre visite).
static var last_view := SOLO

var view := ""
var _root: Control
## SOLO / COOP.
var solo_tab: Hub2Button
var coop_tab: Hub2Button
## SOLO : défi, lignes des cartes (id -> Hub2Button), carte choisie.
var weekly_button: Hub2Button
var weekly: WeeklyChallenge
var map_buttons: Dictionary = {}
var selected := ""
var launch_button: Hub2Button
var modify_button: Hub2Button
var preview: Hub2Render
var preview_title: Hub2Text
var preview_waves: HFlowContainer
var preview_fun: Control
## « APERÇU EN PRÉPARATION » et rendu des vues en jeu des cartes perso.
var preview_loading: Control
var preview_bg: ColorRect
var shots: Hub2MapShot
var equipment_box: VBoxContainer
var equipment_right: Hub2Text
## COOP : champs, boutons, état.
var name_edit: LineEdit
var port_edit: LineEdit
var address_edit: LineEdit
var host_button: Hub2Button
var join_button: Hub2Button
var status_label: Label
var _error := ""
var _dots_t := 0.0
## SALON.
var lobby: Hub2LobbyView
## Fenêtre ouverte (armes de départ, changer de carte).
var modal: Hub2Modal
var _leaving := false


func build() -> void:
	shots = Hub2MapShot.new()
	shots.name = "MapShots"
	add_child(shots)
	shots.ready_shot.connect(_on_shot)
	Net.players_changed.connect(_on_net_changed)
	Net.joined_server.connect(sync)
	_publish_card()
	sync()


func _exit_tree() -> void:
	for pair in [[Net.players_changed, _on_net_changed], [Net.joined_server, sync]]:
		var s: Signal = pair[0]
		if s.is_connected(pair[1]):
			s.disconnect(pair[1])


## Session ouverte et salon affichable (hôte, ou invité accepté).
static func in_lobby() -> bool:
	return Net.is_online() and GameState.state == GameState.State.LOBBY


## Invité en cours de connexion ?
static func connecting() -> bool:
	return Net.mode == Net.Mode.CLIENT and GameState.state == GameState.State.CONNECTING


func sync() -> void:
	var want := LOBBY if in_lobby() else (COOP if last_view == COOP or Net.mode == Net.Mode.CLIENT else SOLO)
	if want != view:
		_show(want)
	elif view == COOP:
		_refresh_coop_state()


func _on_net_changed() -> void:
	sync()


func _show(v: String) -> void:
	var had_focus := _has_focus()
	close_modal()
	view = v
	if _root:
		remove_child(_root)
		_root.queue_free()
	_root = Control.new()
	_root.name = "View"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_main(_root)
	map_buttons.clear()
	lobby = null
	weekly_button = null
	launch_button = null
	modify_button = null
	match v:
		LOBBY:
			# <main> du salon : top 92 (maquette PartieCoop).
			_root.offset_top = Hub2Style.px(92)
			lobby = Hub2LobbyView.new(self)
			lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
			_root.add_child(lobby)
		COOP:
			_build_coop()
		_:
			_build_solo()
	if hub:
		# Voile de la vue (salon : 0.45).
		if hub.get("current_id") == screen_id and hub.get("veil"):
			(hub.get("veil") as Hub2Veil).spec = veil()
		hub.refresh_prompts()
		if had_focus or hub.get("current_id") == screen_id:
			var f := first_focus()
			if f:
				hub.focus_later(f)


func _has_focus() -> bool:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return f != null and is_ancestor_of(f)


func refresh() -> void:
	_publish_card()
	if view == SOLO:
		_fill_equipment()
		if weekly_button:
			_fill_weekly(weekly_button)
	elif view == LOBBY and lobby:
		lobby.refresh_profile()


func _publish_card() -> void:
	var pr := profile()
	if pr:
		Net.set_lobby_card(pr.level(), pr.starting_weapons)


func shown() -> void:
	sync()
	if view == LOBBY and lobby:
		lobby.on_shown()


func hidden() -> void:
	close_modal()


func veil() -> Dictionary:
	return {"color": Hub2Style.shade(0.45 if view == LOBBY else 0.35)}


func first_focus() -> Control:
	if modal:
		return null
	match view:
		LOBBY:
			return lobby.first_focus() if lobby else null
		COOP:
			return join_button if Net.mode == Net.Mode.CLIENT else host_button
	if selected != "" and map_buttons.has(selected):
		return map_buttons[selected]
	if selected == WEEKLY and weekly_button:
		return weekly_button
	return launch_button


func prompts() -> Array:
	if modal:
		return [[Hub2Input.ACCEPT, Lang.t("Choisir", "Select")], [Hub2Input.BACK, Lang.t("Fermer", "Close")]]
	match view:
		LOBBY:
			return lobby.prompts() if lobby else []
		COOP:
			return [[Hub2Input.ACCEPT, Lang.t("Choisir", "Select")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]
	var out := [[Hub2Input.ACCEPT, Lang.t("Lancer", "Launch")]]
	if selected != WEEKLY:
		out.append(loadout_prompt())
	out.append([Hub2Input.BACK, Lang.t("Retour", "Back")])
	return out


## Invite X · ARMES DE DÉPART (X au clavier et à la manette).
static func loadout_prompt() -> Array:
	return [PROMPT_LOADOUT, Lang.t("Armes de départ", "Starting weapons"),
		PackedStringArray([Hub2Input.physical_key_name(KEY_X)]), [JOY_BUTTON_X]]


func help() -> String:
	match view:
		LOBBY:
			return Lang.t("Chacun garde sa progression : XP, butin et contrats vont dans son propre profil.",
				"Everyone keeps their own progression: XP, loot and contracts go to their own profile.")
		COOP:
			return Lang.t("Coop de 2 à 4 survivants par adresse IP : héberge un salon ou rejoins celui d’un ami.",
				"Co-op for 2 to 4 survivors over IP address: host a lobby or join a friend's.")
	return Lang.t("Les armes de ton arsenal se construisent en partie, à la station, contre de la ferraille.",
			"Your arsenal weapons are built in a game, at the station, for scrap.")


func back() -> bool:
	if modal:
		close_modal()
		return true
	if view == LOBBY and lobby:
		return lobby.back()
	return false


func handle_input(event: InputEvent) -> bool:
	if modal:
		return false
	if _typing():
		return false
	if _is_x(event):
		on_prompt(PROMPT_LOADOUT)
		return true
	if view == LOBBY and lobby:
		return lobby.handle_input(event)
	return false


func _typing() -> bool:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return f is LineEdit


static func _is_x(event: InputEvent) -> bool:
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed and jb.button_index == JOY_BUTTON_X:
		return true
	return Hub2Input.is_key(event, KEY_X)


func on_prompt(id: String) -> void:
	match id:
		PROMPT_LOADOUT:
			if view == SOLO and selected != WEEKLY or view == LOBBY:
				open_loadout()
		_:
			if lobby:
				lobby.on_prompt(id)


# --------------------------------------------------------------------------
# SOLO / COOP
# --------------------------------------------------------------------------

## Onglets SOLO / COOP (role=tablist) : fond rgba(10, 11, 13, 0.62), liseré
## 1 px, deux cases de 40 px ; choisie : fond #F2F0EA, texte #0B0B0C 700,
## sinon rgba(242, 240, 234, 0.6) 600 ; Chakra Petch 15 px, 0.14em.
func mode_tabs(width := -1.0) -> Hub2Box:
	var frame := Hub2Box.new()
	frame.flat(Hub2Style.GLASS, Hub2Style.LINE, 1.0)
	frame.pad(1)
	if width > 0.0:
		frame.custom_minimum_size.x = Hub2Style.px(width)
		frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := Hub2Ui.hbox(0)
	frame.add_child(h)
	var cur := COOP if view == LOBBY or view == COOP else SOLO
	solo_tab = _tab("SOLO", cur == SOLO, SOLO)
	coop_tab = _tab("COOP", cur == COOP, COOP)
	h.add_child(solo_tab)
	h.add_child(coop_tab)
	solo_tab.hint = Lang.t("Partir seul : choisir une carte et lancer.", "Head out alone: pick a map and start.")
	coop_tab.hint = Lang.t("Coopération de 2 à 4 survivants, par adresse IP : héberger ou rejoindre.",
			"Co-op for 2 to 4 survivors, over IP address: host or join.")
	return frame


func _tab(text: String, on: bool, v: String) -> Hub2Button:
	var b := Hub2Button.new()
	b.box.flat(Hub2Style.TEXT if on else Color(0, 0, 0, 0))
	b.custom_minimum_size.y = Hub2Style.px(38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, 700 if on else 600, 15, Hub2Style.INK if on else Hub2Style.text_a(0.6), 0.14)
	t.align = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_content(t)
	b.pressed.connect(choose.bind(v))
	return b


## SOLO ou COOP choisi (un invité en cours de connexion reste en COOP ; un
## salon ouvert reste affiché : QUITTER LE SALON d'abord).
func choose(v: String) -> void:
	if v == SOLO and (Net.mode == Net.Mode.CLIENT or in_lobby()):
		if in_lobby() and hub:
			hub.set_hint(Lang.t("Quitte d’abord le salon pour jouer seul.", "Leave the lobby first to play alone."))
		return
	last_view = v
	_error = ""
	if (v == SOLO) != (view == SOLO):
		_show(v)
		if hub:
			hub.focus_later(solo_tab if v == SOLO else coop_tab)


# --------------------------------------------------------------------------
# Vue SOLO (Partie.dc.html)
# --------------------------------------------------------------------------

func _build_solo() -> void:
	var row := Hub2Ui.hbox(20)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(row)
	# Colonne des choix : 380 px, écart 14.
	var left := Hub2Ui.vbox(14)
	left.custom_minimum_size.x = Hub2Style.px(380)
	row.add_child(left)
	left.add_child(mode_tabs())
	weekly = HubPlayWeekly.current()
	weekly_button = Hub2Button.new()
	weekly_button.pressed.connect(func(): _row_pressed(WEEKLY))
	weekly_button.focus_entered.connect(func(): select_map(WEEKLY))
	_fill_weekly(weekly_button)
	left.add_child(weekly_button)
	var lists := Hub2PlayData.map_lists()
	var game_label := Hub2Ui.section(Lang.t("CARTES DU JEU", "GAME MAPS"))
	var gm := MarginContainer.new()
	gm.add_theme_constant_override("margin_top", int(Hub2Style.px(4)))
	gm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gm.add_child(game_label)
	left.add_child(gm)
	var game_rows := Hub2Ui.vbox(6)
	left.add_child(game_rows)
	for m in lists.game:
		game_rows.add_child(_map_row(m))
	left.add_child(_custom_section(lists.custom))

	# Aperçu et lancement.
	var right := Hub2Ui.vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(_preview_box())
	var bottom := Hub2Ui.hbox(14)
	right.add_child(bottom)
	bottom.add_child(_equipment())
	launch_button = launch_card(220.0)
	launch_button.pressed.connect(launch_selected)
	bottom.add_child(launch_button)
	var start := Settings.last_map if map_buttons.has(Settings.last_map) else ""
	if start == "" and not lists.game.is_empty():
		start = String(lists.game[0].id)
	if start != "":
		select_map(start)
	elif weekly:
		select_map(WEEKLY)


## Carte du défi de la semaine (bouton biseauté turquoise de la maquette).
func _fill_weekly(b: Hub2Button) -> void:
	for c in b.box.get_children():
		b.box.remove_child(c)
		c.queue_free()
	var on := selected == WEEKLY
	b.box.glass(Hub2Style.teal_a(0.14 if on else 0.08), Hub2Style.TEAL if on else Hub2Style.teal_a(0.45), 1.0)
	b.box.chamfer(14, 0)
	b.box.pad(14, 16)
	var d := Hub2PlayData.weekly_card(weekly, profile())
	var v := Hub2Ui.vbox(4)
	b.add_content(v)
	var top := Hub2Ui.hbox(8)
	v.add_child(top)
	var k := Hub2Text.new()
	k.setup(String(d.kicker), Hub2Style.CHAKRA, 700, 12, Hub2Style.TEAL, 0.18)
	top.add_child(k)
	top.add_child(Hub2Ui.spring())
	var tl := Hub2Text.new()
	tl.setup(String(d.left), Hub2Style.MONO, 500, 12, Hub2Style.text_a(0.6))
	top.add_child(tl)
	var t := Hub2Text.new()
	t.setup(String(d.title), Hub2Style.CHAKRA, 700, 19, Hub2Style.TEXT)
	v.add_child(t)
	var line := Hub2Style.label(String(d.line), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.65))
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.clip_text = true
	line.custom_minimum_size.x = Hub2Style.px(60)
	v.add_child(line)
	b.hint = HubPlayWeekly.hint(weekly)
	b.disabled = weekly == null


## Ligne d'une carte (bouton de la maquette : padding 10 14, nom 16 px 700,
## sous-titre 12 px, record en JetBrains Mono 12 px).
func _map_row(m: Dictionary) -> Hub2Button:
	var b := Hub2Button.new()
	var id := String(m.id)
	b.box.pad(10, 14)
	var h := Hub2Ui.hbox(12)
	b.add_content(h)
	var v := Hub2Ui.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := Hub2Text.new()
	t.setup(String(m.name), Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.03)
	v.add_child(t)
	v.add_child(Hub2Style.label(String(m.sub), Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55)))
	var best := Hub2Text.new()
	best.setup(String(m.best), Hub2Style.MONO, 500, 12, Hub2Style.text_a(0.55))
	best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(best)
	_set_row_style(b, false)
	b.hint = Lang.t("Carte perso (éditeur) : pour le fun, aucune progression.", "Custom map (editor): just for fun, no progression.") \
			if m.custom else ""  # carte du jeu : aide de l'écran (maquette)
	b.focus_entered.connect(func(): select_map(id))
	b.pressed.connect(func(): _row_pressed(id))
	map_buttons[id] = b
	return b


static func _set_row_style(b: Hub2Button, on: bool) -> void:
	b.box.glass(Hub2Style.yellow_a(0.1) if on else Hub2Style.GLASS, Hub2Style.YELLOW if on else Hub2Style.LINE, 1.0)


## CARTES PERSONNALISÉES : liseré haut rgba(255, 255, 255, 0.12), padding-top
## 14, écart 8, « POUR LE FUN », la règle, puis les cartes (défilantes si
## elles dépassent la colonne).
func _custom_section(maps: Array) -> Control:
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override("margin_top", int(Hub2Style.px(6)))
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sec := Hub2Box.new()
	sec.flat(Color(0, 0, 0, 0), Hub2Style.white_a(0.12), 0.0)
	sec.border = Vector4(0, 1, 0, 0)
	sec.pad(14, 0, 0, 0)
	wrap.add_child(sec)
	var v := Hub2Ui.vbox(8)
	sec.add_child(v)
	var head := Hub2Ui.hbox(8)
	v.add_child(head)
	head.add_child(Hub2Ui.section(Lang.t("CARTES PERSONNALISÉES", "CUSTOM MAPS")))
	head.add_child(Hub2Ui.spring())
	head.add_child(Hub2Ui.tag(Lang.t("POUR LE FUN", "JUST FOR FUN"), Color("D7B3FF"), Color("B56CFF")))
	v.add_child(Hub2Ui.paragraph(ProgressGate.rule_text(), 13, 0.6, 1.35))
	if maps.is_empty():
		v.add_child(Hub2Ui.paragraph(Lang.t("Aucune pour l’instant : dessine-en une dans l’éditeur de cartes.",
				"None yet: draw one in the map editor."), 13, 0.45, 1.35))
		return wrap
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.follow_focus = true
	v.add_child(scroll)
	var rows := Hub2Ui.vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for m in maps:
		rows.add_child(_map_row(m))
	return wrap


## Aperçu de la carte : fond rgba(255, 255, 255, 0.03), liseré 1 px, image
## (object-fit: cover), dégradé du bas (rgba(8, 9, 11, 0.9) -> 0), nom 40 px,
## pastilles des vagues.
func _preview_box() -> Control:
	var box := Hub2Box.new()
	box.flat(Hub2Style.white_a(0.03), Hub2Style.LINE, 1.0)
	box.pad(1)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.clip_contents = true
	preview_bg = ColorRect.new()
	preview_bg.color = Hub2Style.shade(0.88)
	preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_bg.visible = false
	box.add_child(preview_bg)
	preview = Hub2Render.new()
	preview.fit = Hub2Render.FIT_COVER
	box.add_child(preview)
	# Bloc du bas (position: absolute; bottom: 0) : dégradé sur tout le bloc,
	# padding 18 20 à l'intérieur.
	var col := Hub2Ui.vbox(0)
	box.add_child(col)
	# « APERÇU EN PRÉPARATION » (carte perso rendue hors écran), en haut à
	# gauche, qui pulse doucement.
	var lm := MarginContainer.new()
	lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in [["left", 20], ["top", 18]]:
		lm.add_theme_constant_override("margin_" + s[0], int(Hub2Style.px(s[1])))
	col.add_child(lm)
	preview_loading = Hub2Ui.tag(Lang.t("APERÇU EN PRÉPARATION…", "PREPARING PREVIEW…"), Hub2Style.text_a(0.75),
			Hub2Style.white_a(0.18), Hub2Style.GLASS_STRONG, 11, 0.16, 4, 10)
	preview_loading.visible = false
	lm.add_child(preview_loading)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var block := MarginContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(block)
	var grad := TextureRect.new()
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad.texture = bottom_gradient()
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	block.add_child(grad)
	var info := MarginContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in [["left", 20], ["right", 20], ["top", 18], ["bottom", 18]]:
		info.add_theme_constant_override("margin_" + s[0], int(Hub2Style.px(s[1])))
	block.add_child(info)
	var v := Hub2Ui.vbox(10)
	info.add_child(v)
	preview_title = Hub2Text.new()
	preview_title.setup("", Hub2Style.CHAKRA, 700, 40, Hub2Style.TEXT, 0.02)
	preview_title.line_height = 40
	v.add_child(preview_title)
	var chips_row := Hub2Ui.hbox(8)
	v.add_child(chips_row)
	preview_waves = HFlowContainer.new()
	preview_waves.add_theme_constant_override("h_separation", int(Hub2Style.px(8)))
	preview_waves.add_theme_constant_override("v_separation", int(Hub2Style.px(8)))
	preview_waves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_waves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_row.add_child(preview_waves)
	preview_fun = Hub2Ui.tag(Lang.t("POUR LE FUN", "JUST FOR FUN"), Color("D7B3FF"), Color("B56CFF"), Hub2Style.GLASS_STRONG)
	preview_fun.visible = false
	chips_row.add_child(preview_fun)
	return box


## linear-gradient(to top, rgba(8, 9, 11, 0.9), rgba(8, 9, 11, 0)).
static func bottom_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Hub2Style.shade(0.9))
	g.set_color(1, Hub2Style.shade(0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 1)
	t.fill_to = Vector2(0, 0)
	t.width = 4
	t.height = 128
	return t


## ÉQUIPEMENT : panneau de verre (padding 14 16, écart 8) : titre, X ·
## MODIFIER (jaune), trois cases.
func _equipment() -> Control:
	var box := Hub2Box.new()
	box.glass()
	box.pad(14, 16)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_box = Hub2Ui.vbox(8)
	box.add_child(equipment_box)
	_fill_equipment()
	return box


func _fill_equipment() -> void:
	if equipment_box == null:
		return
	for c in equipment_box.get_children():
		equipment_box.remove_child(c)
		c.queue_free()
	var head := Hub2Ui.hbox(8)
	equipment_box.add_child(head)
	head.add_child(Hub2Ui.section(Lang.t("ÉQUIPEMENT", "LOADOUT")))
	head.add_child(Hub2Ui.spring())
	var challenge := selected == WEEKLY
	modify_button = Hub2Button.new()
	modify_button.show_focus = true
	var mt := Hub2Text.new()
	var key := Hub2Input.keycap_text(PackedStringArray([Hub2Input.physical_key_name(KEY_X)]), [JOY_BUTTON_X], Settings.using_pad)
	if challenge:
		mt.setup(Lang.t("IMPOSÉ PAR LE DÉFI", "SET BY THE CHALLENGE"), Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.12)
		modify_button.disabled = true
		modify_button.focus_mode = Control.FOCUS_NONE
	else:
		mt.setup("%s · %s" % [key, Lang.t("MODIFIER", "CHANGE")], Hub2Style.CHAKRA, 700, 12, Hub2Style.YELLOW, 0.12)
		modify_button.hint = Lang.t("Choisir ses armes de départ : au moins une, au plus trois.",
				"Choose your starting weapons: at least one, at most three.")
		modify_button.pressed.connect(open_loadout)
		modify_button.focus_mode = Control.FOCUS_NONE
	equipment_right = mt
	modify_button.add_content(mt)
	head.add_child(modify_button)
	var sel := WeeklyChallenge.starting_ids() if challenge else (profile().starting_weapons if profile() else BaseWeapons.default_selection())
	equipment_box.add_child(Hub2Equipment.slots_row(sel, true, 8))


## Bouton LANCER : fond #F5C542, biseaux 16 px, padding 0 22, LANCER Chakra
## Petch 26 px 700 0.12em ; `sub` : seconde ligne (salon : « 3 joueurs prêts
## sur 3 », 13 px 600).
func launch_card(width: float, sub := "") -> Hub2Button:
	var b := Hub2Button.new()
	b.box.flat(Hub2Style.YELLOW)
	b.box.chamfer(16)
	b.box.pad(0, 22)
	b.custom_minimum_size.x = Hub2Style.px(width)
	var v := Hub2Ui.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_content(v)
	var t := Hub2Text.new()
	t.setup(Lang.t("LANCER", "LAUNCH"), Hub2Style.CHAKRA, 700, 26, Hub2Style.INK, 0.12)
	v.add_child(t)
	if sub != "":
		v.add_child(Hub2Style.label(sub, Hub2Style.BARLOW, 600, 13, Hub2Style.INK))
	return b


## Choisit la carte `id` (ou le défi : WEEKLY) : ligne surlignée, aperçu.
func select_map(id: String) -> void:
	if id == WEEKLY and weekly == null:
		return
	if id != WEEKLY and not map_buttons.has(id):
		return
	var changed := id != selected
	selected = id
	for k in map_buttons:
		_set_row_style(map_buttons[k], k == id)
	if weekly_button:
		_fill_weekly(weekly_button)
	var map_id := weekly.map_id if id == WEEKLY else id
	var def := HubPlayView.def_of(map_id)
	var pic := picture_for(map_id)
	apply_picture(preview, pic)
	# Plan : sur un fond sombre (proportions réelles, centré).
	preview_bg.visible = not pic[1]
	preview.modulate.a = 1.0
	# Carte perso sans vue en jeu : rendue hors écran la première fois (plan
	# net en attendant, « APERÇU EN PRÉPARATION »).
	preview_loading.visible = ProgressGate.is_custom_map(map_id) and not pic[1] and shots != null and shots.request(map_id)
	preview_title.text = Hub2PlayData.map_title(def)
	Hub2Ui.fill_waves(preview_waves, def)
	preview_fun.visible = ProgressGate.is_custom_map(map_id)
	if changed:
		_fill_equipment()
		if hub:
			hub.refresh_prompts()
	if launch_button:
		launch_button.hint = Lang.t("Évacue à la manche %d ou plus pour la récompense de la semaine.", "Evacuate at round %d or later for this week's reward.") \
				% weekly.goal_round if id == WEEKLY else (Lang.t("Carte perso : pour le fun, rien n’est gardé.", "Custom map: just for fun, nothing is kept.")
				if ProgressGate.is_custom_map(id) else Lang.t("La partie ne se termine jamais d’elle-même : évacue après une vague spéciale.",
				"The game never ends on its own: evacuate after a special wave."))


## Image d'aperçu d'une carte : [texture, vue en jeu (cover) ?]. Cartes du
## jeu : vue pré-rendue (assets/ui/hub/maps/<id>.png, tools/map_shots.sh) ;
## sinon (cartes perso) le plan (MapPreview).
static func map_picture(map_id: String) -> Array:
	var shot := "res://assets/ui/hub/maps/%s.png" % map_id
	if not ProgressGate.is_custom_map(map_id) and ResourceLoader.exists(shot):
		return [load(shot) as Texture2D, true]
	return [MapPreview.texture(map_id), false]


## Comme map_picture, avec la vue en jeu d'une carte perso si elle est déjà
## rendue (Hub2MapShot).
func picture_for(map_id: String) -> Array:
	if ProgressGate.is_custom_map(map_id) and shots:
		var t := shots.cached(map_id)
		if t:
			return [t, true]
	return map_picture(map_id)


## Pose l'image `pic` ([texture, vue en jeu]) : vue en jeu en cover ; plan
## agrandi d'un nombre entier de fois, centré sur le fond sombre, pixels nets.
static func apply_picture(r: Hub2Render, pic: Array) -> void:
	r.texture = pic[0]
	r.fit = Hub2Render.FIT_COVER if pic[1] else Hub2Render.FIT_INTEGER
	r.texture_filter = HubRenders.FILTER if pic[1] else CanvasItem.TEXTURE_FILTER_NEAREST


## Vue en jeu d'une carte perso prête : montrée en fondu si elle est choisie.
func _on_shot(map_id: String, tex: Texture2D) -> void:
	if view != SOLO or preview == null:
		return
	var cur := weekly.map_id if selected == WEEKLY and weekly else selected
	if cur != map_id:
		return
	preview_loading.visible = false
	apply_picture(preview, [tex, true])
	preview_bg.visible = false
	preview.modulate.a = 0.0
	create_tween().tween_property(preview, "modulate:a", 1.0, 0.35)


func _row_pressed(id: String) -> void:
	if id == selected:
		Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
		launch_selected()
	else:
		select_map(id)


## LANCER : même chemin que l'ancien onglet PARTIE (fondu cinématique puis
## Router.start_solo ; carte mémorisée dans Settings.last_map ; défi : sa
## carte et sa clé).
func launch_selected() -> void:
	if _leaving or selected == "" or hub == null or hub.menu == null:
		return
	if selected == WEEKLY:
		if weekly == null:
			return
		_leaving = true
		var ch := weekly
		hub.menu.launch(func(): Router.start_solo(ch.map_id, ch.key))
		return
	_leaving = true
	var id := selected
	Settings.last_map = id
	Settings.save_settings()
	hub.menu.launch(func(): Router.start_solo(id))


# --------------------------------------------------------------------------
# Armes de départ (X · MODIFIER ; règles de l'ancien onglet DÉPART)
# --------------------------------------------------------------------------

func open_loadout() -> void:
	if modal or profile() == null:
		return
	if view == SOLO and selected == WEEKLY:
		return
	modal = Hub2Modal.new()
	modal.setup(Lang.t("ARMES DE DÉPART", "STARTING WEAPONS"),
			Lang.t("Au moins une, au plus trois. Les armes de base sont données à tous.",
				"At least one, at most three. Base weapons are given to everyone."), 460)
	modal.closed.connect(_on_modal_closed)
	add_child(modal)
	_fill_loadout()


func _fill_loadout() -> void:
	if modal == null:
		return
	var keep := -1
	var f := get_viewport().gui_get_focus_owner() if get_viewport() else null
	for c in modal.body.get_children():
		if c == f:
			keep = c.get_index()
		modal.body.remove_child(c)
		c.queue_free()
	var sel := profile().starting_weapons
	modal.body.add_child(Hub2Equipment.slots_row(sel, true, 8))
	var first: Control = null
	var ids := BaseWeapons.ids()
	for i in ids.size():
		var id := ids[i]
		var on := id in sel
		var b := modal.add_row(Hub2Equipment.weapon_name(id), HubGear.weapon_class(id),
				Lang.t("AU DÉPART", "EQUIPPED") if on else "", on)
		b.hint = Lang.t("Retirer cette arme du départ.", "Remove this weapon from the loadout.") if on \
				else Lang.t("Ajouter cette arme au départ.", "Add this weapon to the loadout.")
		b.pressed.connect(toggle_weapon.bind(id))
		if first == null:
			first = b
	if hub:
		var target: Control = modal.body.get_child(keep) if keep > 0 and keep < modal.body.get_child_count() else first
		hub.focus_later(target)
		hub.refresh_prompts()


## Ajoute ou retire l'arme de base `id` des armes de départ (enregistré) ;
## faux si refusé (dernière arme, trois emplacements pris).
func toggle_weapon(id: String) -> bool:
	var r := Hub2Equipment.toggled(profile().starting_weapons, id)
	if (r[0] as PackedStringArray).is_empty():
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		if hub and String(r[1]) != "":
			hub.set_hint(String(r[1]))
		return false
	if not profile().set_starting_weapons(r[0]):
		return false
	Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
	hub.save_profile()
	_fill_loadout()
	return true


func close_modal() -> void:
	if modal:
		var m := modal
		modal = null
		m.close()


func _on_modal_closed() -> void:
	modal = null
	if not is_inside_tree() or hub == null:
		return
	hub.refresh_prompts()
	hub.set_hint("")
	var f := first_focus()
	if view == SOLO and launch_button:
		f = map_buttons.get(selected, launch_button) if selected != WEEKLY else weekly_button
	if f:
		hub.focus_later(f)


# --------------------------------------------------------------------------
# Vue COOP sans salon : héberger / rejoindre (pas de maquette)
# --------------------------------------------------------------------------

func _build_coop() -> void:
	var row := Hub2Ui.hbox(20)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(row)
	var left := Hub2Ui.vbox(14)
	left.custom_minimum_size.x = Hub2Style.px(380)
	row.add_child(left)
	left.add_child(mode_tabs())
	# Nom du survivant.
	var who := _card(left)
	who.add_child(Hub2Ui.section(Lang.t("TON NOM", "YOUR NAME")))
	name_edit = Hub2Ui.line_edit(Settings.player_name, Lang.t("Survivant", "Survivor"), 16)
	who.add_child(name_edit)
	# Héberger.
	var host := _card(left)
	host.add_child(Hub2Ui.section(Lang.t("HÉBERGER UN SALON", "HOST A LOBBY")))
	host.add_child(Hub2Ui.paragraph(Lang.t("Tes amis te rejoignent avec ton adresse : %s.", "Your friends join you with your address: %s.")
			% Hub2PlayData.address_text(local_ip(), Settings.last_port), 13, 0.6))
	var hr := Hub2Ui.hbox(8)
	host.add_child(hr)
	var pl := Hub2Style.label(Lang.t("Port", "Port"), Hub2Style.BARLOW, 500, 13, Hub2Style.text_a(0.6))
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(pl)
	port_edit = Hub2Ui.line_edit(str(Settings.last_port), str(Net.DEFAULT_PORT), 5)
	port_edit.custom_minimum_size.x = Hub2Style.px(90)
	port_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hr.add_child(port_edit)
	hr.add_child(Hub2Ui.spring())
	host_button = Hub2Ui.outline_button(Lang.t("HÉBERGER", "HOST"), Hub2Style.INK, Color(0, 0, 0, 0), Hub2Style.YELLOW, 18, 14)
	host_button.box.chamfer(10)
	host_button.hint = Lang.t("Ouvrir un salon : les autres te rejoignent avec ton adresse IP.", "Open a lobby: the others join you with your IP address.")
	host_button.pressed.connect(host_lobby)
	hr.add_child(host_button)
	# Rejoindre.
	var join := _card(left)
	join.add_child(Hub2Ui.section(Lang.t("REJOINDRE UN SALON", "JOIN A LOBBY")))
	address_edit = Hub2Ui.line_edit(Hub2PlayData.address_text(Settings.last_ip, Settings.last_port) if Settings.last_ip != "" else "",
			"192.168.1.24:7777", 21)
	join.add_child(address_edit)
	join_button = Hub2Ui.outline_button(Lang.t("REJOINDRE", "JOIN"), Hub2Style.TEXT, Hub2Style.text_a(0.4), Hub2Style.shade(0.5))
	join_button.hint = Lang.t("Entrer l’adresse de l’hôte (IP:port).", "Enter the host's address (IP:port).")
	join_button.pressed.connect(join_or_cancel)
	join.add_child(join_button)
	status_label = Hub2Ui.paragraph("", 13, 0.6)
	left.add_child(status_label)
	address_edit.text_submitted.connect(func(_t): join_or_cancel())
	port_edit.text_submitted.connect(func(_t): host_lobby())
	name_edit.text_submitted.connect(func(_t): hub.focus_later(host_button))
	for e: LineEdit in [name_edit, port_edit, address_edit]:
		e.focus_entered.connect(func():
			if hub:
				hub.set_hint(Lang.t("Entrée : valider.", "Enter: confirm.")))
	# À droite : règles de la coop.
	var right := Hub2Box.new()
	right.glass()
	right.pad(24, 26)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(right)
	var rv := Hub2Ui.vbox(12)
	right.add_child(rv)
	var t := Hub2Text.new()
	t.setup(Lang.t("COOPÉRATION", "CO-OP"), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT, 0.08)
	rv.add_child(t)
	for line in [
			Lang.t("De 2 à 4 survivants, par adresse IP : sur le même réseau, ou par Internet si l’hôte a ouvert son port.",
				"2 to 4 survivors over IP address: on the same network, or over the Internet if the host opened their port."),
			Lang.t("L’hôte choisit la carte (ou le défi de la semaine) ; ses cartes perso sont envoyées et vérifiées chez chacun.",
				"The host picks the map (or the weekly challenge); their custom maps are sent and checked on each computer."),
			Lang.t("Chacun garde sa progression : XP, butin et contrats vont dans son propre profil.",
				"Everyone keeps their own progression: XP, loot and contracts go to their own profile."),
			Lang.t("Le salon reste ouvert pendant que tu parcours les autres onglets.",
				"The lobby stays open while you browse the other tabs.")]:
		rv.add_child(Hub2Ui.paragraph(line, 15, 0.75))
	_refresh_coop_state()


## Panneau de verre de la vue COOP (padding 14 16, écart 8) : son VBox.
func _card(parent: Control) -> VBoxContainer:
	var b := Hub2Box.new()
	b.glass()
	b.pad(14, 16)
	parent.add_child(b)
	var v := Hub2Ui.vbox(8)
	b.add_child(v)
	return v


func _refresh_coop_state() -> void:
	if view != COOP or join_button == null:
		return
	var busy := connecting()
	Hub2Ui.button_text(join_button).text = Lang.t("ANNULER", "CANCEL") if busy else Lang.t("REJOINDRE", "JOIN")
	join_button.box.flat(Hub2Style.shade(0.5), Color(1, 0.42, 0.34, 0.6) if busy else Hub2Style.text_a(0.4), 1.0)
	host_button.disabled = busy
	host_button.modulate.a = 0.45 if busy else 1.0
	if busy:
		status_label.add_theme_color_override("font_color", Hub2Style.YELLOW)
		status_label.text = Lang.t("Connexion à %s", "Connecting to %s") % Hub2PlayData.address_text(Net.server_address, Net.port) \
				+ ".".repeat(1 + int(_dots_t * 2.0) % 3)
	elif _error != "":
		status_label.add_theme_color_override("font_color", Hub2Style.BAD)
		status_label.text = _error
	else:
		status_label.add_theme_color_override("font_color", Hub2Style.text_a(0.6))
		status_label.text = ""


static func local_ip() -> String:
	@warning_ignore("static_called_on_instance")
	var ips := Net.local_ipv4_addresses()
	return ips[0] if ips.size() > 0 else "127.0.0.1"


func _process(delta: float) -> void:
	# « APERÇU EN PRÉPARATION » qui pulse doucement (1,6 s).
	if view == SOLO and is_instance_valid(preview_loading) and preview_loading.visible:
		_dots_t += delta
		preview_loading.modulate.a = 0.725 + 0.275 * cos(_dots_t * TAU / 1.6)
	if view == COOP and connecting():
		_dots_t += delta
		_refresh_coop_state()


func _player_name() -> String:
	@warning_ignore("static_called_on_instance")
	return Net._clean_name(name_edit.text if name_edit else Settings.player_name)


## HÉBERGER : ouvre la session (Net.host, 4 joueurs comme la maquette) puis
## le salon.
func host_lobby() -> void:
	if connecting() or Net.is_online():
		return
	_error = ""
	var port_txt := port_edit.text.strip_edges() if port_edit else str(Settings.last_port)
	@warning_ignore("static_called_on_instance")
	if not port_txt.is_valid_int() or not Net.is_valid_port(port_txt.to_int()):
		_fail(Lang.t("Port invalide (1024 à 65535).", "Invalid port (1024 to 65535)."))
		return
	Settings.player_name = _player_name()
	if Net.host(port_txt.to_int(), Net.DEFAULT_MAX_PLAYERS, Settings.player_name) != OK:
		return  # erreur signalée par Net.connection_error -> show_error
	Settings.last_port = port_txt.to_int()
	Settings.save_settings()
	GameState.set_state(GameState.State.LOBBY)
	sync()


## REJOINDRE (ou ANNULER pendant la connexion).
func join_or_cancel() -> void:
	if connecting():
		Net.leave()
		GameState.reset_to_menu()
		_error = ""
		_refresh_coop_state()
		return
	if Net.is_online():
		return
	_error = ""
	var a := Hub2PlayData.parse_address(address_edit.text if address_edit else "", Settings.last_port)
	if a.is_empty():
		_fail(Lang.t("Adresse invalide (exemple : 192.168.1.24:7777).", "Invalid address (example: 192.168.1.24:7777)."))
		return
	Settings.player_name = _player_name()
	Settings.last_ip = String(a[0])
	Settings.last_port = int(a[1])
	Settings.save_settings()
	_dots_t = 0.0
	GameState.set_state(GameState.State.CONNECTING)
	if Net.join(String(a[0]), int(a[1]), Settings.player_name) != OK:
		return
	_refresh_coop_state()


func _fail(t: String) -> void:
	_error = t
	_refresh_coop_state()
	Audio.play_ui("ui_error", -6.0)


## Erreur de connexion ou fin de session (MainMenu) : vue COOP, message sur
## place.
func show_error(title: String, message: String) -> void:
	_error = ("%s : %s" if not Lang.is_en() else "%s: %s") % [title, message.replace("\n", " ")]
	last_view = COOP
	sync()
	_refresh_coop_state()
	Audio.play_ui("ui_error", -6.0)


## Quitte le salon (QUITTER LE SALON) : session fermée, vue COOP.
func leave_lobby() -> void:
	close_modal()
	Net.leave()
	GameState.reset_to_menu()
	Router.lobby_message = ""
	last_view = COOP
	sync()
