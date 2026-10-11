class_name HubPlayLobby
extends HBoxContainer
## Salon de l'onglet PARTIE (docs/HUB_PLAN.md D4, maquette écran 10 ; reprend
## l'ancien écran du salon) :
##   - à gauche SALON : un joueur par ligne (couleur, nom, HÔTE, armes de
##     départ, niveau, état : AU SALON, EN RETOUR… pendant LobbyReturn,
##     téléchargement de la carte perso), places libres, résumé de la dernière
##     partie, DÉMARRER (hôte ; grisé avec la raison tant que le groupe n'est
##     pas revenu ou n'a pas la carte), QUITTER LE SALON (deux appuis) ;
##   - à droite CARTE (choisie par l'hôte) : plan, nom, vagues, CHANGER DE
##     CARTE (hôte : liste des cartes du jeu et perso ; une carte perso est
##     contrôlée puis envoyée aux invités, MapShare), état de la carte perso
##     chez l'invité ; VOUS PARTEZ AVEC et VOS CONTRATS ACTIFS (profil local).
## Le groupe reste connecté quand on change d'onglet (le panneau reste en
## vie) ; à l'affichage, « je suis revenu au salon » part vers l'hôte
## (LobbyReturn.report_in_lobby).

var panel: HubPlayPanel
var is_host := false
## Hôte : cartes proposées (cartes du jeu puis cartes perso jouables) et
## carte choisie (Settings.last_map).
var map_ids: Array = []
var map_id := ""
var start_button: HubFitButton
var quit_button: HubButton
var change_button: HubButton
var modify_button: HubButton
## Lignes des joueurs (HubRow), dans l'ordre des places.
var player_rows: Array = []
## Texte de chaque ligne de joueur (tests : nom, niveau, état).
var player_lines: PackedStringArray = []
var status: Label
## Hôte : raison du DÉMARRER grisé ("" : possible).
var start_reason := ""
var map_title: Label
var map_info: Label
var preview: TextureRect
var preview_note: Label
var picker: Control
var picker_rows: Dictionary = {}
var _rows_box: VBoxContainer
var _quit_armed := false
var _launching := false
var _left: Control
var _box: HubBox


func _init(p: HubPlayPanel) -> void:
	panel = p
	is_host = Net.mode == Net.Mode.HOST
	add_theme_constant_override("separation", int(HubStyle.px(16)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build_left()
	_build_right()
	if is_host:
		map_ids = []
		for m in HubPlayView.playable_maps():
			map_ids.append(m.id)
		map_id = Settings.last_map if Settings.last_map in map_ids else Game.MENU_MAPS[0]
		# Carte annoncée une fois par session (un retour au salon la garde).
		if Net.lobby_map == "":
			apply_map(map_id)
	Net.players_changed.connect(_refresh)
	Net.player_left.connect(_on_left)
	Net.lobby_map_changed.connect(_on_lobby_map)
	Net.map_share.states_changed.connect(_refresh)
	Net.map_share.offer_changed.connect(_refresh_map)
	Net.map_share.local_failed.connect(_on_local_failed)
	Net.lobby_return.changed.connect(_refresh_start)
	_refresh()
	_refresh_map()
	# Après une partie : « je suis revenu au salon » (l'hôte attend tout le
	# groupe avant de relancer, LobbyReturn).
	Net.lobby_return.report_in_lobby()


func _exit_tree() -> void:
	for pair in [[Net.players_changed, _refresh], [Net.player_left, _on_left], [Net.lobby_map_changed, _on_lobby_map],
			[Net.map_share.states_changed, _refresh], [Net.map_share.offer_changed, _refresh_map],
			[Net.map_share.local_failed, _on_local_failed], [Net.lobby_return.changed, _refresh_start]]:
		var s: Signal = pair[0]
		if s.is_connected(pair[1]):
			s.disconnect(pair[1])


func first_focus() -> Control:
	if picker:
		var r: Control = picker_rows.get(map_id)
		return r if r else null
	if change_button:
		return change_button
	return start_button if start_button and not start_button.disabled else quit_button


## Aide de la barre d'invites quand l'onglet s'affiche.
func update_hint() -> void:
	if panel.hub:
		panel.hub.set_hint(_hint())


func _hint() -> String:
	return Lang.t("Un invité voit la carte sans pouvoir la changer.", "A guest sees the map without being able to change it.") if is_host \
		else Lang.t("L'hôte choisit la carte et lance la partie.", "The host picks the map and starts the game.")


## Échap / B : ferme la liste des cartes, annule QUITTER ; sinon menu du hub.
func back() -> bool:
	if picker:
		close_picker()
		return true
	if _quit_armed:
		_disarm_quit()
		return true
	return false


# --------------------------------------------------------------------------
# SALON (gauche)
# --------------------------------------------------------------------------

func _build_left() -> void:
	_left = Control.new()
	_left.custom_minimum_size.x = HubStyle.px(620)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	var where := ""
	if is_host:
		where = Lang.t("vous êtes l'hôte · %s", "you are the host · %s") % HubPlayPanel._local_ip()
		if Net.port != Net.DEFAULT_PORT:
			where += ":%d" % Net.port
	else:
		where = Lang.t("connecté à %s:%d", "connected to %s:%d") % [Net.server_address, Net.port]
	_box = HubBox.new(Lang.t("SALON", "LOBBY"), where)
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_left.add_child(_box)
	_rows_box = HubBox.vbox(0)
	_box.content.add_child(_rows_box)
	var notes := HubBox.vbox(4)
	_box.content.add_child(HubBox.pad(notes, 14, 14, 14, 70))
	var last := Router.lobby_message
	if last != "":
		var l := HubStyle.label(last if last.ends_with(".") else last + ".", 13, HubStyle.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes.add_child(l)
	var rule := HubStyle.label(Lang.t("Chacun garde son profil, ses contrats et son butin : rien n'est partagé.",
			"Everyone keeps their own profile, contracts and loot: nothing is shared."), 13, HubStyle.DIM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(rule)
	status = HubStyle.label("", 13, HubStyle.YELLOW)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.add_child(status)
	var buttons := HubBox.hbox(10)
	buttons.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	buttons.offset_left = HubStyle.px(14)
	buttons.offset_right = -HubStyle.px(14)
	buttons.offset_bottom = -HubStyle.px(14)
	buttons.offset_top = buttons.offset_bottom - HubStyle.px(34)
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_left.add_child(buttons)
	start_button = HubFitButton.make_fit(Lang.t("DÉMARRER", "START") if is_host else Lang.t("EN ATTENTE DE L'HÔTE", "WAITING FOR THE HOST"),
			_on_start, HubButton.PRIMARY, Lang.t("Lancer la partie pour tout le groupe.", "Start the game for the whole group.") if is_host
			else Lang.t("Seul l'hôte lance la partie.", "Only the host starts the game."))
	start_button.focus_entered.connect(func():
		if panel.hub:
			panel.hub.set_hint(start_button.hint))
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.disabled = not is_host
	if not is_host:
		start_button.focus_mode = Control.FOCUS_NONE
	buttons.add_child(start_button)
	quit_button = panel.hub_button(Lang.t("QUITTER LE SALON", "LEAVE THE LOBBY"), _on_quit, HubButton.NORMAL,
			Lang.t("Quitter le groupe (deux appuis)." + (" Les invités reviennent au hub." if is_host else ""),
				"Leave the group (press twice)." + (" The guests go back to the hub." if is_host else "")))
	quit_button.min_width = 140
	buttons.add_child(quit_button)


## Lignes des joueurs : une par place occupée, puis les places libres.
func _refresh() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	player_rows.clear()
	player_lines.clear()
	var by_slot := {}
	for pid in Net.players:
		by_slot[Net.player_slot(pid)] = pid
	var slots := by_slot.keys()
	slots.sort()
	var i := 0
	for slot in slots:
		var row := _player_row(by_slot[slot], slot)
		row.alt = i % 2 == 1
		_rows_box.add_child(row)
		player_rows.append(row)
		i += 1
	var free := mini(Net.max_players - Net.players.size(), maxi(4 - Net.players.size(), 1))
	for k in maxi(free, 0):
		var r := _free_row()
		r.alt = (i + k) % 2 == 1
		_rows_box.add_child(r)
	if not is_host and Net.map_share.local_state in ["telechargement", "prete"]:
		_refresh_map()
	_refresh_start()


## État d'un joueur au salon : [texte, sorte de pastille].
func player_state(pid: int) -> Array:
	var p: Dictionary = Net.players.get(pid, {})
	if p.get("away", false):
		return [Lang.t("EN RETOUR…", "COMING BACK…"), HubTag.DATE]
	var share := Net.map_share
	if not share.offer.is_empty():
		match String(share.states.get(pid, {}).get("etat", "attente")):
			"prete":
				pass
			"refusee":
				return [Lang.t("CARTE REFUSÉE", "MAP REFUSED"), HubTag.NEW]
			"telechargement":
				return [Lang.t("CARTE %d %%", "MAP %d%%") % int(share.states[pid].get("pct", 0)), HubTag.DATE]
			_:
				return [Lang.t("ATTENTE CARTE", "AWAITING MAP"), HubTag.LOCK]
	return [Lang.t("AU SALON", "IN LOBBY"), HubTag.READY]


func _player_row(pid: int, slot: int) -> HubRow:
	var p: Dictionary = Net.players.get(pid, {})
	var row := HubRow.new(HubRow.ROW, 56.0)
	var sw := _swatch(ScorePanel.slot_color(slot), false)
	row.box.add_child(sw)
	var names := HubBox.vbox(1)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var top := HubBox.hbox(8)
	var nm := HubStyle.label(Net.player_name(pid).to_upper(), 17, HubStyle.PAPER, "bold")
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(nm)
	if pid == 1:
		top.add_child(HubTag.make(Lang.t("HÔTE", "HOST")))
	if pid == Net.local_id() and pid != 1:
		top.add_child(HubTag.make(Lang.t("VOUS", "YOU")))
	names.add_child(top)
	# Armes de départ (écart à la maquette : demandé par le lot E).
	var weapons := PackedStringArray()
	for id in p.get("start", PackedStringArray()):
		weapons.append(HubPlayView.weapon_label(String(id)))
	if not weapons.is_empty():
		var wl := HubStyle.label(" · ".join(weapons), 13, HubStyle.DIM)
		names.add_child(wl)
	row.box.add_child(names)
	row.box.add_child(HubBox.spring(false))
	var lvl := HubSamplesColumn.rich(Lang.t("NIV. [b]%s[/b]", "LVL [b]%s[/b]") % (str(int(p.lvl)) if p.has("lvl") else "–"), 15, HubStyle.PLASTER)
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.box.add_child(lvl)
	var st := player_state(pid)
	var tag := WideTag.new()
	tag.min_w = HubStyle.px(86)
	tag.text = st[0]
	tag.kind = st[1]
	row.box.add_child(tag)
	var line := "%s NIV.%s %s" % [Net.player_name(pid), str(p.get("lvl", "–")), st[0]]
	var share_txt := Net.map_share.state_text(pid)
	if share_txt != "":
		line += " — " + share_txt
	player_lines.append(line)
	return row


## Pastille d'état de largeur minimale (86 px de la maquette), texte centré.
class WideTag extends HubTag:
	var min_w := 0.0

	func _resize() -> void:
		super._resize()
		custom_minimum_size.x = maxf(custom_minimum_size.x, min_w)


func _free_row() -> HubRow:
	var row := HubRow.new(HubRow.ROW, 56.0)
	row.box.add_child(_swatch(HubStyle.DIM2, true))
	var l := HubStyle.label(Lang.t("Place libre", "Free slot"), 15, HubStyle.DIM2)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.box.add_child(l)
	row.box.add_child(HubBox.spring(false))
	var r := HubStyle.label(Lang.t("de 2 à %d joueurs", "2 to %d players") % Net.max_players, 13, HubStyle.DIM2)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.box.add_child(r)
	return row


## Pavé de couleur du joueur (16 × 28, contour noir) ; `dashed` : place libre.
func _swatch(col: Color, dashed: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = HubStyle.pxv(16, 28)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		var b := HubStyle.px(2)
		if dashed:
			var dc := Color("4A4844")
			var d := HubStyle.px(4)
			var y := 0.0
			while y < r.size.y:
				c.draw_rect(Rect2(0, y, b, minf(d, r.size.y - y)), dc)
				c.draw_rect(Rect2(r.size.x - b, y, b, minf(d, r.size.y - y)), dc)
				y += d * 2.0
			var x := 0.0
			while x < r.size.x:
				c.draw_rect(Rect2(x, 0, minf(d, r.size.x - x), b), dc)
				c.draw_rect(Rect2(x, r.size.y - b, minf(d, r.size.x - x), b), dc)
				x += d * 2.0
		else:
			c.draw_rect(r, HubStyle.BLACK)
			c.draw_rect(r.grow(-b), col))
	return c


## Hôte : DÉMARRER grisé avec la raison tant qu'un joueur n'a pas la carte ou
## n'est pas encore revenu au salon après la partie précédente.
func _refresh_start() -> void:
	if start_button == null or _launching:
		return
	if not is_host:
		start_button.disabled = true
		return
	var st := Net.lobby_return.can_start()
	if st[0]:
		st = Net.map_share.can_start()
	start_button.disabled = not st[0]
	# La raison est écrite dans le bouton (maquette : « DÉMARRER · RETOUR AU
	# SALON DE : MARIE ») ; la ligne d'état garde les autres messages.
	start_reason = "" if st[0] else String(st[1])
	start_button.label = Lang.t("DÉMARRER", "START") if st[0] else Lang.t("DÉMARRER · %s", "START · %s") % start_reason.to_upper()


func _on_left(_pid: int) -> void:
	if is_host:
		status.text = Lang.t("Un joueur est parti.", "A player left.")
		_refresh_start()


func _on_local_failed(message: String) -> void:
	# Refus de la carte : message clair, on reste dans le salon.
	status.text = Lang.t("Carte de l'hôte refusée : %s", "Host's map refused: %s") % message
	_refresh_map()


func _on_start() -> void:
	if not is_host or Net.players.is_empty() or _launching:
		return
	var target := Net.lobby_map if map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) else map_id
	if not Net.start_match(target):
		_refresh_start()
		return
	Router.lobby_message = ""
	_launching = true
	start_button.disabled = true
	status.text = Lang.t("Lancement...", "Starting...")


func _on_quit() -> void:
	if not _quit_armed:
		_quit_armed = true
		quit_button.label = Lang.t("CONFIRMER : QUITTER", "CONFIRM: LEAVE")
		quit_button.kind = HubButton.DANGER
		if panel.hub:
			panel.hub.set_hint(Lang.t("Appuyez encore pour quitter le groupe (Échap : annuler).", "Press again to leave the group (Esc: cancel)."))
		return
	panel.leave_lobby()


func _disarm_quit() -> void:
	_quit_armed = false
	quit_button.label = Lang.t("QUITTER LE SALON", "LEAVE THE LOBBY")
	quit_button.kind = HubButton.NORMAL
	update_hint()


# --------------------------------------------------------------------------
# CARTE (droite)
# --------------------------------------------------------------------------

func _build_right() -> void:
	var box := HubBox.new(Lang.t("CARTE", "MAP"), Lang.t("choisie par l'hôte", "picked by the host"), false, false)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	var top := HubBox.hbox(14)
	box.content.add_child(HubBox.pad(top, 14, 14, 14, 14))
	var pv := HubPlayView.preview_box(220, 160)
	top.add_child(pv[0])
	preview = pv[1]
	preview_note = HubStyle.label("", 13, HubStyle.DIM)
	preview_note.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(pv[0] as Control).add_child(preview_note)
	var info := HubBox.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	map_title = HubStyle.label("", 24, HubStyle.PAPER, "impact", true)
	map_title.clip_text = true
	map_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_title.custom_minimum_size.x = HubStyle.px(100)
	info.add_child(map_title)
	map_info = HubStyle.label("", 13, HubStyle.PAPER)
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.add_theme_constant_override("line_spacing", int(HubStyle.px(4)))
	info.add_child(map_info)
	if is_host:
		change_button = panel.hub_button(Lang.t("CHANGER DE CARTE", "CHANGE MAP"), open_picker, HubButton.NORMAL, _hint())
		change_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		info.add_child(HubBox.pad(change_button, 0, 6, 0, 0))
	box.content.add_child(HubRow.group(Lang.t("VOUS PARTEZ AVEC", "YOU HEAD OUT WITH")))
	var lr := HubPlayView.loadout_row(panel.profile(), panel)
	box.content.add_child(lr[0])
	modify_button = lr[1]
	box.content.add_child(HubRow.group(Lang.t("VOS CONTRATS ACTIFS", "YOUR ACTIVE CONTRACTS")))
	for r in HubPlayView.contract_rows(panel.profile(), {}):
		box.content.add_child(r)


## Nom de la carte du salon (carte perso partagée : nom annoncé par l'hôte,
## nettoyé ; jamais interprété comme du BBCode).
func map_name(id: String) -> String:
	if id.begins_with(EditorMapDef.SHARED_PREFIX):
		var nom: Dictionary = Net.map_share.offer.get("nom", {})
		if nom.is_empty():
			return "..."
		return CustomMapGuard.clean_display(Lang.t(String(nom.get("fr", "?")), String(nom.get("en", nom.get("fr", "?")))))
	if id == "":
		return "..."
	var def := HubPlayView.def_of(id)
	return HubPlayView.map_name(def) if def else "..."


func _on_lobby_map(_id: String) -> void:
	_refresh_map()


## Hôte : annonce la carte `id` (carte perso : contrôlée puis envoyée) ;
## faux si elle est refusée (la précédente reste).
func apply_map(id: String) -> bool:
	var r := Net.set_lobby_map(id)
	if not r.ok:
		status.text = Lang.t("Carte refusée : %s", "Map refused: %s") % CustomMapGuard.reasons_text(r.get("reasons", []))
		return false
	map_id = id
	if status.text.begins_with(Lang.t("Carte refusée", "Map refused")):
		status.text = ""
	_refresh_map()
	return true


## Hôte : choisit la carte `id` (mémorisée comme le choix du solo).
func choose_map(id: String) -> bool:
	if not apply_map(id):
		return false
	Settings.last_map = id
	Settings.save_settings()
	return true


func _refresh_map() -> void:
	if map_info == null:
		return
	var id := map_id if is_host else Net.lobby_map
	var share := Net.map_share
	var custom := not share.offer.is_empty() and (Net.lobby_map.begins_with(EditorMapDef.SHARED_PREFIX) or id.begins_with(EditorMapDef.CUSTOM_PREFIX))
	map_title.text = map_name(id).to_upper()
	var lines := []
	var def: MapDef = HubPlayView.def_of(id) if id != "" and (not custom or is_host or share.local_state == "prete") else null
	if def:
		lines.append(HubPlayView.lobby_waves_line(HubPlayView.map_facts(id, def)))
	if custom:
		lines.append(Lang.t("Carte perso · %s", "Custom map · %s") % _size_text(int(share.offer.get("size", 0))))
		if is_host:
			lines.append(Lang.t("Envoyée automatiquement aux invités, vérifiée chez chacun.", "Sent automatically to the guests, checked on each computer."))
	else:
		lines.append(Lang.t("Plus de chiens à plusieurs ; chacun tire ses propres échantillons", "More dogs with more players; each one rolls their own samples"))
	# Aperçu : dessiné sur place depuis la carte vérifiée (jamais une image reçue).
	var tex: Texture2D = null
	var note := ""
	if not is_host and custom:
		match share.local_state:
			"prete":
				tex = MapPreview.texture(Net.lobby_map)
				lines.append(Lang.t("Carte vérifiée et prête.", "Map checked and ready."))
			"refusee":
				note = Lang.t("Carte refusée : elle ne sera pas chargée.", "Map refused: it will not be loaded.")
				lines.append(share.local_reason)
			_:
				note = Lang.t("Aperçu après le téléchargement…", "Preview after the download…")
				var st := share.state_text(Net.local_id()) if share.states.has(Net.local_id()) else Lang.t("téléchargement...", "downloading...")
				lines.append(st[0].to_upper() + st.substr(1))
	elif id != "":
		tex = MapPreview.texture(id)
	preview.texture = tex
	preview_note.text = note
	map_info.text = "\n".join(lines)
	_refresh_start()


static func _size_text(n: int) -> String:
	if n >= 1048576:
		return Lang.t("%.1f Mo", "%.1f MB") % (n / 1048576.0)
	return Lang.t("%d Ko", "%d KB") % maxi(1, roundi(n / 1024.0))


## Texte d'état du salon (tests : raison du DÉMARRER grisé, carte refusée…).
func status_text() -> String:
	if start_reason != "":
		return start_reason
	return status.text if status else ""


# --------------------------------------------------------------------------
# Liste des cartes (hôte, CHANGER DE CARTE)
# --------------------------------------------------------------------------

## Fenêtre au-dessus du salon : voile, liste des cartes du jeu puis perso ;
## valider une carte l'annonce au groupe, Échap ferme.
func open_picker() -> void:
	if picker or not is_host:
		return
	var veil := Control.new()
	picker = veil
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.draw.connect(func(): veil.draw_rect(Rect2(Vector2.ZERO, veil.size), Color(0, 0, 0, 0.62)))
	veil.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_picker())
	panel.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(center)
	var box := HubBox.new(Lang.t("CHANGER DE CARTE", "CHANGE MAP"), Lang.t("envoyée à tout le groupe", "sent to the whole group"))
	center.add_child(box)
	picker_rows.clear()
	var maps := HubPlayView.playable_maps()
	var groups := [[Lang.t("CARTES DU JEU", "GAME MAPS"), maps.filter(func(m): return not m.custom)],
		[Lang.t("CARTES PERSO", "CUSTOM MAPS"), maps.filter(func(m): return m.custom)]]
	# Hauteur : toute la liste, défilante au-delà de 440 px.
	var h := 30.0 + 4.0 + maps.size() * 40.0
	for g in groups:
		if not (g[1] as Array).is_empty():
			h += 26.0
	box.custom_minimum_size = HubStyle.pxv(420, minf(h, 440.0))
	var first: Control = null
	for g in groups:
		if (g[1] as Array).is_empty():
			continue
		box.content.add_child(HubRow.group(g[0]))
		var i := 0
		for m in g[1]:
			var f := HubPlayView.map_facts(m.id, m.def)
			var row := HubPlayView.MapRow.new(m.id, HubPlayView.map_name(m.def), HubPlayView.list_note(f),
					Lang.t("Entrée : jouer cette carte.", "Enter: play this map."))
			row.alt = i % 2 == 1
			row.selected = m.id == map_id
			row.chosen.connect(func(_id):
				for k in picker_rows:
					(picker_rows[k] as HubPlayView.MapRow).selected = k == _id)
			row.activated.connect(_pick)
			row.focus_entered.connect(func():
				if panel.hub:
					panel.hub.set_hint(row.hint))
			box.content.add_child(row)
			picker_rows[m.id] = row
			if first == null:
				first = row
			i += 1
	var fr: Control = picker_rows.get(map_id, first)
	if fr and panel.hub:
		panel.hub.focus_later(fr)


func _pick(id: String) -> void:
	choose_map(id)
	close_picker()


func close_picker() -> void:
	if picker == null:
		return
	var p := picker
	picker = null
	picker_rows.clear()
	p.queue_free()
	if panel.hub and change_button:
		panel.hub.focus_later(change_button)
