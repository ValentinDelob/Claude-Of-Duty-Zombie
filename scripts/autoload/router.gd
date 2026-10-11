extends Node
## Router — enchaînement des écrans (menu <-> partie) et fin de session.

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Message à afficher par le menu à son retour (ex. « Connexion perdue »).
var pending_message := ""
## Onglet du hub où le menu revient après une partie ("" : menu titre) :
## « lab » après une partie solo (LABO, « dernière partie »), « play » en
## multijoueur (onglet PARTIE : salon, ou héberger / rejoindre). Lu une fois
## par MainMenu (docs/HUB_PLAN.md §2).
var hub_tab := ""
## Scène où revenir à la fin de la partie au lieu du menu (partie lancée par
## le bouton Tester de l'éditeur de cartes), "" : menu principal.
var return_scene := ""
## Résumé de la dernière partie, affiché par le salon au retour (multijoueur).
var lobby_message := ""
## Dernière partie du joueur local, pour le LABO du hub (« DERNIÈRE PARTIE ») :
## {"result": MatchResult, "map": nom affiché, "solo": bool} ; {} : aucune
## depuis le lancement du jeu. Rempli par Game._show_match_end.
var last_match := {}


func start_solo(map_id := "") -> void:
	Net.start_solo(Settings.player_name)
	Net.start_match(map_id if map_id != "" else Game.requested_map())


## Quitte la session en cours et revient au menu : au hub, onglet `tab`
## (« lab », « play »), ou au menu titre (`tab` vide).
func back_to_menu(reason := "", tab := "") -> void:
	pending_message = reason
	hub_tab = tab
	lobby_message = ""
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
		hub_tab = ""
	get_tree().change_scene_to_file.call_deferred(target)
	if GameState.state == GameState.State.DISCONNECTING:
		GameState.set_state(GameState.State.MAIN_MENU)


## Onglet du hub où revenir en quittant la partie en cours : LABO en solo,
## PARTIE en multijoueur (pour héberger ou rejoindre à nouveau).
func hub_tab_after_match() -> String:
	return "play" if Net.mode == Net.Mode.HOST or Net.mode == Net.Mode.CLIENT else "lab"


## Fin d'une partie multijoueur (ordre du serveur : LobbyReturn._cl_return) :
## retour au SALON avec tout le groupe, sans couper la session (connexion,
## joueurs, personnages, carte et réglages du salon gardés) : le salon est
## l'onglet PARTIE du hub (MainMenu). La scène de jeu est libérée en entier
## (points, manche, armes, zombies) : la partie suivante recharge tout. Hors
## ligne (solo) : retour au hub, onglet LABO.
func back_to_lobby() -> void:
	if not Net.is_online():
		back_to_menu(lobby_message, "lab")
		return
	if not GameState.set_state(GameState.State.LOBBY):
		GameState.reset_to_menu()
		GameState.set_state(GameState.State.LOBBY)
	Net.end_match()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.stop_music(1.0)
	print("[Router] retour au salon (%s, %d joueur(s))" % [Net.Mode.keys()[Net.mode], Net.players.size()])
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


## Quitte le jeu proprement (session, sons) : aucune ressource orpheline.
func quit_game() -> void:
	Net.leave()
	Audio.stop_all()
	get_tree().quit.call_deferred()
