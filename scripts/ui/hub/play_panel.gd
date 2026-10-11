class_name HubPlayPanel
extends HubPanel
## Onglet PARTIE du hub (docs/HUB_PLAN.md §3.7, D4 ; maquette écrans 9 et
## 10) : SOLO ou COOP, puis le salon dans le même onglet.
##
## Trois vues :
##   - SOLO (écran 9) : à gauche SOLO / COOP et la liste des cartes (cartes du
##     jeu puis cartes perso jouables de l'éditeur) ; à droite l'aperçu de la
##     carte choisie (plan, vagues spéciales et de boss, porte d'évacuation,
##     échantillons qu'on y trouve), VOUS PARTEZ AVEC (armes de départ du
##     profil, MODIFIER : onglet DÉPART), CONTRATS ACTIFS (« sur cette carte »
##     quand elle donne un échantillon qui manque), LANCER LA PARTIE (même
##     chemin que l'ancien écran de sélection de carte : fondu cinématique
##     puis Router.start_solo, choix mémorisé dans Settings.last_map) ;
##     au-dessus des cartes, la ligne DÉFI DE LA SEMAINE (GAME_CONCEPT
##     §4.18, HubPlayWeekly) : aperçu du défi (carte, modificateurs,
##     objectif, meilleur résultat, temps restant, récompense), LANCER LE DÉFI ;
##   - COOP (pas de maquette, même style) : nom du joueur, HÉBERGER (port,
##     joueurs maximum), REJOINDRE (adresse IP, port) ; erreurs de connexion
##     affichées sur place ;
##   - SALON (écran 10, HubPlayLobby) dès que la session est ouverte (hôte, ou
##     invité accepté) : le groupe reste connecté pendant que chacun parcourt
##     les autres onglets du hub (le panneau reste en vie, D4) ; après une
##     partie multijoueur, le menu rouvre le hub sur cet onglet.
## La vue suit l'état du réseau (sync) ; SOLO / COOP est retenu d'une visite
## à l'autre (last_view).

const SOLO := "solo"
const COOP := "coop"
const LOBBY := "lobby"

## Dernier choix SOLO / COOP (retour au hub, autre visite).
static var last_view := SOLO

## Vue affichée (SOLO, COOP, LOBBY).
var view := ""
var solo_button: HubButton
var coop_button: HubButton
## SOLO : lignes des cartes (id -> HubPlayView.MapRow), carte choisie.
var map_rows: Dictionary = {}
var selected := ""
var launch_button: HubButton
var modify_button: HubButton
## SOLO : aperçu de la carte choisie.
var map_title: Label
var preview: TextureRect
var info_lines: Array = []  # RichTextLabel
var _chips: HBoxContainer
var _contracts: VBoxContainer
var _contracts_group: HubRow
var _loadout_box: VBoxContainer
## SOLO : défi de la semaine (ligne HubPlayWeekly.ROW_ID ; null : aucun) et
## aperçu affiché (-1 : pas encore, 0 : carte, 1 : défi).
var weekly: WeeklyChallenge
var _weekly_view := -1
## COOP : champs et boutons.
var name_edit: LineEdit
var host_port_edit: LineEdit
var ip_edit: LineEdit
var join_port_edit: LineEdit
var host_button: HubButton
var join_button: HubButton
var max_label: Label
var max_players := Net.DEFAULT_MAX_PLAYERS
var status_label: Label
## SALON (vue LOBBY).
var lobby: HubPlayLobby
## Changements du salon pendant que l'onglet est caché (pastille).
var changes := 0
var _seen := ""
var _root: HBoxContainer
var _leaving := false
var _dots_t := 0.0
## Dernière erreur de connexion à afficher dans la vue COOP.
var _error := ""


func build() -> void:
	_root = HubBox.hbox(16)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	Net.players_changed.connect(_on_net_changed)
	Net.joined_server.connect(sync)
	Net.lobby_map_changed.connect(_on_lobby_map)
	_publish_card()
	sync()


func _exit_tree() -> void:
	if Net.players_changed.is_connected(_on_net_changed):
		Net.players_changed.disconnect(_on_net_changed)
	if Net.joined_server.is_connected(sync):
		Net.joined_server.disconnect(sync)
	if Net.lobby_map_changed.is_connected(_on_lobby_map):
		Net.lobby_map_changed.disconnect(_on_lobby_map)


## Session ouverte et salon affichable (hôte, ou invité accepté).
static func in_lobby() -> bool:
	return Net.is_online() and GameState.state == GameState.State.LOBBY


## Vue qui suit l'état du réseau : SALON si la session est ouverte, sinon le
## dernier choix SOLO / COOP. Reconstruit seulement si la vue change.
func sync() -> void:
	var want := LOBBY if in_lobby() else (COOP if last_view == COOP or Net.mode == Net.Mode.CLIENT else SOLO)
	if want != view:
		_show(want)
	elif view == COOP:
		_refresh_coop_state()


func _show(v: String) -> void:
	var had_focus := _has_focus()
	view = v
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	map_rows.clear()
	info_lines.clear()
	lobby = null
	match v:
		LOBBY:
			lobby = HubPlayLobby.new(self)
			lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_root.add_child(lobby)
			_seen = _lobby_signature()
		COOP:
			_build_coop()
		_:
			_build_solo()
	if hub:
		hub.refresh_prompts()
		hub.refresh_badges()
	if had_focus or (hub and hub.tab == tab_id and visible):
		var f := first_focus()
		if f and hub:
			hub.focus_later(f)


func _has_focus() -> bool:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return f != null and is_ancestor_of(f)


## Le profil a changé (autre onglet) : armes de départ et contrats relus,
## fiche de salon renvoyée (niveau, armes de départ).
func refresh() -> void:
	_publish_card()
	var keep := view
	view = ""
	_show(keep)


func _publish_card() -> void:
	var pr := profile()
	if pr:
		Net.set_lobby_card(pr.level(), pr.starting_weapons)


func first_focus() -> Control:
	match view:
		LOBBY:
			return lobby.first_focus() if lobby else null
		COOP:
			return join_button if Net.mode == Net.Mode.CLIENT else host_button
	return launch_button


func prompts() -> Array:
	match view:
		LOBBY:
			return [[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")],
				[HubPrompts.TABS, Lang.t("Onglets (le salon reste ouvert)", "Tabs (the lobby stays open)")],
				[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]
		COOP:
			return [[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
				[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]
	return [[HubPrompts.ACCEPT, Lang.t("Lancer", "Start")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]


func back() -> bool:
	if view == LOBBY and lobby:
		return lobby.back()
	return false


func shown() -> void:
	changes = 0
	_seen = _lobby_signature()
	if hub:
		hub.refresh_badges()
	if view == LOBBY and lobby:
		lobby.update_hint()


## Pastille : changements du salon (joueur arrivé ou parti, carte changée)
## pendant que l'onglet était caché.
func badge() -> int:
	return changes


func _lobby_signature() -> String:
	var ids := Net.players.keys()
	ids.sort()
	return "%s|%s" % [str(ids), Net.lobby_map]


func _note_change() -> void:
	if view != LOBBY or (hub and hub.tab == tab_id):
		_seen = _lobby_signature()
		return
	var sig := _lobby_signature()
	if sig != _seen:
		_seen = sig
		changes += 1
		if hub:
			hub.refresh_badges()


func _on_net_changed() -> void:
	sync()
	_note_change()


func _on_lobby_map(_id: String) -> void:
	_note_change()


## Erreur de connexion ou fin de session (MainMenu) : vue COOP, message sur
## place (titre en tête).
func show_error(title: String, message: String) -> void:
	_error = "%s : %s" % [title, message.replace("\n", " ")] if not Lang.is_en() else "%s: %s" % [title, message.replace("\n", " ")]
	last_view = COOP
	sync()
	_refresh_coop_state()
	Audio.play_ui("ui_error", -6.0)


# --------------------------------------------------------------------------
# SOLO / COOP (en haut à gauche)
# --------------------------------------------------------------------------

func _mode_toggle(left: HubBox) -> void:
	var tog := HubBox.hbox(0)
	solo_button = hub_button("SOLO", func(): _choose(SOLO), HubButton.PRIMARY if view == SOLO else HubButton.NORMAL,
			Lang.t("Partir seul : choisir une carte et lancer.", "Head out alone: pick a map and start."))
	coop_button = hub_button(Lang.t("COOP", "CO-OP"), func(): _choose(COOP), HubButton.PRIMARY if view == COOP else HubButton.NORMAL,
			Lang.t("Coopération de 2 à %d survivants, par adresse IP : héberger ou rejoindre.",
				"Co-op for 2 to %d survivors, over IP address: host or join.") % Net.MAX_SUPPORTED_PLAYERS)
	for b in [solo_button, coop_button]:
		b.min_width = 196
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tog.add_child(b)
	var p := HubBox.pad(tog, 12, 12, 12, 14)
	HubPlayView.underline(p)
	left.content.add_child(p)


func _choose(v: String) -> void:
	# Un invité en cours de connexion reste en COOP (ANNULER d'abord).
	if v == SOLO and Net.mode == Net.Mode.CLIENT:
		return
	last_view = v
	_error = ""
	if v != view:
		_show(v)
		if hub:
			hub.focus_later(solo_button if v == SOLO else coop_button)


# --------------------------------------------------------------------------
# Vue SOLO (écran 9)
# --------------------------------------------------------------------------

func _build_solo() -> void:
	var left := HubBox.new()
	left.custom_minimum_size.x = HubStyle.px(420)
	_root.add_child(left)
	_mode_toggle(left)
	var maps := HubPlayView.playable_maps()
	var game_maps := maps.filter(func(m): return not m.custom)
	var custom := maps.filter(func(m): return m.custom)
	# Défi de la semaine (§4.18) : une ligne au-dessus des cartes.
	weekly = HubPlayWeekly.current()
	left.content.add_child(HubRow.group(Lang.t("DÉFI DE LA SEMAINE", "WEEKLY CHALLENGE")))
	_add_row(left.content, HubPlayWeekly.ROW_ID, HubPlayWeekly.row_title(weekly),
			HubPlayWeekly.row_note(weekly, profile()), HubPlayWeekly.hint(weekly), 0)
	left.content.add_child(HubRow.group(Lang.t("CARTES DU JEU", "GAME MAPS")))
	_add_map_rows(left.content, game_maps)
	left.content.add_child(HubRow.group(Lang.t("CARTES PERSO", "CUSTOM MAPS")))
	if custom.is_empty():
		var r := HubRow.new()
		var l := HubStyle.label(Lang.t("Aucune : dessinez-en une dans l'ÉDITEUR DE CARTES", "None yet: draw one in the MAP EDITOR"), 13, HubStyle.DIM)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.box.add_child(l)
		r.box.add_child(HubBox.spring(false))
		left.content.add_child(r)
	else:
		_add_map_rows(left.content, custom)

	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(right)
	var box := HubBox.new("", "", false, false)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	right.add_child(box)
	var top := HubBox.hbox(16)
	box.content.add_child(HubBox.pad(top, 14, 14, 14, 14))
	var pv := HubPlayView.preview_box(300, 220)
	top.add_child(pv[0])
	preview = pv[1]
	var info := HubBox.vbox(12)  # 8 px de la maquette + interligne des lignes riches
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	map_title = HubStyle.label("", 30, HubStyle.RED_HI, "title", true, 0.05)
	map_title.add_theme_constant_override("shadow_offset_x", int(HubStyle.px(3)))
	map_title.add_theme_constant_override("shadow_offset_y", int(HubStyle.px(3)))
	map_title.clip_text = true
	map_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_title.custom_minimum_size.x = HubStyle.px(100)
	info.add_child(map_title)
	for i in 3:
		var t := HubSamplesColumn.rich("", 13, HubStyle.PAPER, true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(t)
		info_lines.append(t)
	_chips = HubBox.hbox(6)
	info.add_child(HubBox.pad(_chips, 0, 4, 0, 0))
	box.content.add_child(HubRow.group(Lang.t("VOUS PARTEZ AVEC", "YOU HEAD OUT WITH")))
	_loadout_box = HubBox.vbox(0)
	box.content.add_child(_loadout_box)
	_contracts_group = HubRow.group("")
	box.content.add_child(_contracts_group)
	_contracts = HubBox.vbox(0)
	box.content.add_child(_contracts)
	launch_button = hub_button(Lang.t("LANCER LA PARTIE", "START THE GAME"), _launch_selected, HubButton.PRIMARY, "")
	# Aide selon l'aperçu (partie ou défi) : lue au moment du focus.
	launch_button.focus_entered.connect(func():
		if hub:
			hub.set_hint(launch_button.hint))
	_weekly_view = -1
	_set_weekly_view(false)
	launch_button.big = true
	launch_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	launch_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	launch_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	launch_button.offset_right = -HubStyle.px(16)
	launch_button.offset_bottom = -HubStyle.px(16)
	launch_button.offset_left = launch_button.offset_right
	launch_button.offset_top = launch_button.offset_bottom
	right.add_child(launch_button)
	var start: String = Settings.last_map if map_rows.has(Settings.last_map) else (game_maps[0].id if not game_maps.is_empty() else "")
	if start != "":
		select_map(start)


func _add_map_rows(parent: Control, maps: Array) -> void:
	var i := 0
	for m in maps:
		var def: MapDef = m.def
		var f := HubPlayView.map_facts(m.id, def)
		var hint := Lang.t("Carte perso (éditeur de cartes) : %s.", "Custom map (map editor): %s.") % HubPlayView.map_name(def) \
				if m.custom else (def.description if def.description != "" else HubPlayView.map_name(def))
		_add_row(parent, m.id, HubPlayView.map_name(def) if m.custom else def.display_name, HubPlayView.list_note(f), hint, i)
		i += 1


func _add_row(parent: Control, id: String, title: String, note: String, hint: String, i: int) -> void:
	var row := HubPlayView.MapRow.new(id, title, note, hint)
	row.alt = i % 2 == 1
	row.chosen.connect(select_map)
	row.activated.connect(func(_id): _launch_selected())
	row.focus_entered.connect(func():
		if hub:
			hub.set_hint(row.hint))
	parent.add_child(row)
	map_rows[id] = row


## Aperçu de droite en mode défi (`on`) ou carte : armes de départ (imposées
## ou du profil), CONTRATS ACTIFS ou RÈGLES DU DÉFI, texte de LANCER.
func _set_weekly_view(on: bool) -> void:
	if _weekly_view == int(on):
		return
	_weekly_view = int(on)
	for c in _loadout_box.get_children():
		_loadout_box.remove_child(c)
		c.queue_free()
	if on:
		_loadout_box.add_child(HubPlayWeekly.loadout_row())
		modify_button = null
	else:
		var lr := HubPlayView.loadout_row(profile(), self)
		_loadout_box.add_child(lr[0])
		modify_button = lr[1]
	(_contracts_group.box.get_child(0) as Label).text = Lang.t("RÈGLES DU DÉFI", "CHALLENGE RULES") if on \
			else Lang.t("CONTRATS ACTIFS", "ACTIVE CONTRACTS")
	launch_button.label = Lang.t("LANCER LE DÉFI", "START THE CHALLENGE") if on else Lang.t("LANCER LA PARTIE", "START THE GAME")
	launch_button.hint = Lang.t("Évacuez à la manche %d ou plus pour la récompense de la semaine.", "Evacuate at round %d or later for this week's reward.") \
			% (weekly.goal_round if weekly else 0) if on else Lang.t("La partie ne se termine jamais d'elle-même : évacuez après une vague spéciale.",
				"The game never ends on its own: evacuate after a special wave.")


## SOLO : le défi de la semaine choisi (aperçu de droite).
func _show_weekly() -> void:
	_set_weekly_view(true)
	map_title.text = Lang.t("DÉFI DE LA SEMAINE", "WEEKLY CHALLENGE")
	preview.texture = MapPreview.texture(weekly.map_id) if weekly else null
	var lines := HubPlayWeekly.info_lines(weekly, profile())
	for i in info_lines.size():
		(info_lines[i] as RichTextLabel).text = HubSamplesColumn.style_bbcode(lines[i])
	HubPlayWeekly.fill_reward(_chips, weekly, profile())
	for c in _contracts.get_children():
		_contracts.remove_child(c)
		c.queue_free()
	for r in HubPlayWeekly.rule_rows():
		_contracts.add_child(r)


## SOLO : choisit la carte `id` (ligne surlignée, aperçu, contrats).
func select_map(id: String) -> void:
	if not map_rows.has(id):
		return
	selected = id
	for k in map_rows:
		(map_rows[k] as HubPlayView.MapRow).selected = k == id
	var row: HubPlayView.MapRow = map_rows[id]
	if launch_button:
		launch_button.focus_neighbor_left = launch_button.get_path_to(row)
		for k in map_rows:
			var r: Control = map_rows[k]
			r.focus_neighbor_right = r.get_path_to(launch_button)
	if id == HubPlayWeekly.ROW_ID:
		_show_weekly()
		return
	_set_weekly_view(false)
	var def := HubPlayView.def_of(id)
	var f := HubPlayView.map_facts(id, def)
	map_title.text = HubPlayView.map_name(def).to_upper()
	preview.texture = MapPreview.texture(id)
	var lines := [HubPlayView.special_line(f), HubPlayView.boss_line(f), HubPlayView.evac_line(f)]
	for i in info_lines.size():
		(info_lines[i] as RichTextLabel).text = HubSamplesColumn.style_bbcode(lines[i])
	for c in _chips.get_children():
		c.queue_free()
	var lab := HubStyle.label(Lang.t("Échantillons :", "Samples:"), 13, HubStyle.DIM)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chips.add_child(lab)
	if (f.samples as Array).is_empty():
		var none := HubStyle.label(Lang.t("aucun (pas de vague spéciale)", "none (no special wave)"), 13, HubStyle.DIM)
		none.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_chips.add_child(none)
	for k in f.samples:
		_chips.add_child(HubPlayView.sample_chip(String(k)))
	for c in _contracts.get_children():
		c.queue_free()
	for r in HubPlayView.contract_rows(profile(), f):
		_contracts.add_child(r)


func _launch_selected() -> void:
	if _leaving or selected == "" or hub == null or hub.menu == null:
		return
	var ch := weekly if selected == HubPlayWeekly.ROW_ID else null
	if selected == HubPlayWeekly.ROW_ID and ch == null:
		return
	_leaving = true
	for r in map_rows.values():
		(r as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ch:
		# Défi de la semaine : sa carte, sa clé (la carte mémorisée ne change pas).
		hub.menu.launch(func(): Router.start_solo(ch.map_id, ch.key))
		return
	var id := selected
	Settings.last_map = id
	Settings.save_settings()
	hub.menu.launch(func(): Router.start_solo(id))


# --------------------------------------------------------------------------
# Vue COOP : héberger / rejoindre
# --------------------------------------------------------------------------

func _build_coop() -> void:
	var left := HubBox.new()
	left.custom_minimum_size.x = HubStyle.px(420)
	_root.add_child(left)
	_mode_toggle(left)
	var v := left.content
	v.add_child(HubRow.group(Lang.t("SURVIVANT", "SURVIVOR")))
	name_edit = HubPlayView.line_edit(Settings.player_name, Lang.t("Survivant", "Survivor"), 16)
	v.add_child(_field(Lang.t("Nom du joueur", "Player name"), name_edit))
	v.add_child(HubRow.group(Lang.t("HÉBERGER UNE PARTIE", "HOST A GAME")))
	host_port_edit = HubPlayView.line_edit(str(Settings.last_port), "7777", 5)
	v.add_child(_field("Port", host_port_edit))
	var mr := HubBox.hbox(8)
	var minus := hub_button("−", func(): _set_max(max_players - 1), HubButton.NORMAL,
			Lang.t("Joueurs maximum dans le salon.", "Maximum players in the lobby."))
	minus.height = 28
	minus.min_width = 34
	mr.add_child(minus)
	max_label = HubStyle.label(str(max_players), 17, HubStyle.PAPER, "impact")
	max_label.custom_minimum_size.x = HubStyle.px(28)
	max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	max_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mr.add_child(max_label)
	var plus := hub_button("+", func(): _set_max(max_players + 1), HubButton.NORMAL,
			Lang.t("Joueurs maximum dans le salon.", "Maximum players in the lobby."))
	plus.height = 28
	plus.min_width = 34
	mr.add_child(plus)
	mr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(_field(Lang.t("Joueurs maximum", "Max players"), mr))
	host_button = hub_button(Lang.t("HÉBERGER", "HOST"), _host, HubButton.PRIMARY,
			Lang.t("Ouvrir un salon : les autres vous rejoignent avec votre adresse IP.", "Open a lobby: the others join you with your IP address."))
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(HubPlayView.underline(HubBox.pad(host_button, 12, 8, 12, 10)))
	v.add_child(HubRow.group(Lang.t("REJOINDRE UNE PARTIE", "JOIN A GAME")))
	ip_edit = HubPlayView.line_edit(Settings.last_ip, "192.168.1.25", 15)
	v.add_child(_field(Lang.t("Adresse IP", "IP address"), ip_edit))
	join_port_edit = HubPlayView.line_edit(str(Settings.last_port), "7777", 5)
	v.add_child(_field("Port", join_port_edit))
	join_button = hub_button(Lang.t("REJOINDRE", "JOIN"), _join_or_cancel, HubButton.NORMAL,
			Lang.t("Entrer l'adresse IP et le port de l'hôte.", "Enter the host's IP address and port."))
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(HubBox.pad(join_button, 12, 8, 12, 8))
	status_label = HubStyle.label("", 13, HubStyle.DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(HubBox.pad(status_label, 12, 2, 12, 8))
	ip_edit.text_submitted.connect(func(_t): _join_or_cancel())
	join_port_edit.text_submitted.connect(func(_t): _join_or_cancel())
	host_port_edit.text_submitted.connect(func(_t): _host())
	name_edit.text_submitted.connect(func(_t): hub.focus_later(host_button))
	_build_coop_info()
	_refresh_coop_state()


## Ligne de formulaire : intitulé à gauche (gris, 13 px), champ à droite.
func _field(t: String, c: Control) -> HubRow:
	var r := HubRow.new()
	var l := HubStyle.label(t, 13, HubStyle.DIM)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = HubStyle.px(118)
	r.box.add_child(l)
	if c is LineEdit:
		c.focus_entered.connect(func():
			if hub:
				hub.set_hint(Lang.t("Entrée : valider.", "Enter: confirm.")))
	r.box.add_child(c)
	if c.size_flags_horizontal & Control.SIZE_EXPAND == 0:
		r.box.add_child(HubBox.spring(false))
	return r


## Panneau de droite de la vue COOP : règles de la coop, puis le rappel des
## armes de départ et des contrats (comme le salon, écran 10).
func _build_coop_info() -> void:
	var box := HubBox.new(Lang.t("COOPÉRATION", "CO-OP"), Lang.t("de 2 à %d survivants", "2 to %d survivors") % Net.MAX_SUPPORTED_PLAYERS, false, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(box)
	var v := HubBox.vbox(8)
	box.content.add_child(HubBox.pad(v, 14, 14, 14, 14))
	for t in [
			Lang.t("Par adresse IP : sur le même réseau, ou par Internet si l'hôte a ouvert son port.",
				"Over IP address: on the same network, or over the Internet if the host opened their port."),
			Lang.t("L'hôte choisit la carte ; ses cartes perso sont envoyées aux invités et vérifiées chez chacun.",
				"The host picks the map; their custom maps are sent to the guests and checked on each computer."),
			Lang.t("Chacun garde son profil, ses contrats et son butin : rien n'est partagé. Plus de chiens à plusieurs ; chacun tire ses propres échantillons.",
				"Everyone keeps their own profile, contracts and loot: nothing is shared. More dogs with more players; each one rolls their own samples."),
			Lang.t("Le salon reste ouvert pendant que vous parcourez les autres onglets.",
				"The lobby stays open while you browse the other tabs.")]:
		var l := HubStyle.label(t, 13, HubStyle.PLASTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	box.content.add_child(HubRow.group(Lang.t("VOUS PARTEZ AVEC", "YOU HEAD OUT WITH")))
	var lr := HubPlayView.loadout_row(profile(), self)
	box.content.add_child(lr[0])
	modify_button = lr[1]
	box.content.add_child(HubRow.group(Lang.t("VOS CONTRATS ACTIFS", "YOUR ACTIVE CONTRACTS")))
	for r in HubPlayView.contract_rows(profile(), {}):
		box.content.add_child(r)


func _set_max(v: int) -> void:
	max_players = clampi(v, 2, Net.MAX_SUPPORTED_PLAYERS)
	if max_label:
		max_label.text = str(max_players)


## Invité en cours de connexion ?
static func connecting() -> bool:
	return Net.mode == Net.Mode.CLIENT and GameState.state == GameState.State.CONNECTING


func _refresh_coop_state() -> void:
	if view != COOP or join_button == null:
		return
	var busy := connecting()
	join_button.label = Lang.t("ANNULER", "CANCEL") if busy else Lang.t("REJOINDRE", "JOIN")
	join_button.kind = HubButton.DANGER if busy else HubButton.NORMAL
	host_button.disabled = busy
	if busy:
		status_label.add_theme_color_override("font_color", HubStyle.YELLOW)
		status_label.text = Lang.t("Connexion à %s:%d", "Connecting to %s:%d") % [Net.server_address, Net.port] + ".".repeat(1 + int(_dots_t * 2.0) % 3)
	elif _error != "":
		status_label.add_theme_color_override("font_color", HubStyle.BAD)
		status_label.text = _error
	else:
		status_label.add_theme_color_override("font_color", HubStyle.DIM)
		status_label.text = Lang.t("Votre adresse IP : %s", "Your IP address: %s") % _local_ip()


static func _local_ip() -> String:
	@warning_ignore("static_called_on_instance")
	var ips := Net.local_ipv4_addresses()
	return ips[0] if ips.size() > 0 else "127.0.0.1"


func _process(delta: float) -> void:
	if view == COOP and connecting():
		_dots_t += delta
		_refresh_coop_state()


func _player_name() -> String:
	@warning_ignore("static_called_on_instance")
	return Net._clean_name(name_edit.text if name_edit else Settings.player_name)


## HÉBERGER : ouvre la session (Net.host) puis le salon dans l'onglet.
func _host() -> void:
	if connecting() or Net.is_online():
		return
	_error = ""
	var port_txt := host_port_edit.text.strip_edges()
	if not port_txt.is_valid_int() or not Net.is_valid_port(port_txt.to_int()):
		_fail(Lang.t("Port invalide (1024 à 65535).", "Invalid port (1024 to 65535)."))
		return
	Settings.player_name = _player_name()
	# Erreur (port occupé…) : Net.connection_error -> MainMenu -> show_error.
	if Net.host(port_txt.to_int(), max_players, Settings.player_name) != OK:
		return
	Settings.last_port = port_txt.to_int()
	Settings.save_settings()
	GameState.set_state(GameState.State.LOBBY)
	sync()


## REJOINDRE (ou ANNULER pendant la connexion).
func _join_or_cancel() -> void:
	if connecting():
		Net.leave()
		GameState.reset_to_menu()
		_error = ""
		_refresh_coop_state()
		return
	if Net.is_online():
		return
	_error = ""
	var ip := ip_edit.text.strip_edges()
	var port_txt := join_port_edit.text.strip_edges()
	if not Net.is_valid_ipv4(ip):
		_fail(Lang.t("Adresse IPv4 invalide (exemple : 192.168.1.25).", "Invalid IPv4 address (example: 192.168.1.25)."))
		return
	if not port_txt.is_valid_int() or not Net.is_valid_port(port_txt.to_int()):
		_fail(Lang.t("Port invalide (1024 à 65535).", "Invalid port (1024 to 65535)."))
		return
	Settings.player_name = _player_name()
	Settings.last_ip = ip
	Settings.last_port = port_txt.to_int()
	Settings.save_settings()
	_dots_t = 0.0
	GameState.set_state(GameState.State.CONNECTING)
	if Net.join(ip, port_txt.to_int(), Settings.player_name) != OK:
		return  # erreur signalée par Net.connection_error
	_refresh_coop_state()


func _fail(t: String) -> void:
	_error = t
	_refresh_coop_state()
	Audio.play_ui("ui_error", -6.0)


## Quitte le salon (QUITTER LE SALON, ÉCRAN TITRE) : session fermée, vue COOP.
func leave_lobby() -> void:
	Net.leave()
	GameState.reset_to_menu()
	Router.lobby_message = ""
	last_view = COOP
	sync()
