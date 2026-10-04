class_name McpDialog
extends AcceptDialog
## Collaboration > Connecter une IA (MCP)… (docs/MCP.md) : état du serveur
## MCP du jeu (écoute, port, désactivé), adresse, jeton masqué (« Afficher »),
## commande Claude Code et configuration JSON à copier, nouveau jeton, case
## pour activer le serveur. Prévient quand le port n'est pas 7791 (la
## configuration de l'IA devra changer).

var ed: MapEditor
var srv: Node
var _state: Label
var _warn: Label
var _url: LineEdit
var _token: LineEdit
var _show: CheckBox
var _enable: CheckBox


static func open(editor: MapEditor) -> McpDialog:
	var d := McpDialog.new()
	d.ed = editor
	d.srv = MapEditor.mcp_server()
	if d.srv == null:
		d.free()
		return null
	editor.add_child(d)
	d._build()
	d.popup_centered()
	return d


func _build() -> void:
	title = Lang.t("Connecter une IA (MCP)", "Connect an AI (MCP)")
	ok_button_text = Lang.t("Fermer", "Close")
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(EditorUi.px(8)))
	box.custom_minimum_size = Vector2(EditorUi.px(640), 0)
	add_child(box)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = Lang.t(
		"Une IA comme Claude Code peut lire la carte ouverte et y poser des éléments, en direct. Le jeu est lui-même le serveur MCP : rien d'autre à installer. Il n'écoute que sur cet ordinateur (127.0.0.1) et exige le jeton ci-dessous.",
		"An AI such as Claude Code can read the open map and place elements, live. The game itself is the MCP server: nothing else to install. It only listens on this computer (127.0.0.1) and requires the token below.")
	box.add_child(intro)
	_enable = CheckBox.new()
	_enable.text = Lang.t("Activer le serveur MCP (autoriser une IA)", "Enable the MCP server (allow an AI)")
	_enable.toggled.connect(func(on: bool): ed.set_claude_allowed(on))
	box.add_child(_enable)
	_state = Label.new()
	box.add_child(_state)
	_warn = Label.new()
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	box.add_child(_warn)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", int(EditorUi.px(10)))
	box.add_child(g)
	var l := Label.new()
	l.text = Lang.t("Adresse", "URL")
	g.add_child(l)
	_url = LineEdit.new()
	_url.editable = false
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(_url)
	l = Label.new()
	l.text = Lang.t("Jeton", "Token")
	g.add_child(l)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(row)
	_token = LineEdit.new()
	_token.editable = false
	_token.secret = true
	_token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_token)
	_show = CheckBox.new()
	_show.text = Lang.t("Afficher", "Show")
	_show.toggled.connect(func(on: bool): _token.secret = not on)
	row.add_child(_show)
	var btns := HFlowContainer.new()
	box.add_child(btns)
	_button(btns, Lang.t("Copier la commande Claude Code", "Copy the Claude Code command"), func():
		DisplayServer.clipboard_set(srv.claude_command())
		ed.set_status(Lang.t("Commande copiée : collez-la dans un terminal, puis lancez claude", "Command copied: paste it in a terminal, then start claude")))
	_button(btns, Lang.t("Copier la config JSON", "Copy the JSON config"), func():
		DisplayServer.clipboard_set(srv.json_config())
		ed.set_status(Lang.t("Configuration JSON copiée (clients MCP « http »)", "JSON config copied (\"http\" MCP clients)")))
	_button(btns, Lang.t("Régénérer le jeton", "Regenerate the token"), func():
		srv.regenerate_token()
		ed.set_status(Lang.t("Nouveau jeton : refaites la configuration de l'IA (l'ancien ne marche plus)", "New token: set the AI up again (the old one no longer works)")))
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = Lang.t(
		"Claude Code : collez la commande copiée dans un terminal (une seule fois), puis lancez « claude ». Le jeu doit tourner, éditeur de cartes ouvert sur la carte voulue. Si le jeu n'était pas lancé au démarrage de Claude Code, tapez /mcp dans Claude Code pour reconnecter « map-editor ».\nAutre client MCP : transport « HTTP » (Streamable HTTP), avec l'adresse et l'en-tête Authorization de la config JSON.",
		"Claude Code: paste the copied command in a terminal (once), then start \"claude\". The game must be running, with the map editor open on the wanted map. If the game was not running when Claude Code started, type /mcp in Claude Code to reconnect \"map-editor\".\nOther MCP client: \"HTTP\" (Streamable HTTP) transport, with the URL and the Authorization header of the JSON config.")
	box.add_child(help)
	srv.state_changed.connect(refresh)
	refresh()


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func refresh() -> void:
	if srv == null:
		return
	_enable.set_pressed_no_signal(bool(Settings.mcp_enabled))
	var on: bool = srv.is_running()
	if on:
		_state.text = Lang.t("État : à l'écoute sur 127.0.0.1, port %d", "Status: listening on 127.0.0.1, port %d") % int(srv.port)
	elif Settings.mcp_enabled and String(srv.error) != "":
		_state.text = Lang.t("État : arrêté (%s)", "Status: stopped (%s)") % String(srv.error)
	else:
		_state.text = Lang.t("État : désactivé", "Status: disabled")
	_warn.visible = on and int(srv.port) != srv.FIRST_PORT
	_warn.text = Lang.t(
		"Attention : le port %d était pris, le serveur écoute sur le port %d. Une IA configurée avec le port %d ne le trouvera pas : recopiez la commande ou la config ci-dessous (ou libérez le port %d et relancez le jeu)." ,
		"Warning: port %d was taken, the server listens on port %d. An AI set up with port %d will not find it: copy the command or the config below again (or free port %d and restart the game).") % [srv.FIRST_PORT, int(srv.port), srv.FIRST_PORT, srv.FIRST_PORT]
	_url.text = srv.url()
	_token.text = srv.get_token()
