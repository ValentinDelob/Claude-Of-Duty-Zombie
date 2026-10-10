class_name PauseMenu
extends MenuHost
## Menu pause ([Échap]) : REPRENDRE, OPTIONS, QUITTER LA PARTIE, QUITTER LE JEU.
## En solo la partie est suspendue (comme BO1) ; en multijoueur elle continue
## (les zombies ne vous attendent pas) mais le joueur local ne bouge plus et
## ne tire plus tant que le menu est ouvert (Player : entrées ignorées,
## souris libérée).
##
## OPTIONS ouvre l'écran d'options du menu principal (même script,
## MainMenu.SCREENS.options) par-dessus la partie ; RETOUR ou Échap revient ici.

var game: Game
var _first: Button
var _options_btn: Button
var _where: Label
var _sub: Label
var _bg: ColorRect
var _root: VBoxContainer
var _hint: Label


func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.72)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_hint = UiStyle.label("", 17, UiStyle.DIM)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 112
	_hint.offset_top = -64
	_hint.offset_right = 1100
	_hint.offset_bottom = -36
	add_child(_hint)
	visible = false


## Colonne principale, reconstruite à chaque ouverture (langue à jour).
func _build_root() -> void:
	if _root:
		remove_child(_root)
		_root.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 110
	col.offset_top = -160
	add_child(col)
	move_child(col, _bg.get_index() + 1)
	_root = col
	col.add_child(MenuStyle.title("PAUSE", 54))
	_sub = UiStyle.label(Lang.t("La partie continue pour vos coéquipiers.", "The game goes on for your teammates.") if Net.is_online()
			else Lang.t("Partie suspendue.", "Game paused."), 18, UiStyle.DIM)
	col.add_child(_sub)
	# Carte et manche en cours (comme l'en-tête du menu pause de BO1).
	_where = HudStyle.label("", 20, HudStyle.TEXT, "condensed", 3)
	col.add_child(_where)
	col.add_child(UiStyle.label("", 10))
	_first = _button(Lang.t("REPRENDRE", "RESUME"), close, Lang.t("Retour à la partie.", "Back to the game."))
	col.add_child(_first)
	_options_btn = _button("OPTIONS", func(): show_screen("options"),
			Lang.t("Commandes, touches, graphismes, son.", "Controls, keys, graphics, audio."))
	col.add_child(_options_btn)
	col.add_child(_button(Lang.t("QUITTER LA PARTIE", "QUIT GAME"), _leave, Lang.t("Retour au menu principal.", "Back to the main menu.")))
	col.add_child(_button(Lang.t("QUITTER LE JEU", "QUIT TO DESKTOP"), _quit_game, Lang.t("Retour au bureau.", "Back to the desktop.")))
	if game and game.map_def:
		var n: int = game.rounds.round_n if game.rounds else 0
		_where.text = game.map_def.display_name + (("   —   " + Lang.t("MANCHE %d", "ROUND %d") % n) if n > 0 else "")


func _button(label: String, cb: Callable, hint: String) -> Button:
	var b := MenuStyle.button(label, cb, hint)
	b.focus_entered.connect(func(): set_hint(hint))
	return b


func open() -> void:
	_close_screen()
	_build_root()
	visible = true
	_bg.color.a = 0.72
	game.capture_mouse(false)
	if not Net.is_online():
		get_tree().paused = true
	_first.grab_focus.call_deferred()


func close() -> void:
	_close_screen()
	visible = false
	get_tree().paused = false
	game.capture_mouse(true)


## Échap (ou B / Retour) : ferme l'écran d'options, sinon reprend la partie.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if current:
			current.back()
		else:
			close()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# MenuHost : écran d'options par-dessus la partie
# --------------------------------------------------------------------------

func show_screen(screen_name: String, args := {}, _remember := true) -> void:
	if screen_name != "options" or current:
		return
	var script := load(MainMenu.SCREENS.options) as GDScript
	if script == null:
		push_error("[PauseMenu] écran des options introuvable")
		return
	var s: MenuScreen = script.new()
	s.menu = self
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	current = s
	current_name = screen_name
	_root.visible = false
	_bg.color.a = 0.86
	_hint.text = ""
	add_child(s)
	move_child(s, _bg.get_index() + 1)
	s.modulate.a = 0.0
	var a := args.duplicate()
	a.in_game = true
	s.enter(a)
	s.create_tween().tween_property(s, "modulate:a", 1.0, 0.18)


func go_back() -> void:
	if current == null:
		return
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	_close_screen()
	_build_root()  # langue éventuellement changée dans les options
	_options_btn.grab_focus.call_deferred()


func _close_screen() -> void:
	if current == null:
		return
	var s := current
	current = null
	current_name = ""
	s.exit()
	var fo := get_viewport().gui_get_focus_owner()
	if fo and s.is_ancestor_of(fo):
		fo.release_focus()
	remove_child(s)
	s.queue_free()
	_bg.color.a = 0.72
	_hint.text = ""


func set_hint(t: String) -> void:
	_hint.text = t


func _leave() -> void:
	get_tree().paused = false
	# L'XP déjà gagnée dans la partie est gardée (GAME_CONCEPT §4.15).
	if game:
		game.keep_match_xp()
	Router.back_to_menu()


func _quit_game() -> void:
	if game:
		game.keep_match_xp()
	Router.quit_game()
