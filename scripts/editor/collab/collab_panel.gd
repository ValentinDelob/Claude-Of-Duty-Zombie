class_name CollabPanel
extends Node
## Interface minimale de la collaboration (docs/MAP_COLLAB.md § 6) : menu
## « Collaboration » de la barre du haut (Héberger…, Rejoindre…, Infos de la
## session…, Quitter la session, Autoriser Claude (MCP)), pastilles colorées
## des participants à côté. Le rendu riche (historique, sélections des
## autres, bulles de Claude) viendra par-dessus.

const ID_HOST := 0
const ID_JOIN := 1
const ID_LEAVE := 2
const ID_CLAUDE := 3
const ID_INFO := 4

var ed: MapEditor
var menu: MenuButton
## Pastilles des participants (cachées sans session ni Claude).
var pills: HBoxContainer


func setup(editor: MapEditor) -> void:
	ed = editor
	menu = MenuButton.new()
	menu.name = "CollabMenu"
	menu.text = Lang.t("Collaboration", "Collaboration")
	menu.flat = false
	ed.top_bar.add_child(menu)
	ed.top_bar.move_child(menu, ed.edit_menu.get_index() + 1)
	var pm := menu.get_popup()
	pm.add_item(Lang.t("Héberger…", "Host…"), ID_HOST)
	pm.add_item(Lang.t("Rejoindre…", "Join…"), ID_JOIN)
	pm.add_item(Lang.t("Infos de la session…", "Session info…"), ID_INFO)
	pm.add_item(Lang.t("Quitter la session", "Leave the session"), ID_LEAVE)
	pm.add_separator()
	pm.add_check_item(Lang.t("Autoriser Claude (MCP)", "Allow Claude (MCP)"), ID_CLAUDE)
	pm.id_pressed.connect(_on_menu)
	pm.about_to_popup.connect(_refresh_menu)
	pills = HBoxContainer.new()
	pills.name = "CollabPeers"
	pills.visible = false
	pills.add_theme_constant_override("separation", 8)
	ed.top_bar.add_child(pills)
	ed.top_bar.move_child(pills, menu.get_index() + 1)
	ed.collab.peers_changed.connect(refresh)
	ed.collab.session_changed.connect(refresh)
	refresh()


func _refresh_menu() -> void:
	var pm := menu.get_popup()
	var on := ed.collab.is_session()
	pm.set_item_disabled(pm.get_item_index(ID_LEAVE), not on)
	pm.set_item_disabled(pm.get_item_index(ID_INFO), ed.collab.role != MapCollab.Role.HOST)
	pm.set_item_checked(pm.get_item_index(ID_CLAUDE), MapEditor.pref("collab_claude", true))
	pm.set_item_tooltip(pm.get_item_index(ID_CLAUDE), Lang.t(
		"Claude (Claude Code, serveur MCP) peut lire la carte et y poser des éléments. Écoute sur cet ordinateur seulement (127.0.0.1, port %s)." % (str(ed.agent_link.port) if ed.agent_link != null and ed.agent_link.is_running() else "7791"),
		"Claude (Claude Code, MCP server) can read the map and place elements. Listens on this computer only (127.0.0.1, port %s)." % (str(ed.agent_link.port) if ed.agent_link != null and ed.agent_link.is_running() else "7791")))


func _on_menu(id: int) -> void:
	match id:
		ID_HOST:
			host_dialog()
		ID_JOIN:
			join_dialog()
		ID_INFO:
			show_info()
		ID_LEAVE:
			ed.collab.leave()
			ed.set_status(Lang.t("Session quittée : la carte reste ici", "Session left: the map stays here"))
		ID_CLAUDE:
			var on := not bool(MapEditor.pref("collab_claude", true))
			ed.set_claude_allowed(on)


## Participants (pastilles) et libellé de Fichier > Enregistrer (invité :
## une copie).
func refresh() -> void:
	for c in pills.get_children():
		c.queue_free()
	var list := ed.collab.peer_list()
	pills.visible = list.size() > 1
	for p in list:
		var l := Label.new()
		var me := String(p.id) == ed.collab.my_id
		l.text = ("◆ " if p.kind == "agent" else "● ") + String(p.name) + (Lang.t(" (vous)", " (you)") if me else "")
		l.add_theme_color_override("font_color", Color.html(String(p.color)))
		l.tooltip_text = Lang.t("Claude, rattaché à %s", "Claude, attached to %s") % ed.collab.peer_name(MapHistory.root_of(String(p.id))) if p.kind == "agent" else String(p.name)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		pills.add_child(l)
	var fm := ed.file_menu.get_popup()
	var i := fm.get_item_index(2)
	if i >= 0:
		fm.set_item_text(i, Lang.t("Enregistrer une copie…", "Save a copy…") if ed.collab.role == MapCollab.Role.GUEST else Lang.t("Enregistrer", "Save") + "   Ctrl+S")


## Pseudo par défaut : celui des réglages du jeu.
static func default_name() -> String:
	return String(MapEditor.pref("collab_name", Settings.player_name))


func _grid(d: ConfirmationDialog) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	d.add_child(g)
	return g


func _field(g: GridContainer, label: String, value: String, width := 220.0) -> LineEdit:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(width, 0)
	g.add_child(e)
	return e


func _port_field(g: GridContainer, value: int) -> SpinBox:
	var l := Label.new()
	l.text = Lang.t("Port", "Port")
	g.add_child(l)
	var s := SpinBox.new()
	s.min_value = 1024
	s.max_value = 65535
	s.value = value
	s.custom_minimum_size = Vector2(140, 0)
	g.add_child(s)
	return s


func _dialog(title: String, ok: String) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = title
	d.ok_button_text = ok
	d.cancel_button_text = Lang.t("Annuler", "Cancel")
	ed.add_child(d)
	d.canceled.connect(d.queue_free)
	return d


## Héberger : port et pseudo, puis le code de session et l'adresse à donner.
func host_dialog() -> void:
	var d := _dialog(Lang.t("Héberger une session", "Host a session"), Lang.t("Héberger", "Host"))
	var g := _grid(d)
	var port := _port_field(g, int(MapEditor.pref("collab_port", MapCollab.DEFAULT_PORT)))
	var nm := _field(g, Lang.t("Pseudo", "Nickname"), default_name())
	d.confirmed.connect(func():
		d.queue_free()
		var err := ed.collab.host(int(port.value), nm.text)
		if err != OK:
			ed.set_status(Lang.t("Hébergement impossible : le port %d est peut-être déjà pris (%s)", "Cannot host: port %d may already be in use (%s)") % [int(port.value), error_string(err)], true)
			return
		MapEditor.set_pref("collab_port", int(port.value))
		MapEditor.set_pref("collab_name", nm.text.strip_edges())
		show_info())
	d.popup_centered()


## Code de session et adresses locales à donner aux invités.
func show_info() -> void:
	var c := ed.collab
	if c.role != MapCollab.Role.HOST:
		return
	var ips := Net.local_ipv4_addresses()
	ed.set_status(Lang.t("Session ouverte : code %s, port %d", "Session open: code %s, port %d") % [c.session_code, c.port])
	ed._info(Lang.t("Session ouverte", "Session open"), Lang.t(
		"Code de session : %s\nAdresse de cet ordinateur : %s\nPort : %d\n\nLes autres : Collaboration > Rejoindre…, avec cette adresse, ce port et ce code.\nPar Internet : redirigez le port %d (TCP) vers cet ordinateur sur votre box.",
		"Session code: %s\nThis computer's address: %s\nPort: %d\n\nThe others: Collaboration > Join…, with this address, port and code.\nOver the Internet: forward port %d (TCP) to this computer on your router.") % [
		c.session_code, ", ".join(ips) if not ips.is_empty() else "127.0.0.1", c.port, c.port])


## Rejoindre : adresse, port, code, pseudo. La carte de l'hôte remplace celle
## d'ici (elle reste dans la sauvegarde automatique).
func join_dialog() -> void:
	var d := _dialog(Lang.t("Rejoindre une session", "Join a session"), Lang.t("Rejoindre", "Join"))
	var g := _grid(d)
	var addr := _field(g, Lang.t("Adresse de l'hôte", "Host address"), String(MapEditor.pref("collab_addr", "192.168.1.")))
	var port := _port_field(g, int(MapEditor.pref("collab_port", MapCollab.DEFAULT_PORT)))
	var code := _field(g, Lang.t("Code de session", "Session code"), "", 120.0)
	var nm := _field(g, Lang.t("Pseudo", "Nickname"), default_name())
	d.confirmed.connect(func():
		d.queue_free()
		var a := addr.text.strip_edges()
		if not Net.is_valid_ipv4(a):
			ed.set_status(Lang.t("« %s » n'est pas une adresse IPv4 valide (exemple : 192.168.1.25)", "\"%s\" is not a valid IPv4 address (example: 192.168.1.25)") % a, true)
			return
		MapEditor.set_pref("collab_addr", a)
		MapEditor.set_pref("collab_port", int(port.value))
		MapEditor.set_pref("collab_name", nm.text.strip_edges())
		ed.autosave()
		var err := ed.collab.join(a, int(port.value), code.text.strip_edges().to_upper(), nm.text)
		if err != OK:
			ed.set_status(Lang.t("Connexion impossible (%s)", "Cannot connect (%s)") % error_string(err), true)
			return
		ed.set_status(Lang.t("Connexion à %s:%d…", "Connecting to %s:%d…") % [a, int(port.value)]))
	d.popup_centered()
	code.grab_focus.call_deferred()
