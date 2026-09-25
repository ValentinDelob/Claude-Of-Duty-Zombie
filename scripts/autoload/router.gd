extends Node
## Router — enchaînement des écrans (menu <-> partie) et fin de session.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Message à afficher par le menu à son retour (ex. « Connexion perdue »).
var pending_message := ""


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
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
	if GameState.state == GameState.State.DISCONNECTING:
		GameState.set_state(GameState.State.MAIN_MENU)
