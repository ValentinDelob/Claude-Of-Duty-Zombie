class_name MainMenu
extends Control
## Racine des menus : fond, écran courant, transitions, messages d'erreur.
## Les écrans (MenuScreen) sont créés à la demande.
##
## Les menus sont pensés pour une toile de 1280x720 : tant que le menu est
## affiché, la fenêtre passe en mise à l'échelle « canvas_items » (texte net
## en 1080p et plus) ; le réglage précédent est restauré à la sortie.

const SCREENS := {
	"main": "res://scripts/ui/screens/main_screen.gd",
	"multiplayer": "res://scripts/ui/screens/multiplayer_screen.gd",
	"host": "res://scripts/ui/screens/host_screen.gd",
	"lobby": "res://scripts/ui/screens/lobby_screen.gd",
	"join": "res://scripts/ui/screens/join_screen.gd",
	"connecting": "res://scripts/ui/screens/connecting_screen.gd",
	"message": "res://scripts/ui/screens/message_screen.gd",
	"options": "res://scripts/ui/screens/options_screen.gd",
	"credits": "res://scripts/ui/screens/credits_screen.gd",
}
const BASE_SIZE := Vector2i(1280, 720)
## Durées des transitions (fondu au noir puis retour).
const FADE_IN := 0.16
const FADE_OUT := 0.55

var current: MenuScreen
var current_name := ""
var _layer: Control
var _history: Array[String] = []
var _fade: ColorRect
var _fade_mat: ShaderMaterial
var _fade_tween: Tween
var _fade_amount := 0.0
var _hint: Label
var _saved_scale := {}


func _ready() -> void:
	if GameState.state != GameState.State.LOBBY:
		GameState.reset_to_menu()
	_setup_scaling()
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.012, 0.012)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_hint = UiStyle.label("", 17, UiStyle.DIM)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 112
	_hint.offset_top = -64
	_hint.offset_right = 900
	_hint.offset_bottom = -36
	add_child(_hint)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = preload("res://assets/shaders/menu_fade.gdshader")
	_fade.material = _fade_mat
	add_child(_fade)
	Net.connection_error.connect(_on_connection_error)
	Net.session_ended.connect(_on_session_ended)
	Net.joined_server.connect(_on_joined)
	if Router.pending_message != "":
		show_screen("main")
		show_message("PARTIE TERMINÉE", Router.pending_message)
		Router.pending_message = ""
	else:
		show_screen("main")
	# Ouverture : sortie lente du noir.
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_set_fade(1.0)
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	Audio.play_music("", 0.0)


func _exit_tree() -> void:
	var w := get_window()
	if w and not _saved_scale.is_empty():
		w.content_scale_mode = _saved_scale.mode
		w.content_scale_aspect = _saved_scale.aspect
		w.content_scale_size = _saved_scale.size


func _setup_scaling() -> void:
	var w := get_window()
	if w == null:
		return
	_saved_scale = {"mode": w.content_scale_mode, "aspect": w.content_scale_aspect, "size": w.content_scale_size}
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = BASE_SIZE


func show_screen(screen_name: String, args := {}, remember := true) -> void:
	var old := current
	if old:
		if remember and current_name != "message":
			_history.append(current_name)
		old.exit()
		_retire(old)
	_hint.text = ""
	var s: MenuScreen = load(SCREENS[screen_name]).new()
	s.menu = self
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(s)
	current = s
	current_name = screen_name
	s.modulate.a = 0.0
	s.enter(args)
	# Transition : court passage au noir bruité, puis l'écran émerge.
	if old:
		_transition()
	var tw := s.create_tween()
	tw.tween_interval(FADE_IN if old else 0.2)
	tw.tween_property(s, "modulate:a", 1.0, FADE_OUT).set_trans(Tween.TRANS_SINE)


## L'ancien écran s'efface pendant que le noir monte, puis disparaît.
func _retire(old: MenuScreen) -> void:
	var fo := get_viewport().gui_get_focus_owner()
	if fo and old.is_ancestor_of(fo):
		fo.release_focus()
	old.process_mode = Node.PROCESS_MODE_DISABLED
	_set_mouse_ignore(old)
	var tw := create_tween()
	tw.tween_property(old, "modulate:a", 0.0, FADE_IN)
	tw.tween_callback(old.queue_free)


func _set_mouse_ignore(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(n as Control).focus_mode = Control.FOCUS_NONE
	for c in n.get_children():
		_set_mouse_ignore(c)


func _transition() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	var start := _fade_amount
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, start, 1.0, FADE_IN * (1.0 - start))
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE)


func _set_fade(v: float) -> void:
	_fade_amount = v
	_fade_mat.set_shader_parameter("amount", v)
	_fade.visible = v > 0.001


## Fondu au noir complet puis appel de `then` (lancement d'une partie...).
func fade_to_black(duration: float, then: Callable) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var start := _fade_amount
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, start, 1.0, duration).set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_interval(0.15)
	_fade_tween.tween_callback(then)


## Texte d'aide en bas de l'écran (description de l'élément sélectionné).
func set_hint(t: String) -> void:
	_hint.text = t


## Revient à l'écran précédent.
func go_back() -> void:
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
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
	show_message(t, m, "join" if current_name == "connecting" else "multiplayer")


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
