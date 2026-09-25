extends Node
## GameState — machine à états centrale de la session.
##
## Tous les scripts qui ont besoin de savoir « où en est la partie » lisent
## GameState.state au lieu de maintenir leurs propres booléens implicites.

enum State {
	MAIN_MENU,
	LOBBY,
	CONNECTING,
	LOADING,
	PLAYING,
	ROUND_END,
	PLAYER_DOWN,
	GAME_OVER,
	DISCONNECTING,
}

signal state_changed(previous: State, current: State)

## Transitions autorisées. Toute autre transition est refusée et loguée :
## cela évite les états incohérents difficiles à déboguer.
const TRANSITIONS := {
	State.MAIN_MENU: [State.LOBBY, State.CONNECTING, State.LOADING],
	State.LOBBY: [State.LOADING, State.DISCONNECTING, State.MAIN_MENU],
	State.CONNECTING: [State.LOBBY, State.MAIN_MENU, State.DISCONNECTING],
	State.LOADING: [State.PLAYING, State.DISCONNECTING, State.MAIN_MENU],
	State.PLAYING: [State.ROUND_END, State.PLAYER_DOWN, State.GAME_OVER, State.DISCONNECTING],
	State.ROUND_END: [State.PLAYING, State.PLAYER_DOWN, State.GAME_OVER, State.DISCONNECTING],
	State.PLAYER_DOWN: [State.PLAYING, State.ROUND_END, State.GAME_OVER, State.DISCONNECTING],
	State.GAME_OVER: [State.LOBBY, State.DISCONNECTING, State.MAIN_MENU],
	State.DISCONNECTING: [State.MAIN_MENU],
}

var state: State = State.MAIN_MENU


func set_state(next: State) -> bool:
	if next == state:
		return true
	if not can_transition(state, next):
		push_warning("[GameState] transition refusée %s -> %s" % [state_name(state), state_name(next)])
		return false
	var previous := state
	state = next
	print("[GameState] %s -> %s" % [state_name(previous), state_name(next)])
	state_changed.emit(previous, next)
	return true


## Retour forcé au menu (déconnexion brutale, erreur fatale...).
func reset_to_menu() -> void:
	var previous := state
	state = State.MAIN_MENU
	if previous != State.MAIN_MENU:
		print("[GameState] %s -> MAIN_MENU (reset)" % state_name(previous))
		state_changed.emit(previous, state)


static func can_transition(from: State, to: State) -> bool:
	return to in TRANSITIONS.get(from, [])


static func state_name(s: State) -> String:
	return State.keys()[s]


## Vrai quand le monde de jeu tourne (joueurs, zombies...).
func is_in_game() -> bool:
	return state in [State.PLAYING, State.ROUND_END, State.PLAYER_DOWN, State.GAME_OVER]
