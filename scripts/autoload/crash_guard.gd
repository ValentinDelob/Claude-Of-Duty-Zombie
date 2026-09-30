extends Node
## CrashGuard — journal de session et trace des plantages (CrashLog,
## docs/ARCHITECTURE.md « Journaux et plantages »). Premier autoload (après Packs,
## qui ne fait que monter des paquets) : la
## session commence avant tout le reste.
##
## Chez le joueur (exe exporté) : marqueur « session en cours » posé au
## démarrage (version, heure, écran courant, journal), mis à jour à chaque
## changement d'écran, retiré à la fermeture normale (menu Quitter, fenêtre
## fermée, retour au lanceur : l'arbre se termine toujours par _exit_tree). Un
## marqueur resté d'une session précédente = plantage : rapport dans
## user://crashes/ et message discret au menu principal.
## Dans les tests (binaire de l'éditeur, --log-file) : seulement les lignes de
## contexte du journal, rien n'est écrit dans les données du joueur.

## Marqueur et rapports actifs (session d'un joueur).
var active := false
## Dossier des données (marqueurs, crashes/).
var root := ""
## Rapports créés au démarrage (plantages des sessions précédentes).
var reports := PackedStringArray()
var _screen := ""
var _poll := 0.0
var _notice_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = CrashLog.player_session()
	if not active:
		return
	root = OS.get_user_data_dir()
	reports = CrashLog.begin_session(root, CrashLog.log_path(), {"programme": "Claude of Duty Zombie",
		"version": str(ProjectSettings.get_setting("application/config/version", "?")), "ecran": "démarrage"})
	for r in reports:
		print("[Session] la session précédente a planté : rapport ", r)


## Ligne de contexte du journal (vidé à chaque ligne). `mark` : notée aussi
## dans le marqueur (rare : elle figurera dans le rapport d'un plantage).
func context(text: String, mark := false) -> void:
	print("[Session] ", text)
	if mark and active:
		CrashLog.update_marker(root, "contexte", text)


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	var s := get_tree().current_scene
	var sname := String(s.name) if s != null else ""
	if sname == _screen:
		return
	_screen = sname
	print("[Session] écran : ", sname)
	if active:
		CrashLog.update_marker(root, "ecran", sname)
	if sname == "MainMenu" and not reports.is_empty() and not _notice_shown:
		_notice_shown = true
		_show_notice(reports[reports.size() - 1])


func _exit_tree() -> void:
	if active:
		print("[Session] fermeture normale")
		CrashLog.end_session(root)
		active = false


## Texte du message au joueur après un plantage.
static func notice_text(report: String) -> String:
	return Lang.t("La dernière session s'est arrêtée brutalement. Un rapport a été enregistré : %s",
		"The last session stopped unexpectedly. A report was saved: %s") % report.replace("/", "\\")


## Message discret en bas de l'écran (20 s) ; bouton pour ouvrir le dossier.
func _show_notice(report: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "CrashNotice"
	layer.layer = 90
	add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.035, 0.85)
	sb.border_color = Color(0.62, 0.05, 0.04, 0.8)
	sb.border_width_left = 3
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_top = -86
	panel.offset_bottom = -16
	panel.offset_right = 760
	layer.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var l := Label.new()
	l.text = notice_text(report)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	row.add_child(l)
	var open := Button.new()
	open.text = Lang.t("Ouvrir le dossier", "Open folder")
	open.focus_mode = Control.FOCUS_NONE
	open.pressed.connect(func(): OS.shell_open(report.get_base_dir()))
	row.add_child(open)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(layer.queue_free)
	row.add_child(close)
	get_tree().create_timer(20.0).timeout.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())
