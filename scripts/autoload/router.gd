extends Node
## Router — enchaînement des écrans (menu <-> partie) et fin de session.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Message à afficher par le menu à son retour (ex. « Connexion perdue »).
var pending_message := ""
## Scène où revenir à la fin de la partie au lieu du menu (partie lancée par
## le bouton Tester de l'éditeur de cartes), "" : menu principal.
var return_scene := ""


func start_solo(map_id := "") -> void:
	Net.start_solo(Settings.player_name)
	Net.start_match(map_id if map_id != "" else Game.requested_map())


## Quitte la session en cours et revient au menu principal.
func back_to_menu(reason := "") -> void:
	pending_message = reason
	if GameState.state != GameState.State.MAIN_MENU:
		if not GameState.set_state(GameState.State.DISCONNECTING):
			GameState.reset_to_menu()
	Net.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.stop_music(1.0)
	var target := MENU_SCENE
	if return_scene != "":
		target = return_scene
		return_scene = ""
	get_tree().change_scene_to_file.call_deferred(target)
	if GameState.state == GameState.State.DISCONNECTING:
		GameState.set_state(GameState.State.MAIN_MENU)


## Quitte le jeu proprement (session, sons) : aucune ressource orpheline.
func quit_game() -> void:
	Net.leave()
	Audio.stop_all()
	get_tree().quit.call_deferred()
