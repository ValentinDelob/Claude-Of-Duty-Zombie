extends MenuScreen
## Salon d'avant-partie. Vue hôte : IP/port, joueurs, carte (officielle ou
## carte perso de l'éditeur, envoyée automatiquement aux invités : MapShare),
## [DÉMARRER] grisé tant que tout le monde n'a pas la carte. Vue client :
## serveur rejoint, joueurs, carte annoncée (nom, aperçu, taille,
## téléchargement de chacun), attente du lancement.

var is_host := false
var _list: VBoxContainer
var _start: Button
var _status: Label
## Hôte : carte choisie (Settings.last_map) et sa ligne ◄ ►.
var map_id := ""
var map_row: MenuOptionRow
## Hôte : cartes proposées (officielles puis cartes perso jouables).
var map_ids: Array = []
var _map_index := 0
var _map_label: Label
var _map_info: Label
var _map_title: Label
var _preview: TextureRect
var _preview_note: Label
var _launching := false


func enter(args := {}) -> void:
	is_host = args.get("host", Net.mode == Net.Mode.HOST)
	var col := vbox(10)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -260
	add_child(col)
	col.add_child(title("CLAUDE OF DUTY ZOMBIE", 40))
	if is_host:
		col.add_child(text(Lang.t("PARTIE PRIVÉE", "PRIVATE MATCH"), 26, UiStyle.BONE))
	else:
		col.add_child(text(Lang.t("CONNECTÉ À :", "CONNECTED TO:"), 18, UiStyle.DIM))
		col.add_child(text("%s:%d" % [Net.server_address, Net.port], 28))
	var panel := MenuStyle.panel()
	panel.custom_minimum_size = Vector2(520, 0)
	# Pas étiré à la largeur de la ligne CARTE : le dossier de la carte est à droite.
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(panel)
	var inner := vbox(6)
	panel.add_child(inner)
	inner.add_child(text(Lang.t("Joueurs :", "Players:"), 20, UiStyle.DIM))
	_list = vbox(4)
	inner.add_child(_list)
	if is_host:
		var ips := Net.local_ipv4_addresses()
		var ip_text := ips[0] if ips.size() > 0 else "127.0.0.1"
		inner.add_child(text("", 4))
		inner.add_child(text("IP : %s" % ip_text, 24, UiStyle.GOLD))
		if ips.size() > 1:
			inner.add_child(text(Lang.t("(autres : %s)", "(others: %s)") % ", ".join(ips.slice(1)), 16, UiStyle.DIM))
		inner.add_child(text("PORT : %d" % Net.port, 24, UiStyle.GOLD))
		# Choix de la carte (mémorisé, annoncé aux clients) : cartes officielles,
		# puis les cartes perso jouables de l'éditeur (envoyées aux invités).
		var names := PackedStringArray()
		map_ids = []
		for id in Game.MENU_MAPS:
			map_ids.append(id)
			names.append(MapPreview.map_def(id).display_name)
		for m in EditorMap.list_maps():
			var cid := EditorMapDef.CUSTOM_PREFIX + String(m.id)
			var cdef := MapPreview.map_def(cid) as EditorMapDef
			if cdef != null and cdef.is_valid():
				map_ids.append(cid)
				names.append(Lang.t("%s (perso)", "%s (custom)") % CustomMapGuard.clean_display(cdef.display_name))
		map_id = Settings.last_map if Settings.last_map in map_ids else Game.MENU_MAPS[0]
		_map_index = map_ids.find(map_id)
		map_row = MenuOptionRow.make_choice(Lang.t("CARTE", "MAP"), names, _map_index)
		map_row.value_changed.connect(_on_map_changed)
		map_row.focus_entered.connect(func(): menu.set_hint(Lang.t("◄ ► : carte de la partie (les cartes perso sont envoyées aux invités).", "◄ ► : match map (custom maps are sent to the guests).")))
		col.add_child(map_row)
		_start = button(Lang.t("DÉMARRER", "START"), _on_start)
		col.add_child(_start)
	else:
		_map_label = text(Lang.t("CARTE : %s", "MAP: %s") % _map_name(Net.lobby_map), 22, UiStyle.GOLD)
		col.add_child(_map_label)
		Net.lobby_map_changed.connect(_on_lobby_map)
	_status = text("" if is_host else Lang.t("En attente du lancement...", "Waiting for the host to start..."), 20, UiStyle.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	col.add_child(_status)
	var quit := button(Lang.t("QUITTER", "LEAVE"), back)
	col.add_child(quit)
	_build_map_panel()
	focus_later((_start if _start else quit))
	Net.players_changed.connect(_refresh)
	Net.player_left.connect(_on_left)
	Net.map_share.states_changed.connect(_refresh)
	Net.map_share.offer_changed.connect(_refresh_map)
	Net.map_share.local_failed.connect(_on_local_failed)
	if is_host:
		_apply_map(map_id)
	_refresh()
	_refresh_map()


## Dossier de la carte à droite : nom, aperçu (plan), taille et état.
func _build_map_panel() -> void:
	var panel := MenuStyle.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	# Au-dessus de la ligne CARTE de l'hôte (qui occupe le milieu de l'écran).
	panel.offset_left = -560
	panel.offset_right = -70
	panel.offset_top = -290
	panel.offset_bottom = 70
	add_child(panel)
	var inner := vbox(6)
	panel.add_child(inner)
	_map_title = UiStyle.label("", 28, UiStyle.BONE, "impact")
	inner.add_child(_map_title)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(450, 190)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	inner.add_child(_preview)
	_preview_note = text("", 16, UiStyle.DIM)
	inner.add_child(_preview_note)
	_map_info = text("", 18, UiStyle.BONE)
	_map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_info.custom_minimum_size = Vector2(450, 0)
	inner.add_child(_map_info)


## Nom de la carte du salon (carte perso partagée : nom annoncé par l'hôte,
## nettoyé ; jamais interprété comme du BBCode).
func _map_name(id: String) -> String:
	if id.begins_with(EditorMapDef.SHARED_PREFIX):
		var nom: Dictionary = Net.map_share.offer.get("nom", {})
		if nom.is_empty():
			return "..."
		return Lang.t(String(nom.get("fr", "?")), String(nom.get("en", nom.get("fr", "?"))))
	if id == "":
		return "..."
	var def := MapPreview.map_def(id)
	return def.display_name if def else "..."


func _on_map_changed(v: float) -> void:
	var i := clampi(int(v), 0, map_ids.size() - 1)
	if not _apply_map(map_ids[i]):
		# Carte refusée : on revient à la précédente.
		map_row.value = _map_index
		map_row.queue_redraw()
		return
	_map_index = i
	Settings.last_map = map_id
	Settings.save_settings()


## Hôte : annonce la carte `id` (carte perso : contrôlée puis envoyée).
func _apply_map(id: String) -> bool:
	var r := Net.set_lobby_map(id)
	if not r.ok:
		_status.text = Lang.t("Carte refusée : %s", "Map refused: %s") % CustomMapGuard.reasons_text(r.get("reasons", []))
		return false
	map_id = id
	_refresh_map()
	return true


func _on_lobby_map(_id: String) -> void:
	_refresh_map()


func _refresh_map() -> void:
	if not is_instance_valid(_map_info):
		return
	var id := map_id if is_host else Net.lobby_map
	var share := Net.map_share
	var custom := not share.offer.is_empty() and (Net.lobby_map.begins_with(EditorMapDef.SHARED_PREFIX) or id.begins_with(EditorMapDef.CUSTOM_PREFIX))
	if _map_label:
		_map_label.text = Lang.t("CARTE : %s", "MAP: %s") % _map_name(id)
	_map_title.text = CustomMapGuard.clean_display(_map_name(id))
	var lines := []
	if custom:
		lines.append(Lang.t("Carte perso · %s", "Custom map · %s") % _size_text(int(share.offer.get("size", 0))))
		if is_host:
			lines.append(Lang.t("Envoyée automatiquement aux invités, vérifiée chez chacun.", "Sent automatically to the guests, checked on each computer."))
	else:
		lines.append(Lang.t("Carte officielle", "Official map"))
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
				note = Lang.t("Aperçu après le téléchargement...", "Preview after the download...")
				var st := share.state_text(Net.local_id()) if share.states.has(Net.local_id()) else Lang.t("téléchargement...", "downloading...")
				lines.append(st[0].to_upper() + st.substr(1))
	elif id != "":
		tex = MapPreview.texture(id)
	_preview.texture = tex
	_preview_note.text = note
	_map_info.text = "\n".join(lines)
	_refresh_start()


static func _size_text(n: int) -> String:
	if n >= 1048576:
		return Lang.t("%.1f Mo", "%.1f MB") % (n / 1048576.0)
	return Lang.t("%d Ko", "%d KB") % maxi(1, roundi(n / 1024.0))


func exit() -> void:
	if Net.lobby_map_changed.is_connected(_on_lobby_map):
		Net.lobby_map_changed.disconnect(_on_lobby_map)
	if Net.players_changed.is_connected(_refresh):
		Net.players_changed.disconnect(_refresh)
	if Net.player_left.is_connected(_on_left):
		Net.player_left.disconnect(_on_left)
	var share := Net.map_share
	if share.states_changed.is_connected(_refresh):
		share.states_changed.disconnect(_refresh)
	if share.offer_changed.is_connected(_refresh_map):
		share.offer_changed.disconnect(_refresh_map)
	if share.local_failed.is_connected(_on_local_failed):
		share.local_failed.disconnect(_on_local_failed)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var by_slot := {}
	for pid in Net.players:
		by_slot[Net.player_slot(pid)] = pid
	for slot in Net.max_players:
		var line: Label
		if by_slot.has(slot):
			var pid: int = by_slot[slot]
			var tags := []
			if pid == 1:
				tags.append(Lang.t("hôte", "host"))
			if pid == multiplayer.get_unique_id():
				tags.append(Lang.t("vous", "you"))
			var suffix := ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""
			# Carte perso : état du téléchargement de chacun.
			var st := Net.map_share.state_text(pid)
			if st != "":
				suffix += "  — " + st
			line = text("%d. %s%s" % [slot + 1, Net.player_name(pid), suffix], 22, ScorePanel.slot_color(slot))
		else:
			line = text(Lang.t("%d. En attente...", "%d. Waiting...") % (slot + 1), 22, Color(0.4, 0.38, 0.35))
		_list.add_child(line)
	if not is_host and Net.map_share.local_state in ["telechargement", "prete"]:
		_refresh_map()
	_refresh_start()


## Hôte : [DÉMARRER] grisé avec la raison tant qu'un joueur n'a pas la carte.
func _refresh_start() -> void:
	if not _start or _launching:
		return
	var st := Net.map_share.can_start()
	_start.disabled = not st[0]
	if not st[0]:
		_status.text = st[1]
	elif not _status.text.begins_with(Lang.t("Carte refusée", "Map refused")):
		_status.text = Lang.t("%d/%d joueurs", "%d/%d players") % [Net.players.size(), Net.max_players]


func _on_left(_pid: int) -> void:
	if is_host:
		_status.text = Lang.t("Un joueur est parti.", "A player left.")
		_refresh_start()


func _on_local_failed(message: String) -> void:
	# Refus de la carte : message clair, on reste dans le salon.
	_status.text = Lang.t("Carte de l'hôte refusée : %s", "Host's map refused: %s") % message
	_refresh_map()


func _on_start() -> void:
	if not is_host or Net.players.is_empty() or _launching:
		return
	var target := Net.lobby_map if map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) else map_id
	if not Net.start_match(target):
		_refresh_start()
		return
	_launching = true
	_start.disabled = true
	_status.text = Lang.t("Lancement...", "Starting...")


func back() -> void:
	Net.leave()
	GameState.reset_to_menu()
	menu.show_screen("multiplayer", {}, false)
