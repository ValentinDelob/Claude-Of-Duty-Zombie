class_name MainMenu
extends MenuHost
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
	"career": "res://scripts/ui/screens/career_screen.gd",
	"map_select": "res://scripts/ui/screens/map_screen.gd",
}
## Durées des transitions (fondu au noir puis retour).
const FADE_IN := 0.22
const FADE_OUT := 0.7
const MUSIC := "menu_theme"
const MUSIC_DB := -3.0
const MENU_3D_SCALE := 0.75

var _layer: Control
var _history: Array[String] = []
var _fade: ColorRect
var _fade_mat: ShaderMaterial
var _fade_tween: Tween
var _fade_amount := 0.0
var _hint: Label
var _saved_scale := {}
var backdrop: MenuBackdrop
var _post: ColorRect
var _post_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _next_glitch := 8.0
var _glitch_left := 0.0
var _glitch_power := 0.0


func _ready() -> void:
	if GameState.state != GameState.State.LOBBY:
		GameState.reset_to_menu()
	_setup_scaling()
	# Fond 3D (bunker) puis voile sombre à gauche pour la lisibilité.
	backdrop = MenuBackdrop.new()
	add_child(backdrop)
	backdrop.presence.connect(_on_presence)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.82))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.38, Color(0, 0, 0, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.72, 0)
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
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
	var hud := MenuHud.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hud)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = preload("res://assets/shaders/menu_fade.gdshader")
	_fade.material = _fade_mat
	add_child(_fade)
	# Post-traitement plein écran (grain, vignette, balayage, parasites).
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = preload("res://assets/shaders/menu_post.gdshader")
	_post.material = _post_mat
	add_child(_post)
	_rng.randomize()
	Net.connection_error.connect(_on_connection_error)
	Net.session_ended.connect(_on_session_ended)
	Net.joined_server.connect(_on_joined)
	if GameState.state == GameState.State.LOBBY and Net.is_online():
		# Fin d'une partie multijoueur (Router.back_to_lobby) : tout le groupe
		# revient au salon, toujours connecté.
		show_screen("lobby", {"host": Net.mode == Net.Mode.HOST})
	elif Router.pending_message != "":
		show_screen("main")
		show_message(Lang.t("PARTIE TERMINÉE", "GAME OVER"), Router.pending_message)
		Router.pending_message = ""
	else:
		show_screen("main")
	# Ouverture : sortie lente du noir.
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_set_fade(1.0)
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, 2.4).set_trans(Tween.TRANS_SINE)
	glitch(0.35, 0.8)
	Audio.play_music(MUSIC, MUSIC_DB, 3.0)


func _process(delta: float) -> void:
	# Parasites vidéo : rares salves spontanées + celles demandées.
	_next_glitch -= delta
	if _next_glitch <= 0.0:
		_next_glitch = _rng.randf_range(6.0, 14.0)
		glitch(_rng.randf_range(0.08, 0.25), _rng.randf_range(0.3, 0.8))
	var g := 0.0
	if _glitch_left > 0.0:
		_glitch_left -= delta
		g = _glitch_power * _rng.randf_range(0.5, 1.0)
	_post_mat.set_shader_parameter("glitch", g)


## Salve de parasites vidéo sur tout l'écran.
func glitch(duration: float, power := 1.0) -> void:
	if _glitch_left <= 0.0:
		_glitch_power = power
	else:
		_glitch_power = maxf(_glitch_power, power)
	_glitch_left = maxf(_glitch_left, duration)


## Lancement d'une partie : la lampe meurt, l'image décroche, fondu au noir
## sur le fracas d'une porte blindée, puis `then` (chargement).
func launch(then: Callable, duration := 1.8) -> void:
	Audio.play_ui("menu_start", -2.0)
	Audio.stop_music(duration)
	glitch(0.45, 1.0)
	backdrop.blackout(duration + 1.0)
	backdrop.force_figure(true)  # dernière image : elle est là, dans la porte
	fade_to_black(duration, then)


## La silhouette du fond apparaît : râle lointain et image qui décroche.
func _on_presence(shown: bool) -> void:
	if shown:
		Audio.play_ui("menu_presence", -9.0)
		glitch(0.3, 0.9)
	else:
		glitch(0.12, 0.5)


func _exit_tree() -> void:
	var w := get_window()
	if w and not _saved_scale.is_empty():
		# Résolution 3D : restaurée seulement si personne ne l'a changée entre-temps
		# (préréglages de qualité appliqués depuis les options).
		if is_equal_approx(w.scaling_3d_scale, MENU_3D_SCALE):
			w.scaling_3d_scale = _saved_scale.scale_3d


func _setup_scaling() -> void:
	var w := get_window()
	if w == null:
		return
	_saved_scale = {"scale_3d": w.scaling_3d_scale}
	# Le fond 3D, sous le grain et la vignette, est rendu à 75 % de la
	# définition : invisible à l'œil, nettement moins coûteux (GTX 1050).
	w.scaling_3d_scale = minf(w.scaling_3d_scale, MENU_3D_SCALE)
	# L'interface (menu et HUD) suit la résolution : mise à l'échelle 2D du
	# projet (display/window/stretch = canvas_items, base 1280x720).


func show_screen(screen_name: String, args := {}, remember := true) -> void:
	var old := current
	if old:
		if remember and current_name != "message":
			_history.append(current_name)
		old.exit()
		_retire(old)
	_hint.text = ""
	var script := load(SCREENS[screen_name]) as GDScript
	if script == null:
		push_error("[MainMenu] écran introuvable : " + str(SCREENS[screen_name]))
		return
	var s: MenuScreen = script.new()
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
	Audio.play_ui("menu_whoosh", -12.0)
	glitch(0.1, 0.35)


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
	show_message(Lang.t("DÉCONNECTÉ", "DISCONNECTED"), reason, "multiplayer")


## Client accepté par un hôte : direction le salon.
func _on_joined() -> void:
	if GameState.state == GameState.State.CONNECTING:
		GameState.set_state(GameState.State.LOBBY)
	elif GameState.state == GameState.State.MAIN_MENU:
		GameState.set_state(GameState.State.LOBBY)
	show_screen("lobby", {"host": false})
