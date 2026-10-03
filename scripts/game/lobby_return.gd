class_name LobbyReturn
extends Node
## Retour du groupe au salon après une partie multijoueur, comme dans BO1
## (enfant de Net, chemin réseau /root/Net/LobbyReturn) :
##   1. fin de partie : après l'écran de fin (Game.GAME_OVER_DELAY), le
##      serveur renvoie TOUT le groupe au salon (`srv_return_all` ->
##      `_cl_return` -> Router.back_to_lobby) : la connexion ENet, la liste des
##      joueurs, leurs personnages, la carte et les réglages du salon restent ;
##   2. chaque machine, une fois dans l'écran du salon, le dit au serveur
##      (`report_in_lobby` -> `_srv_in_lobby`) ; tant qu'un joueur n'est pas
##      revenu, le serveur refuse de relancer (`can_start`, bouton DÉMARRER
##      grisé avec la raison) : un ordre de chargement ne croise jamais un
##      retour au salon en cours ;
##   3. l'hôte qui ferme la session (QUITTER au salon ou en partie) prévient
##      les invités (`srv_notify_closing` -> `_cl_host_closing`) avant de couper :
##      ils reviennent au menu avec un message clair au lieu d'attendre la
##      perte de connexion.
## Serveur autoritaire : `_cl_*` n'est accepté que de l'hôte (« authority »),
## `_srv_in_lobby` seulement d'un joueur connu attendu au salon.

## La liste des joueurs pas encore revenus au salon a changé (serveur).
signal changed

## Serveur : joueurs pas encore revenus au salon (pid -> true).
var away: Dictionary = {}


## Oubli complet (fin de session : Net._reset_peer).
func reset() -> void:
	away.clear()


# ------------------------------------------------------------------ serveur

## Serveur : fin de partie, tout le groupe revient au salon.
func srv_return_all() -> void:
	if not multiplayer.is_server() or not Net.is_online():
		return
	away.clear()
	for pid in Net.players:
		away[pid] = true
	print("[LobbyReturn] retour au salon de %d joueur(s)" % away.size())
	changed.emit()
	_cl_return.rpc()


## Serveur : un joueur parti n'est plus attendu au salon.
func srv_peer_left(pid: int) -> void:
	if away.erase(pid):
		changed.emit()


## Tout le groupe est revenu au salon ? [ok, raison lisible].
func can_start() -> Array:
	if away.is_empty():
		return [true, ""]
	var names := []
	for pid in Net.sorted_peer_ids():
		if away.has(pid):
			names.append(Net.player_name(pid))
	return [false, Lang.t("Retour au salon de : %s", "Coming back to the lobby: %s") % ", ".join(names)]


## Serveur (hôte qui part, des invités connectés) : prévient tout le monde.
## L'appelant envoie le message (ENetConnection.flush) avant de couper
## (Net.leave).
func srv_notify_closing() -> void:
	if multiplayer.is_server() and Net.mode == Net.Mode.HOST:
		_cl_host_closing.rpc()


@rpc("any_peer", "call_local", "reliable")
func _srv_in_lobby() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not Net.players.has(sender) or not away.has(sender):
		return
	away.erase(sender)
	print("[LobbyReturn] %s est revenu au salon (%d attendu(s))" % [Net.player_name(sender), away.size()])
	changed.emit()


# ------------------------------------------------------------------ toutes les machines

## Écran du salon affiché : on le dit au serveur (sans effet hors retour).
func report_in_lobby() -> void:
	if Net.is_online():
		_srv_in_lobby.rpc_id(1)


@rpc("authority", "call_local", "reliable")
func _cl_return() -> void:
	if not Net.is_online():
		return
	# Déjà au salon (retour en double) : on le redit simplement au serveur.
	if GameState.state == GameState.State.LOBBY:
		report_in_lobby()
		return
	# En partie, ou encore en chargement (arrivé en retard) : retour au salon.
	if GameState.state == GameState.State.LOADING or GameState.is_in_game():
		Router.back_to_lobby()


@rpc("authority", "reliable")
func _cl_host_closing() -> void:
	if Net.mode != Net.Mode.CLIENT:
		return
	print("[LobbyReturn] l'hôte ferme la session")
	Net.end_session(Lang.t("L'hôte a quitté la partie.", "The host left the game."))
