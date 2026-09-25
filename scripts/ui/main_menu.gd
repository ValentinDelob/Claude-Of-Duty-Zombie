class_name MainMenu
extends Control
## Racine des menus : fond, écran courant, transitions, messages d'erreur.
## Les écrans (MenuScreen) sont créés à la demande.

const SCREENS := {
	"main": "res://scripts/ui/screens/main_screen.gd",
	"multiplayer": "res://scripts/ui/screens/multiplayer_screen.gd",
	"host": "res://scripts/ui/screens/host_screen.gd",
	"lobby": "res://scripts/ui/screens/lobby_screen.gd",
	"message": "res://scripts/ui/screens/message_screen.gd",
}

var current: MenuScreen
var current_name := ""
var _layer: Control
var _history: Array[String] = []


func _ready() -> void:
	if GameState.state != GameState.State.LOBBY:
		GameState.reset_to_menu()
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.012, 0.012)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	Net.connection_error.connect(_on_connection_error)
	Net.session_ended.connect(_on_session_ended)
	Net.joined_server.connect(_on_joined)
	if Router.pending_message != "":
		show_screen("main")
		show_message("PARTIE TERMINÉE", Router.pending_message)
		Router.pending_message = ""
	else:
		show_screen("main")
	Audio.play_music("", 0.0)


func show_screen(screen_name: String, args := {}, remember := true) -> void:
	if current:
		if remember and current_name != "message":
			_history.append(current_name)
		current.exit()
		current.queue_free()
	var s: MenuScreen = load(SCREENS[screen_name]).new()
	s.menu = self
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(s)
	current = s
	current_name = screen_name
	s.modulate.a = 0.0
	s.enter(args)
	create_tween().tween_property(s, "modulate:a", 1.0, 0.35)


## Revient à l'écran précédent.
func go_back() -> void:
	Audio.play_ui("ui_back", -4.0)
	var prev: String = _history.pop_back() if not _history.is_empty() else "main"
	show_screen(prev, {}, false)


func show_message(t: String, body: String, back_to := "") -> void:
	show_screen("message", {"title": t, "body": body, "back_to": back_to})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and current:
		current.back()


func _on_connection_error(t: String, m: String) -> void:
	if GameState.state == GameState.State.CONNECTING:
		GameState.set_state(GameState.State.MAIN_MENU)
	show_message(t, m, "multiplayer")


func _on_session_ended(reason: String) -> void:
	GameState.reset_to_menu()
	show_message("DÉCONNECTÉ", reason, "multiplayer")


## Client accepté par un hôte : direction le salon.
func _on_joined() -> void:
	if GameState.state == GameState.State.CONNECTING:
		GameState.set_state(GameState.State.LOBBY)
	elif GameState.state == GameState.State.MAIN_MENU:
		GameState.set_state(GameState.State.LOBBY)
	show_screen("lobby", {"host": false})
