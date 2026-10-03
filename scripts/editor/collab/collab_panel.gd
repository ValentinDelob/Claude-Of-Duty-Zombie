class_name CollabPanel
extends Node
## Interface de la collaboration dans la barre du haut (docs/MAP_COLLAB.md
## § 6) : menu « Collaboration » (Héberger…, Rejoindre…, Infos de la
## session…, Quitter la session, Autoriser Claude (MCP), Historique) et
## pastilles des participants à côté : disque de leur couleur avec leur
## initiale (Claude : son icône), pseudo, « Étage N » s'ils sont sur un autre
## étage que celui affiché ; info-bulle avec le rôle et l'étage. Chaque
## pastille est un contrôle de la barre (HFlowContainer) : la barre passe à
## la ligne entre deux pastilles plutôt que de déborder. Le rendu sur le plan
## est dans CollabView, l'historique dans CollabHistory.

const ID_HOST := 0
const ID_JOIN := 1
const ID_LEAVE := 2
const ID_CLAUDE := 3
const ID_INFO := 4
const ID_HISTORY := 5
## Pseudo coupé au-delà (pastille).
const NAME_MAX := 14

var ed: MapEditor
var menu: MenuButton
## Pastilles des participants (aucune sans session ni Claude), rangées
## dans la barre du haut juste après le menu.
var pills: Array = []


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
	pm.add_separator()
	pm.add_item(Lang.t("Historique", "History"), ID_HISTORY)
	pm.id_pressed.connect(_on_menu)
	pm.about_to_popup.connect(_refresh_menu)
	ed.collab.peers_changed.connect(refresh)
	ed.collab.session_changed.connect(refresh)
	Settings.editor_ui_scale_changed.connect(func(_v): update_pills())
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
		ID_HISTORY:
			ed.panels.show_tab("history")


## Participants (pastilles) et éléments de Fichier réservés à l'hôte (grisés
## chez l'invité, MapEditor.update_file_menu).
func refresh() -> void:
	for c in pills:
		if is_instance_valid(c):
			ed.top_bar.remove_child(c)
			c.queue_free()
	pills.clear()
	var list := ed.collab.peer_list()
	if list.size() > 1:
		var at := menu.get_index() + 1
		for p in list:
			var pill := Pill.new()
			pill.name = "CollabPeer_" + String(p.id).validate_node_name()
			pill.panel = self
			pill.peer_id = String(p.id)
			pill.agent = p.kind == "agent"
			pill.me = String(p.id) == ed.collab.my_id
			pill.color = Color.html(String(p.color)) if Color.html_is_valid(String(p.color)) else Color.WHITE
			var nm := String(p.name)
			pill.initial = nm.left(1).to_upper() if nm != "" else "?"
			pill.text = (nm.left(NAME_MAX - 1) + "…" if nm.length() > NAME_MAX else nm) + (Lang.t(" (vous)", " (you)") if pill.me else "")
			pill.mouse_filter = Control.MOUSE_FILTER_PASS
			# Tailles calculées en pixels à la taille de l'interface (EditorUi.px).
			pill.set_meta(EditorUi.SKIP, true)
			ed.top_bar.add_child(pill)
			ed.top_bar.move_child(pill, at)
			at += 1
			pills.append(pill)
		update_pills()
	# Invité : Nouvelle, Ouvrir, Enregistrer... grisés (réservés à l'hôte).
	ed.update_file_menu()


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
		"Code de session : %s\nAdresse de cet ordinateur : %s\nPort : %d\n\nLes autres : Collaboration > Rejoindre…, avec cette adresse, ce port et ce code.\n▶ TESTER : tout le monde joue la carte ensemble, puis revient ici.\nPar Internet : redirigez le port %d (TCP et UDP) vers cet ordinateur sur votre box.",
		"Session code: %s\nThis computer's address: %s\nPort: %d\n\nThe others: Collaboration > Join…, with this address, port and code.\n▶ PLAY TEST: everyone plays the map together, then comes back here.\nOver the Internet: forward port %d (TCP and UDP) to this computer on your router.") % [
		c.session_code, ", ".join(ips) if not ips.is_empty() else "127.0.0.1", c.port, c.port])


## Rejoindre : adresse, port, code, pseudo. La carte de l'hôte remplace celle
## d'ici : modifications non enregistrées ici, confirmation d'abord
## (MapEditor.confirm_unsaved : Enregistrer / Quitter sans enregistrer / Annuler).
func join_dialog() -> void:
	ed.confirm_unsaved(Lang.t("rejoindre une session (la carte de l'hôte remplacera celle-ci)", "join a session (the host's map will replace this one)"), _join_dialog)


func _join_dialog() -> void:
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
		var err := ed.collab.join(a, int(port.value), code.text.strip_edges().to_upper(), nm.text)
		if err != OK:
			ed.set_status(Lang.t("Connexion impossible (%s)", "Cannot connect (%s)") % error_string(err), true)
			return
		ed.set_status(Lang.t("Connexion à %s:%d…", "Connecting to %s:%d…") % [a, int(port.value)]))
	d.popup_centered()
	code.grab_focus.call_deferred()


## Étage et info-bulle des pastilles (présence reçue, étage affiché changé,
## taille de l'interface).
func update_pills() -> void:
	for pill in pills:
		if not is_instance_valid(pill):
			continue
		var id := String(pill.peer_id)
		var p: Dictionary = ed.collab.peers.get(id, {})
		var pr: Dictionary = p.get("presence", {})
		var fl := int(pr.get("floor", -1)) if pr.has("cursor") else -1
		pill.floor_text = Lang.t("Étage %d", "Floor %d") % fl if fl >= 0 and fl != ed.floor_k and not pill.me else ""
		pill.tooltip_text = pill_tooltip(id)
		pill.update_minimum_size()
		pill.queue_redraw()


## Info-bulle d'une pastille : pseudo, rôle, étage.
func pill_tooltip(id: String) -> String:
	var c := ed.collab
	var p: Dictionary = c.peers.get(id, {})
	var lines := [String(p.get("name", id))]
	var role := ""
	if p.get("kind", "") == "agent":
		role = Lang.t("Claude (MCP), rattaché à %s", "Claude (MCP), attached to %s") % c.peer_name(MapHistory.root_of(id))
	elif not c.is_session():
		role = Lang.t("seul sur la carte", "alone on the map")
	elif id == "1":
		role = Lang.t("hôte (enregistre la carte)", "host (saves the map)")
	else:
		role = Lang.t("invité", "guest")
	if id == c.my_id:
		role += Lang.t(" — vous", " — you")
	lines.append(role)
	var pr: Dictionary = p.get("presence", {})
	if id == c.my_id:
		lines.append(Lang.t("Étage %d", "Floor %d") % ed.floor_k)
	elif pr.has("cursor"):
		lines.append(Lang.t("Étage %d", "Floor %d") % int(pr.get("floor", 0)))
	return "\n".join(lines)


## Pastille d'un participant : disque de sa couleur avec son initiale (Claude :
## son icône ; vous : anneau clair), pseudo, puis « Étage N » s'il est sur un
## autre étage que celui affiché. Dessinée à la taille de l'interface.
class Pill extends Control:
	var panel: CollabPanel
	var peer_id := ""
	var color := Color.WHITE
	var initial := ""
	var text := ""
	var floor_text := ""
	var agent := false
	var me := false

	func _font() -> Font:
		return get_theme_font("font", "Label")

	func _d() -> float:
		return EditorUi.px(20)

	func _get_minimum_size() -> Vector2:
		var f := _font()
		var w := _d() + EditorUi.px(5) + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13)).x
		if floor_text != "":
			w += EditorUi.px(6) + f.get_string_size(floor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11)).x + EditorUi.px(8)
		return Vector2(ceilf(w + EditorUi.px(2)), maxf(_d(), EditorUi.fs(13) + EditorUi.px(8)))

	func _draw() -> void:
		var f := _font()
		var d := _d()
		var cy := size.y * 0.5
		var c := Vector2(d * 0.5, cy)
		if agent:
			CollabView.draw_claude_icon(self, c, d * 0.5, color, Color.WHITE)
		else:
			draw_circle(c, d * 0.5, color)
			var fs0 := EditorUi.fs(12)
			var iw := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0).x
			draw_string(f, Vector2(c.x - iw * 0.5, cy + fs0 * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, Color(0.06, 0.06, 0.07))
		if me:
			draw_arc(c, d * 0.5 + 1.0, 0, TAU, 24, Color(1, 1, 1, 0.85), 1.5, true)
		var fs := EditorUi.fs(13)
		var x := d + EditorUi.px(5)
		draw_string(f, Vector2(x, cy + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		if floor_text != "":
			x += f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + EditorUi.px(6)
			var fs2 := EditorUi.fs(11)
			var tw := f.get_string_size(floor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			var box := Rect2(x, cy - (fs2 + EditorUi.px(4)) * 0.5, tw + EditorUi.px(8), fs2 + EditorUi.px(4))
			draw_rect(box, Color(color, 0.18))
			draw_rect(box, Color(color, 0.6), false, 1.0)
			draw_string(f, Vector2(x + EditorUi.px(4), cy + fs2 * 0.36), floor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UiStyle.BONE)
