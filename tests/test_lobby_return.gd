extends TestCase
## Fin de partie multijoueur : retour du groupe au salon (LobbyReturn,
## Net.end_match, transitions de GameState) et remise à zéro de l'état.

const PORT := 17822


func before_each() -> void:
	Net.leave()
	GameState.reset_to_menu()
	Router.return_scene = ""


func after_each() -> void:
	Net.leave()
	GameState.reset_to_menu()
	Router.return_scene = ""


func test_game_over_returns_to_lobby_then_relaunches() -> void:
	for s in [GameState.State.LOBBY, GameState.State.LOADING, GameState.State.PLAYING, GameState.State.GAME_OVER]:
		assert_true(GameState.set_state(s), "-> %s" % GameState.state_name(s))
	assert_true(GameState.set_state(GameState.State.LOBBY), "GAME_OVER -> LOBBY")
	assert_true(GameState.set_state(GameState.State.LOADING), "LOBBY -> LOADING (partie suivante)")


func test_end_match_forgets_the_match_only() -> void:
	assert_eq(Net.host(PORT, 4, "Hote"), OK)
	Net.players[7] = {"name": "Invite", "slot": 1, "char": "orlov"}
	Net.lobby_map = "kino"
	Net.match_started = true
	Net.loaded_peers = {1: true, 7: true}
	Net.cast = {1: 0, 7: 1}
	Net.current_map = "kino"
	Net.end_match()
	assert_false(Net.match_started, "nouveaux arrivants acceptés au salon")
	assert_true(Net.loaded_peers.is_empty())
	assert_true(Net.cast.is_empty())
	assert_eq(Net.current_map, "")
	# La session et le salon restent.
	assert_eq(Net.mode, Net.Mode.HOST)
	assert_eq(Net.players.size(), 2)
	assert_eq(String(Net.players[7].char), "orlov", "choix de personnage gardé")
	assert_eq(Net.lobby_map, "kino", "carte du salon gardée")
	assert_true(Net.multiplayer.multiplayer_peer is ENetMultiplayerPeer, "connexion gardée")


func test_return_waits_for_the_whole_group() -> void:
	assert_eq(Net.host(PORT, 4, "Hote"), OK)
	Net.players[7] = {"name": "Invite", "slot": 1}
	var lr := Net.lobby_return
	var changes := [0]
	var cb := func(): changes[0] += 1
	lr.changed.connect(cb)
	# État hors partie : l'ordre de retour ne change pas de scène.
	lr.srv_return_all()
	assert_eq(lr.away.keys().size(), 2, "tout le groupe attendu au salon")
	var st := lr.can_start()
	assert_false(st[0])
	assert_true(String(st[1]).contains("Hote") and String(st[1]).contains("Invite"), String(st[1]))
	assert_false(Net.start_match("test_arena"), "relance refusée tant que le groupe n'est pas revenu")
	assert_false(Net.match_started)
	# L'hôte arrive au salon (appel local) : il n'est plus attendu.
	lr.report_in_lobby()
	assert_false(lr.away.has(1))
	assert_true(lr.away.has(7))
	# L'invité part : il ne bloque plus personne.
	Net._on_peer_disconnected(7)
	assert_true(lr.away.is_empty())
	assert_true(lr.can_start()[0])
	lr.changed.disconnect(cb)
	assert_true(changes[0] >= 3, "changements signalés (%d)" % changes[0])


func test_unknown_or_unexpected_sender_ignored() -> void:
	assert_eq(Net.host(PORT, 4, "Hote"), OK)
	var lr := Net.lobby_return
	# Pas de retour en cours : rien à effacer, aucun effet.
	lr.report_in_lobby()
	assert_true(lr.away.is_empty())
	lr.away = {1: true, 9: true}
	# Joueur inconnu parti : on l'oublie, sans erreur.
	lr.srv_peer_left(42)
	assert_eq(lr.away.size(), 2)


func test_leave_resets_return_state() -> void:
	assert_eq(Net.host(PORT, 4, "Hote"), OK)
	Net.lobby_return.away = {1: true, 7: true}
	Net.leave()
	assert_true(Net.lobby_return.away.is_empty())
	assert_eq(Net.mode, Net.Mode.NONE)
	# Sans invité connecté, le port est libéré tout de suite.
	assert_eq(Net.host(PORT, 4, "Hote"), OK)


func test_only_online_matches_return_to_lobby() -> void:
	assert_false(Game.returns_to_lobby(), "hors session")
	Net.start_solo("Solo")
	assert_false(Game.returns_to_lobby(), "solo : retour au menu")
	Net.leave()
	assert_eq(Net.host(PORT, 4, "Hote"), OK)
	assert_true(Game.returns_to_lobby(), "multijoueur : retour au salon")
	Router.return_scene = MapEditor.SCENE
	assert_false(Game.returns_to_lobby(), "TESTER à plusieurs : retour dans l'éditeur")


func test_end_session_only_for_a_client() -> void:
	var got := []
	var cb := func(r): got.append(r)
	Net.session_ended.connect(cb)
	Net.end_session("x")
	assert_eq(Net.host(PORT, 4, "Hote"), OK)
	Net.end_session("x")
	Net.session_ended.disconnect(cb)
	assert_true(got.is_empty(), "ni hors session ni pour l'hôte")
	assert_eq(Net.mode, Net.Mode.HOST)
