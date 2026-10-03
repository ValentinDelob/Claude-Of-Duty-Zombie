extends AutotestScenario
## [MP] Hôte : fin de partie en multijoueur, le groupe reste ensemble (BO1).
## Salon sur une carte perso (envoyée à l'invité), partie 1 jouée jusqu'au
## GAME OVER (tous morts) : après l'écran de fin, hôte et invité reviennent au
## SALON, toujours connectés (mêmes identifiants de pairs), personnage de
## l'invité, carte et réglages du salon gardés. Relance d'une seconde partie
## (carte reprise du cache de l'invité, sans renvoi) : état de partie neuf
## (points, manche, atouts, zombies, courant), puis second GAME OVER et second
## retour au salon, sans fuite de nœuds ni de connexions de signaux.

var PORT := 17821 + MpHelpers.port_offset()
const MAP := "perso:arene_rematch"

## Mesures prises au salon après chaque retour (fuites).
var _marks: Array = []


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _client_id() -> int:
	for pid in Net.players:
		if pid != 1:
			return pid
	return 0


func _in_lobby() -> bool:
	var s := tree().current_scene
	return s is MainMenu and (s as MainMenu).current_name == "lobby" and GameState.state == GameState.State.LOBBY


func _in_game() -> bool:
	return Game.instance != null and Game.instance.players.size() == 2 and Game.instance.local_player != null \
		and GameState.state == GameState.State.PLAYING


## Nombre de connexions des signaux des autoloads touchés par une partie.
static func signal_links() -> Dictionary:
	var out := {}
	for pair in [["Net", Net], ["GameState", GameState], ["Settings", Settings], ["MapShare", Net.map_share],
			["LobbyReturn", Net.lobby_return], ["Audio", Audio]]:
		var n := 0
		for s in (pair[1] as Object).get_signal_list():
			n += (pair[1] as Object).get_signal_connection_list(s.name).size()
		out[pair[0]] = n
	return out


func _mark() -> Dictionary:
	return {"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "links": signal_links()}


## Partie lancée depuis le salon, jouée puis perdue (tous morts) ; retour au
## salon. `n` : numéro de la partie.
func _play_and_lose(n: int, cid: int, first_sha: String) -> bool:
	var lobby = tree().current_scene.current
	if not await until(func(): return not lobby._start.disabled, 20.0, "DÉMARRER actif (partie %d)" % n):
		return false
	lobby._on_start()
	if not await until(_in_game, 40.0, "partie %d : les deux joueurs en jeu" % n):
		return false
	var game := Game.instance
	game.rounds.paused = true
	var hpd := game.session.local_data()
	var cpd := game.session.get_data(cid)
	# État de départ : neuf à chaque partie.
	at.check(hpd.points == PlayerData.STARTING_POINTS and cpd.points == PlayerData.STARTING_POINTS and hpd.kills == 0,
		"partie %d : points de départ (%d / %d)" % [n, hpd.points, cpd.points])
	at.check(hpd.perks.is_empty() and hpd.weapons.size() == 1 and hpd.life == PlayerData.Life.ALIVE, "partie %d : ni atout, une arme, vivant" % n)
	at.check(game.rounds.round_n <= 1 and game.zombies.alive.is_empty() and not game.power_on, "partie %d : manche %d, aucun zombie, courant coupé" % [n, game.rounds.round_n])
	at.check(game.map_def.id == first_sha, "partie %d sur la carte perso partagée (%s)" % [n, game.map_def.id.substr(0, 20)])
	at.check(Net.cast.get(cid, -1) == CharacterDB.IDS.find("orlov"), "partie %d : personnage choisi par l'invité gardé (%s)" % [n, str(Net.cast.get(cid))])
	MpHelpers.signal_peer("en_jeu%d" % n)
	if not await MpHelpers.wait_peer(self, "en_jeu%d" % n, 30.0):
		return false
	# De quoi salir l'état de la partie : points, manche, atouts.
	hpd.points = 9000 + n
	hpd.perks.append("juggernog")
	game.rounds.debug_jump_to(4)
	await seconds(0.5)
	var old: WeakRef = weakref(game)
	# Fin de partie réelle : tout le monde meurt.
	game.kill_player(cid)
	game.kill_player(1)
	if not await until(func(): return GameState.state == GameState.State.GAME_OVER, 5.0, "GAME OVER %d" % n):
		return false
	at.check(true, "partie %d : GAME OVER (tous morts)" % n)
	if n == 1:
		await at.screenshot("game_over")
	# Écran de fin, puis retour au salon (pas au menu principal).
	if not await until(_in_lobby, Game.GAME_OVER_DELAY + 15.0, "retour au salon après la partie %d" % n):
		return false
	at.check(Net.mode == Net.Mode.HOST and Net.players.has(1) and Net.players.has(cid) and Net.players.size() == 2,
		"retour %d : toujours hôte, même groupe (%s)" % [n, str(Net.players.keys())])
	at.check(Net.multiplayer.multiplayer_peer is ENetMultiplayerPeer and Array(Net.multiplayer.get_peers()) == [cid],
		"retour %d : connexion ENet gardée, même pair (%s)" % [n, str(Net.multiplayer.get_peers())])
	at.check(Game.instance == null and not Net.match_started and Net.loaded_peers.is_empty() and Net.cast.is_empty(),
		"retour %d : partie oubliée (Net.end_match)" % n)
	lobby = tree().current_scene.current
	at.check(lobby.is_host and lobby.map_id == MAP and Net.lobby_map == first_sha, "retour %d : carte du salon gardée (%s)" % [n, Net.lobby_map.substr(0, 20)])
	at.check(String(Net.players[cid].get("char", "")) == "orlov", "retour %d : choix de personnage de l'invité gardé" % n)
	var col_texts := []
	for c in lobby.find_children("*", "Label", true, false):
		col_texts.append(c.text)
	at.check(" ".join(col_texts).contains(Lang.t("Dernière partie", "Last game")), "retour %d : résumé de la partie au salon" % n)
	if n == 1:
		await seconds(1.0)
		await at.screenshot("lobby_after_game")
	# L'ancienne scène de jeu est entièrement libérée.
	await frames(10)
	at.check(old.get_ref() == null, "retour %d : scène de la partie libérée" % n)
	# Mesure des fuites une fois le salon posé (fondus finis).
	await seconds(2.0)
	_marks.append(_mark())
	return true


func run() -> void:
	timeout_sec = 200
	_rm(EditorMap.maps_root())
	_rm(CustomMapGuard.cache_root())
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.carte["id"] = "arene_rematch"
	m.carte["nom"] = {"fr": "ARÈNE REVANCHE", "en": "REMATCH ARENA"}
	at.check(m.save_dir(EditorMap.map_dir("arene_rematch")) == OK, "carte perso enregistrée")
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	menu.show_screen("host")
	await frames(3)
	menu.current._port.text = str(PORT)
	menu.current._name.text = "Hote"
	MpHelpers._clear_sync()
	menu.current._create()
	await frames(3)
	var lobby = menu.current
	at.check(menu.current_name == "lobby", "salon de l'hôte")
	var idx: int = lobby.map_ids.find(MAP)
	# ► jusqu'à la carte perso (comme au clavier).
	while idx > 0 and lobby.map_row.index() != idx:
		lobby.map_row.nudge(1)
	at.check(lobby.map_id == MAP and Net.lobby_map.begins_with(EditorMapDef.SHARED_PREFIX), "carte perso choisie (%s)" % Net.lobby_map.substr(0, 20))
	var first_sha := Net.lobby_map
	MpHelpers.signal_peer("ecoute")
	if not await until(func(): return Net.players.size() == 2, 40.0, "arrivée de l'invité"):
		return
	var cid := _client_id()
	if not await MpHelpers.wait_peer(self, "salon", 30.0):
		return
	if not await _play_and_lose(1, cid, first_sha):
		return
	var sent := Net.map_share.sent_chunks
	if not await MpHelpers.wait_peer(self, "salon1", 30.0):
		return
	MpHelpers.signal_peer("salon1")
	if not await _play_and_lose(2, cid, first_sha):
		return
	at.check(Net.map_share.sent_chunks == sent, "carte reprise du cache de l'invité, sans renvoi (%d morceaux)" % (Net.map_share.sent_chunks - sent))
	# Aucune fuite d'une partie à l'autre.
	var a: Dictionary = _marks[0]
	var b: Dictionary = _marks[1]
	at.check(b.orphans <= a.orphans, "pas de nœud orphelin de plus (%d -> %d)" % [a.orphans, b.orphans])
	at.check(absi(b.nodes - a.nodes) <= 10, "même nombre de nœuds au salon (%d -> %d)" % [a.nodes, b.nodes])
	at.check(b.links == a.links, "mêmes connexions de signaux des autoloads (%s -> %s)" % [str(a.links), str(b.links)])
	if not await MpHelpers.wait_peer(self, "salon2", 30.0):
		return
	await MpHelpers.finish(self)
