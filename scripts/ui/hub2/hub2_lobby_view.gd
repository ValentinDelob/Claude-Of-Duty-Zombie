class_name Hub2LobbyView
extends VBoxContainer
## Salon coop du hub v2 (docs/hub_v2/PartieCoop.dc.html ; logique de l'ancien
## salon HubPlayLobby : carte de l'hôte, carte perso envoyée et vérifiée,
## défi de la semaine, retour du groupe après une partie).
##
##   - en-tête : SOLO / COOP (260 px), « Salon de <hôte> », « Tu héberges ·
##     adresse 192.168.1.24:7777 », COPIER L'ADRESSE, QUITTER LE SALON (deux
##     appuis) ;
##   - une carte par joueur (4 colonnes, écart 14) : rendu du joueur teinté à
##     sa couleur (player_neutral + player_team_mask × HudStyle.player_color),
##     halo de sa couleur, HÔTE, pavé du niveau, nom, « Niveau N · ping »,
##     armes de départ (rendus), PRÊT / EN ATTENTE ; place libre en
##     pointillés « PLACE LIBRE » ;
##   - en bas : aperçu de la carte, « CARTE · CHOISIE PAR L'HÔTE », nom,
##     vagues, CHANGER DE CARTE (hôte), LANCER « N joueurs prêts sur M ».
## Le registre du salon (Net.players) porte niveau, armes de départ, état
## (« away », LobbyReturn) et ping (mesuré par l'hôte).

const PROMPT_MAP := "change_map"

var panel: Hub2PlayPanel
var is_host := false
## Hôte : cartes proposées et carte choisie.
var map_ids: Array = []
var map_id := ""
var copy_button: Hub2Button
var quit_button: Hub2Button
var change_button: Hub2Button
var launch_button: Hub2Button
var launch_sub: Label
var cards_row: HBoxContainer
## Fiches affichées (Hub2PlayData.lobby_cards) : tests.
var cards: Array = []
var map_thumb: Hub2Render
var map_label: Hub2Text
var map_title: Hub2Text
var map_waves: HBoxContainer
var map_note: Label
var status := ""
var start_reason := ""
var _quit_armed := false
var _launching := false
var _sig := ""


func _init(p: Hub2PlayPanel) -> void:
	panel = p
	is_host = Net.mode == Net.Mode.HOST
	add_theme_constant_override("separation", int(Hub2Style.px(16)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build_header()
	cards_row = Hub2Ui.hbox(14)
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cards_row)
	_build_bottom()
	if is_host:
		map_ids = []
		for m in HubPlayView.playable_maps():
			map_ids.append(m.id)
		map_id = Settings.last_map if Settings.last_map in map_ids else Game.MENU_MAPS[0]
		if Net.lobby_map == "":
			apply_map(map_id)
		else:
			map_id = Net.lobby_map if Net.lobby_map in map_ids else map_id
		if Net.lobby_challenge != "":
			var ch := HubPlayWeekly.current()
			if ch == null:
				Net.set_lobby_challenge("")
			elif ch.key != Net.lobby_challenge:
				choose_weekly()
	for pair in _signals():
		(pair[0] as Signal).connect(pair[1])
	_refresh()
	_refresh_map()
	# Après une partie : « je suis revenu au salon » (LobbyReturn).
	Net.lobby_return.report_in_lobby()


func _signals() -> Array:
	return [[Net.players_changed, _refresh], [Net.player_left, _on_left], [Net.lobby_map_changed, _on_lobby_map],
		[Net.lobby_challenge_changed, _on_lobby_map], [Net.map_share.states_changed, _refresh],
		[Net.map_share.offer_changed, _refresh_map], [Net.map_share.local_failed, _on_local_failed],
		[Net.lobby_return.changed, _refresh]]


func _exit_tree() -> void:
	for pair in _signals():
		var s: Signal = pair[0]
		if s.is_connected(pair[1]):
			s.disconnect(pair[1])


func first_focus() -> Control:
	if is_host and launch_button and not launch_button.disabled:
		return launch_button
	return change_button if change_button else copy_button


func prompts() -> Array:
	if is_host:
		return [[Hub2Input.ACCEPT, Lang.t("Lancer", "Launch")], [Hub2Input.FILTER, Lang.t("Changer de carte", "Change map")],
			[Hub2Input.BACK, Lang.t("Quitter le salon", "Leave the lobby")]]
	return [Hub2PlayPanel.loadout_prompt(), [Hub2Input.BACK, Lang.t("Quitter le salon", "Leave the lobby")]]


## Y / Tab : CHANGER DE CARTE (hôte).
func handle_input(event: InputEvent) -> bool:
	var jb := event as InputEventJoypadButton
	if (jb and jb.pressed and jb.button_index == JOY_BUTTON_Y) or Hub2Input.is_key(event, KEY_TAB):
		if is_host:
			open_picker()
			return true
	return false


func on_prompt(id: String) -> void:
	if id == Hub2Input.FILTER and is_host:
		open_picker()


## B / Échap : QUITTER LE SALON (deux appuis) ; vrai : consommé.
func back() -> bool:
	_on_quit()
	return true


func on_shown() -> void:
	Net.lobby_return.report_in_lobby()
	_refresh()


## Profil local changé (armes de départ) : la fiche part au salon (Net), les
## cartes suivront le registre.
func refresh_profile() -> void:
	_refresh()


# --------------------------------------------------------------------------
# En-tête
# --------------------------------------------------------------------------

func _build_header() -> void:
	var h := Hub2Ui.hbox(20)
	add_child(h)
	h.add_child(panel.mode_tabs(260))
	var who := Hub2Ui.vbox(0)
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(who)
	var t := Hub2Text.new()
	t.setup(Lang.t("Salon de %s", "%s's lobby") % Net.player_name(1), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT, 0.04)
	who.add_child(t)
	var line := Hub2Ui.hbox(0)
	who.add_child(line)
	var lead := Lang.t("Tu héberges · adresse ", "You are hosting · address ") if is_host \
			else Lang.t("Tu as rejoint · adresse ", "You joined · address ")
	line.add_child(Hub2Style.label(lead, Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.6)))
	var addr := Hub2Text.new()
	addr.setup(address(), Hub2Style.MONO, 500, 13, Hub2Style.TEXT)
	addr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(addr)
	h.add_child(Hub2Ui.spring())
	copy_button = Hub2Ui.outline_button(Lang.t("COPIER L’ADRESSE", "COPY ADDRESS"), Hub2Style.TEXT, Hub2Style.text_a(0.4), Hub2Style.shade(0.5))
	copy_button.hint = Lang.t("Copier l’adresse du salon pour l’envoyer à un ami.", "Copy the lobby address to send it to a friend.")
	copy_button.pressed.connect(copy_address)
	h.add_child(copy_button)
	quit_button = Hub2Ui.outline_button(Lang.t("QUITTER LE SALON", "LEAVE THE LOBBY"), Color("FF8A78"), Color(1, 107 / 255.0, 87 / 255.0, 0.6),
			Hub2Style.shade(0.5))
	quit_button.hint = Lang.t("Quitter le groupe (deux appuis).", "Leave the group (press twice).") + \
			(Lang.t(" Les invités reviennent au hub.", " The guests go back to the hub.") if is_host else "")
	quit_button.pressed.connect(_on_quit)
	h.add_child(quit_button)


## Adresse du salon (hôte : sa première adresse IP locale ; invité : celle de
## l'hôte).
func address() -> String:
	if is_host:
		return Hub2PlayData.address_text(Hub2PlayPanel.local_ip(), Net.port)
	return Hub2PlayData.address_text(Net.server_address, Net.port)


func copy_address() -> void:
	DisplayServer.clipboard_set(address())
	Audio.play_ui(MenuStyle.SND_SELECT, MenuStyle.VOL_SELECT)
	if panel.hub:
		panel.hub.set_hint(Lang.t("Adresse copiée : %s", "Address copied: %s") % address())


func _on_quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		Hub2Ui.button_text(quit_button).text = Lang.t("CONFIRMER : QUITTER", "CONFIRM: LEAVE")
		quit_button.box.flat(Color(1, 107 / 255.0, 87 / 255.0, 0.18), Color(1, 107 / 255.0, 87 / 255.0, 0.9), 1.0)
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		if panel.hub:
			panel.hub.set_hint(Lang.t("Appuie encore pour quitter le groupe.", "Press again to leave the group."))
		return
	panel.leave_lobby()


# --------------------------------------------------------------------------
# Cartes des joueurs
# --------------------------------------------------------------------------

func _refresh() -> void:
	if cards_row == null:
		return
	cards = Hub2PlayData.lobby_cards(Net.players, Net.map_share, Net.local_id())
	var sig := JSON.stringify(cards.map(func(c): return [c.pid, c.slot, c.name, c.lvl, c.ping, Array(c.gear), c.ready]))
	sig += "|%d" % Net.max_players
	if sig != _sig:
		_sig = sig
		for c in cards_row.get_children():
			cards_row.remove_child(c)
			c.queue_free()
		var cols := Hub2PlayData.lobby_columns(cards.size(), Net.max_players)
		for i in cols:
			var card: Control = player_card(cards[i]) if i < cards.size() else free_card()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cards_row.add_child(card)
	_refresh_start()


## Carte d'un joueur présent.
func player_card(c: Dictionary) -> Control:
	var box := Hub2Box.new()
	box.glass()
	var v := Hub2Ui.vbox(0)
	box.add_child(v)
	# Rendu : zone de 230 px, joueur de 220 px collé en bas, halo, HÔTE.
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, Hub2Style.px(230))
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = false
	v.add_child(stage)
	var col: Color = c.color
	var glow := TextureRect.new()
	glow.texture = glow_texture(col)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 150 × 26 (bottom 4), flou 10 px : la tache déborde de 2 × 10 px.
	glow.anchor_left = 0.5
	glow.anchor_right = 0.5
	glow.anchor_top = 1.0
	glow.anchor_bottom = 1.0
	glow.offset_left = -Hub2Style.px(95)
	glow.offset_right = Hub2Style.px(95)
	glow.offset_top = -Hub2Style.px(4 + 26 + 20)
	glow.offset_bottom = -Hub2Style.px(4 - 20)
	stage.add_child(glow)
	var img := Hub2Render.new()
	img.texture = HubRenders.character(HubRenders.PLAYER_NEUTRAL)
	img.overlay = HubRenders.character(HubRenders.PLAYER_TEAM_MASK)
	img.overlay_color = col
	img.fit = Hub2Render.FIT_BOTTOM
	img.shadow = Vector3(0, 10, 14)
	img.shadow_color = Color(0, 0, 0, 0.6)
	img.anchor_right = 1.0
	img.anchor_bottom = 1.0
	img.offset_top = Hub2Style.px(10)
	stage.add_child(img)
	if c.host:
		var tag := Hub2Ui.tag(Lang.t("HÔTE", "HOST"), Hub2Style.YELLOW, Hub2Style.YELLOW, Hub2Style.yellow_a(0.15))
		tag.position = Hub2Style.pxv(10, 8)
		stage.add_child(tag)
	# Infos : padding 12 16 14, écart 8, liseré haut 3 px de la couleur.
	var info := Hub2Box.new()
	info.flat(Color(0, 0, 0, 0), col, 0.0)
	info.border = Vector4(0, 3, 0, 0)
	info.border_color = col
	info.pad(15, 16, 14, 16)
	v.add_child(info)
	var iv := Hub2Ui.vbox(8)
	info.add_child(iv)
	var head := Hub2Ui.hbox(10)
	iv.add_child(head)
	var lvl := Hub2Box.new()
	lvl.flat(Color(0, 0, 0, 0), Hub2Style.YELLOW, 1.0)
	lvl.custom_minimum_size = Hub2Style.pxv(34, 34)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lt := Hub2Text.new()
	lt.setup(str(int(c.lvl)), Hub2Style.MONO, 700, 15, Hub2Style.YELLOW)
	lt.align = HORIZONTAL_ALIGNMENT_CENTER
	lvl.add_child(lt)
	head.add_child(lvl)
	var names := Hub2Ui.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var nm := Hub2Style.label(String(c.name), Hub2Style.CHAKRA, 700, 18, Hub2Style.TEXT)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.custom_minimum_size.x = Hub2Style.px(40)
	names.add_child(nm)
	names.add_child(Hub2Style.label(Lang.t("Niveau %d · %s", "Level %d · %s") % [int(c.lvl), String(c.ping)],
			Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55)))
	iv.add_child(Hub2Equipment.slots_row(c.gear, false, 4))
	var ready: bool = c.ready
	var st := Hub2Ui.tag(Hub2PlayData.status_text(ready), Color("062019") if ready else Hub2Style.text_a(0.7),
			Color(0, 0, 0, 0), Hub2Style.TEAL if ready else Hub2Style.white_a(0.08), 12, 0.16, 3, 10)
	iv.add_child(st)
	return box


## Halo de la couleur du joueur : ellipse floue (opacité 0.35, flou 10 px).
static func glow_texture(col: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(col, 0.35), Color(col, 0.3), Color(col, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 32
	return t


## Place libre : pointillés rgba(255, 255, 255, 0.2), fond rgba(10, 11, 13,
## 0.35), « + », PLACE LIBRE, invitation.
func free_card() -> Control:
	var c := Hub2Box.new()
	c.flat(Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.35))
	c.add_child(Hub2Ui.dashed_frame(Hub2Style.white_a(0.2)))
	var v := Hub2Ui.vbox(10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	var plus := Hub2Text.new()
	plus.setup("+", Hub2Style.CHAKRA, 500, 44, Hub2Style.text_a(0.5))
	plus.line_height = 44
	plus.align = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(plus)
	var t := Hub2Text.new()
	t.setup(Lang.t("PLACE LIBRE", "FREE SLOT"), Hub2Style.CHAKRA, 700, 14, Hub2Style.text_a(0.5), 0.16)
	t.align = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var p := MarginContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_constant_override("margin_left", int(Hub2Style.px(20)))
	p.add_theme_constant_override("margin_right", int(Hub2Style.px(20)))
	var l := Hub2Ui.paragraph(Lang.t("Donne ton adresse à un ami pour qu’il rejoigne le salon.",
			"Give your address to a friend so they can join the lobby."), 13, 0.5, 1.2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	v.add_child(p)
	return c


# --------------------------------------------------------------------------
# Carte et lancement
# --------------------------------------------------------------------------

func _build_bottom() -> void:
	var row := Hub2Ui.hbox(14)
	add_child(row)
	var box := Hub2Box.new()
	box.glass()
	box.pad(10, 18, 10, 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var h := Hub2Ui.hbox(18)
	box.add_child(h)
	var thumb := Hub2Box.new()
	thumb.flat(Color(0, 0, 0, 0.3), Hub2Style.white_a(0.15), 1.0)
	thumb.pad(1)
	thumb.custom_minimum_size = Hub2Style.pxv(150, 84)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map_thumb = Hub2Render.new()
	map_thumb.fit = Hub2Render.FIT_COVER
	thumb.add_child(map_thumb)
	h.add_child(thumb)
	var names := Hub2Ui.vbox(2)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(names)
	map_label = Hub2Ui.section(Lang.t("CARTE · CHOISIE PAR L’HÔTE", "MAP · PICKED BY THE HOST"), 11)
	names.add_child(map_label)
	map_title = Hub2Text.new()
	map_title.setup("", Hub2Style.CHAKRA, 700, 22, Hub2Style.TEXT)
	names.add_child(map_title)
	map_note = Hub2Style.label("", Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.55))
	map_note.visible = false
	names.add_child(map_note)
	map_waves = Hub2Ui.hbox(6)
	map_waves.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(map_waves)
	h.add_child(Hub2Ui.spring())
	if is_host:
		change_button = Hub2Ui.outline_button(Lang.t("CHANGER DE CARTE", "CHANGE MAP"), Hub2Style.TEXT, Hub2Style.text_a(0.4), Color(0, 0, 0, 0), 14)
		change_button.hint = Lang.t("Un invité voit la carte sans pouvoir la changer.", "A guest sees the map without being able to change it.")
		change_button.pressed.connect(open_picker)
		h.add_child(change_button)
	launch_button = panel.launch_card(240.0, " ")
	launch_sub = (launch_button.box.get_child(0) as VBoxContainer).get_child(1) as Label
	launch_button.pressed.connect(_on_start)
	launch_button.hint = Lang.t("Lancer la partie pour tout le groupe.", "Start the game for the whole group.") if is_host \
			else Lang.t("Seul l’hôte lance la partie.", "Only the host starts the game.")
	if not is_host:
		launch_button.focus_mode = Control.FOCUS_NONE
	row.add_child(launch_button)


## LANCER : « N joueurs prêts sur M » ; hôte : grisé avec la raison tant
## qu'un joueur n'est pas revenu ou n'a pas la carte ; invité : toujours grisé.
func _refresh_start() -> void:
	if launch_button == null:
		return
	var ready := 0
	for c in cards:
		if c.ready:
			ready += 1
	launch_sub.text = Hub2PlayData.ready_line(ready, cards.size())
	var ok := false
	start_reason = ""
	if is_host and not _launching:
		var st := Net.lobby_return.can_start()
		if st[0]:
			st = Net.map_share.can_start()
		ok = st[0]
		start_reason = "" if ok else String(st[1])
	elif not is_host:
		start_reason = Lang.t("Seul l’hôte lance la partie.", "Only the host starts the game.")
	launch_button.disabled = not ok
	launch_button.modulate.a = 1.0 if ok else 0.5
	if is_host:
		# Aide de l'écran quand on peut lancer (maquette) ; sinon la raison.
		launch_button.hint = "" if ok else start_reason


func _on_left(_pid: int) -> void:
	if is_host:
		status = Lang.t("Un joueur est parti.", "A player left.")
		if panel.hub:
			panel.hub.set_hint(status)
	_refresh()


func _on_local_failed(message: String) -> void:
	status = Lang.t("Carte de l’hôte refusée : %s", "Host's map refused: %s") % message
	if panel.hub:
		panel.hub.set_hint(status)
	_refresh_map()


func _on_start() -> void:
	if not is_host or Net.players.is_empty() or _launching:
		return
	var target := Net.lobby_map if map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) else map_id
	if not Net.start_match(target, Net.lobby_challenge):
		_refresh_start()
		return
	Router.lobby_message = ""
	_launching = true
	launch_button.disabled = true
	if panel.hub:
		panel.hub.set_hint(Lang.t("Lancement…", "Starting…"))


## Nom de la carte du salon (carte perso partagée : nom annoncé par l'hôte).
func map_name(id: String) -> String:
	if id.begins_with(EditorMapDef.SHARED_PREFIX):
		var nom: Dictionary = Net.map_share.offer.get("nom", {})
		if nom.is_empty():
			return "..."
		return CustomMapGuard.clean_display(Lang.t(String(nom.get("fr", "?")), String(nom.get("en", nom.get("fr", "?")))))
	if id == "":
		return "..."
	var def := HubPlayView.def_of(id)
	return Hub2PlayData.map_title(def) if def else "..."


func _on_lobby_map(_id: String) -> void:
	_refresh_map()


## Hôte : annonce la carte `id` (carte perso : contrôlée puis envoyée).
func apply_map(id: String) -> bool:
	var r := Net.set_lobby_map(id)
	if not r.ok:
		status = Lang.t("Carte refusée : %s", "Map refused: %s") % CustomMapGuard.reasons_text(r.get("reasons", []))
		if panel.hub:
			panel.hub.set_hint(status)
		return false
	map_id = id
	_refresh_map()
	return true


func choose_map(id: String) -> bool:
	if not apply_map(id):
		return false
	Settings.last_map = id
	Settings.save_settings()
	return true


## Hôte : défi de la semaine pour tout le groupe.
func choose_weekly() -> bool:
	var ch := HubPlayWeekly.current()
	if ch == null or not is_host or not apply_map(ch.map_id):
		return false
	Net.set_lobby_challenge(ch.key)
	return true


func _refresh_map() -> void:
	if map_title == null:
		return
	var id := map_id if is_host else Net.lobby_map
	var share := Net.map_share
	var custom := not share.offer.is_empty() and (Net.lobby_map.begins_with(EditorMapDef.SHARED_PREFIX) or id.begins_with(EditorMapDef.CUSTOM_PREFIX))
	map_title.text = map_name(id)
	var ch := WeeklyChallenge.from_key(Net.lobby_challenge) if Net.lobby_challenge != "" else null
	map_label.text = Lang.t("CARTE · DÉFI DE LA SEMAINE", "MAP · WEEKLY CHALLENGE") if ch \
			else Lang.t("CARTE · CHOISIE PAR L’HÔTE", "MAP · PICKED BY THE HOST")
	var def: MapDef = HubPlayView.def_of(id) if id != "" and (not custom or is_host or share.local_state == "prete") else null
	Hub2Ui.fill_waves(map_waves, def, 12, 3, 8, 6)
	var note := ""
	var tex: Texture2D = null
	var cover := false
	if not is_host and custom:
		match share.local_state:
			"prete":
				tex = MapPreview.texture(Net.lobby_map)
				note = Lang.t("Carte perso vérifiée : pour le fun, aucune progression.", "Custom map checked: just for fun, no progression.")
			"refusee":
				note = Lang.t("Carte refusée : elle ne sera pas chargée.", "Map refused: it will not be loaded.")
			_:
				var st := share.state_text(Net.local_id()) if share.states.has(Net.local_id()) else Lang.t("téléchargement…", "downloading…")
				note = st.left(1).to_upper() + st.substr(1)
	elif id != "":
		var pic := Hub2PlayPanel.map_picture(id)
		tex = pic[0]
		cover = pic[1]
		if custom or ProgressGate.is_custom_map(id):
			note = Lang.t("Carte perso : pour le fun, aucune progression.", "Custom map: just for fun, no progression.")
	if ch:
		note = ch.goal_text() + Lang.t(" ; armes de base pour tous, butin non gardé.", "; base weapons for everyone, loot not kept.")
	map_thumb.texture = tex
	map_thumb.fit = Hub2Render.FIT_COVER if cover else Hub2Render.FIT_CONTAIN
	map_thumb.texture_filter = HubRenders.FILTER if cover else CanvasItem.TEXTURE_FILTER_NEAREST
	map_note.text = note
	map_note.visible = note != ""
	_refresh_start()


# --------------------------------------------------------------------------
# CHANGER DE CARTE (hôte)
# --------------------------------------------------------------------------

func open_picker() -> void:
	if not is_host or panel.modal:
		return
	var m := Hub2Modal.new()
	m.setup(Lang.t("CHANGER DE CARTE", "CHANGE MAP"), Lang.t("Envoyée à tout le groupe.", "Sent to the whole group."), 460)
	panel.modal = m
	m.closed.connect(panel._on_modal_closed)
	panel.add_child(m)
	var first: Control = null
	var ch := HubPlayWeekly.current()
	if ch:
		m.body.add_child(Hub2Ui.section(Lang.t("DÉFI DE LA SEMAINE", "WEEKLY CHALLENGE")))
		var d := Hub2PlayData.weekly_card(ch, panel.profile())
		var wr := m.add_row(String(d.title), String(d.line), String(d.left), Net.lobby_challenge != "")
		wr.pressed.connect(_pick.bind(HubPlayWeekly.ROW_ID))
		first = wr
	var lists := Hub2PlayData.map_lists()
	for g in [[Lang.t("CARTES DU JEU", "GAME MAPS"), lists.game], [Lang.t("CARTES PERSONNALISÉES · POUR LE FUN", "CUSTOM MAPS · JUST FOR FUN"), lists.custom]]:
		if (g[1] as Array).is_empty():
			continue
		m.body.add_child(Hub2Ui.section(String(g[0])))
		for row in g[1]:
			var b := m.add_row(String(row.name), String(row.sub), String(row.best), String(row.id) == map_id and Net.lobby_challenge == "")
			b.pressed.connect(_pick.bind(String(row.id)))
			if first == null or (String(row.id) == map_id and Net.lobby_challenge == ""):
				first = b
	if panel.hub:
		panel.hub.refresh_prompts()
		if first:
			panel.hub.focus_later(first)


func _pick(id: String) -> void:
	if id == HubPlayWeekly.ROW_ID:
		choose_weekly()
	else:
		if Net.lobby_challenge != "":
			Net.set_lobby_challenge("")
		choose_map(id)
	panel.close_modal()
