extends Node
## Net — couche réseau de la session (Host / Client / Solo).
##
## Principes :
## * Le serveur (peer 1) est l'autorité sur tout ce qui est critique.
## * Le SOLO utilise un OfflineMultiplayerPeer : le joueur local EST le serveur,
##   exactement le même code de gameplay tourne qu'en multijoueur.
## * Convention RPC du projet :
##     - requête client -> serveur : @rpc("any_peer", "call_local", ...) + rpc_id(1, ...)
##       (fonctionne aussi quand l'appelant est le serveur lui-même)
##     - diffusion serveur -> tous : @rpc("authority", "call_local", ...) + rpc(...)

const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 4
const MAX_SUPPORTED_PLAYERS := 8
## Incrémenter à chaque changement incompatible du protocole réseau.
const PROTOCOL_VERSION := 4
const CONNECT_TIMEOUT_SEC := 8.0

enum Mode { NONE, SOLO, HOST, CLIENT }

signal players_changed
## Le client est accepté par le serveur (après la poignée de main).
signal joined_server
## Échec de connexion ou refus du serveur. `title` et `message` sont destinés à l'UI.
signal connection_error(title: String, message: String)
## La session s'est terminée (perte de connexion, hôte parti...).
signal session_ended(reason: String)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
## Serveur : une connexion a été refusée (plein, partie lancée, version).
signal peer_rejected(peer_id: int, reason: String)

var mode: Mode = Mode.NONE
var max_players := DEFAULT_MAX_PLAYERS
var port := DEFAULT_PORT
var server_address := ""
## peer_id -> { "name": String, "slot": int }
var players: Dictionary = {}
## Le serveur refuse les nouveaux arrivants une fois la partie lancée.
var match_started := false

var _connect_timer: Timer
var _handshake_done := false
## Envoi des cartes perso de l'hôte aux invités (chemin réseau /root/Net/MapShare).
var map_share: MapShare


func _ready() -> void:
	map_share = MapShare.new()
	map_share.name = "MapShare"
	add_child(map_share)
	# Jamais d'objet décodé depuis le réseau (un objet peut porter un script).
	(multiplayer as SceneMultiplayer).allow_object_decoding = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Settings.changed.connect(send_character)
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)


# --------------------------------------------------------------------------
# API publique
# --------------------------------------------------------------------------

func start_solo(nickname: String) -> void:
	_reset_peer()
	mode = Mode.SOLO
	max_players = 1
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: {"name": _clean_name(nickname), "slot": 0}}
	match_started = false
	print("[Net] partie solo (pair hors-ligne)")
	players_changed.emit()


func host(host_port: int, wanted_max_players: int, nickname: String) -> Error:
	_reset_peer()
	if not is_valid_port(host_port):
		connection_error.emit(Lang.t("Hébergement impossible", "Cannot host"), Lang.t("Port invalide : %d (1024-65535).", "Invalid port: %d (1024-65535).") % host_port)
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	# On accepte plus de connexions ENet que de places : le refus « serveur plein »
	# est géré au niveau applicatif pour pouvoir envoyer un message clair.
	var err := peer.create_server(host_port, MAX_SUPPORTED_PLAYERS + 2)
	if err != OK:
		var msg := Lang.t("Le port %d est peut-être déjà utilisé par un autre programme.", "Port %d may already be used by another program.") % host_port
		connection_error.emit(Lang.t("Hébergement impossible", "Cannot host"), msg)
		push_warning("[Net] create_server a échoué (%s)" % error_string(err))
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	port = host_port
	max_players = clampi(wanted_max_players, 1, MAX_SUPPORTED_PLAYERS)
	players = {1: {"name": _clean_name(nickname), "slot": 0}}
	match_started = false
	print("[Net] serveur hébergé sur le port %d (max %d joueurs)" % [port, max_players])
	players_changed.emit()
	return OK


func join(address: String, join_port: int, nickname: String) -> Error:
	_reset_peer()
	address = address.strip_edges()
	if not is_valid_ipv4(address):
		connection_error.emit(Lang.t("Adresse invalide", "Invalid address"),
			Lang.t("« %s » n'est pas une adresse IPv4 valide.\nExemple : 192.168.1.25", "\"%s\" is not a valid IPv4 address.\nExample: 192.168.1.25") % address)
		return ERR_INVALID_PARAMETER
	if not is_valid_port(join_port):
		connection_error.emit(Lang.t("Port invalide", "Invalid port"), Lang.t("Le port doit être compris entre 1024 et 65535.", "The port must be between 1024 and 65535."))
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, join_port)
	if err != OK:
		connection_error.emit(Lang.t("Connexion impossible", "Cannot connect"), Lang.t("Impossible d'initialiser la connexion réseau (%s).", "Could not start the network connection (%s).") % error_string(err))
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	server_address = address
	port = join_port
	players = {}
	_handshake_done = false
	lobby_map = ""
	_pending_name = _clean_name(nickname)
	_connect_timer.start(CONNECT_TIMEOUT_SEC)
	print("[Net] connexion à %s:%d..." % [address, join_port])
	return OK


# --------------------------------------------------------------------------
# Lancement de partie et barrière de chargement
# --------------------------------------------------------------------------

const GAME_SCENE := "res://scenes/game.tscn"

## Serveur : tous les joueurs ont fini de charger la carte.
signal all_loaded

## peers ayant signalé la fin de leur chargement (serveur uniquement).
var loaded_peers: Dictionary = {}


## Carte de la partie en cours (choisie par le serveur).
var current_map := ""
## Personnages de la partie en cours : pid -> index dans CharacterDB.IDS.
## Calculé par l'hôte au lancement (CharacterDB.resolve_cast : choix de chaque
## joueur, rotation tirée pour les « automatique », 0 pendant les tests
## automatiques : emplacement 0 = Callahan) et reçu avec l'ordre de chargement.
var cast: Dictionary = {}
## Client : dernier choix de personnage envoyé à l'hôte (voir send_character).
var _sent_character := ""


## Carte choisie par l'hôte dans le salon (affichée aux clients).
var lobby_map := ""
signal lobby_map_changed(map_id: String)


## Serveur (salon) : annonce la carte choisie à tous les joueurs (les nouveaux
## arrivants la reçoivent aussi, voir _srv_hello). Carte perso « perso:<id> » :
## contrôlée, mise en paquet et envoyée automatiquement aux invités (MapShare) ;
## la carte du salon devient « partage:<sha256> ». {ok, reasons} : refusée si
## la carte ne passe pas le contrôle (rien n'est annoncé).
func set_lobby_map(map_id: String) -> Dictionary:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return {"ok": false, "reasons": []}
	if map_id.begins_with(EditorMapDef.CUSTOM_PREFIX):
		var r := map_share.srv_offer_local(map_id)
		if not r.ok:
			return r
		_cl_lobby_map.rpc(EditorMapDef.SHARED_PREFIX + String(r.sha))
		return r
	map_share.srv_clear()
	_cl_lobby_map.rpc(map_id)
	return {"ok": true, "reasons": []}


@rpc("authority", "call_local", "reliable")
func _cl_lobby_map(map_id: Variant) -> void:
	# Identifiant borné : texte court, carte du registre ou hash de carte perso.
	if not (map_id is String and map_id.length() <= 80 and CustomMapGuard.game_map_id_ok(map_id)):
		return
	lobby_map = map_id
	lobby_map_changed.emit(map_id)


## Carte que cette machine accepte de charger sur ordre de l'hôte : carte du
## registre, carte perso partagée présente dans le cache ; une carte perso
## locale « perso:<id> » seulement pour l'hôte lui-même (solo, TESTER).
func can_load_map(map_id: Variant) -> bool:
	if not (map_id is String and map_id.length() <= 80 and CustomMapGuard.game_map_id_ok(map_id)):
		return false
	if Game.MAP_SCRIPTS.has(map_id):
		return true
	if map_id.begins_with(EditorMapDef.SHARED_PREFIX):
		return Game.has_map(map_id)
	return map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) and multiplayer.is_server()


## Serveur : ordonne à tout le monde de charger la partie sur `map_id`. Carte
## perso partagée : seulement quand TOUS les joueurs ont confirmé l'avoir
## (MapShare.can_start) ; faux sinon (rien n'est envoyé).
func start_match(map_id: String) -> bool:
	if not multiplayer.is_server():
		return false
	if map_id.begins_with(EditorMapDef.SHARED_PREFIX):
		var st := map_share.can_start()
		if map_share.offer.get("sha", "") != map_id.trim_prefix(EditorMapDef.SHARED_PREFIX) or not st[0]:
			print("[Net] lancement refusé : %s" % (st[1] if st[1] != "" else "carte non annoncée"))
			return false
	elif map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) and players.size() > 1:
		# Les invités n'ont pas les cartes de l'hôte : passer par set_lobby_map.
		print("[Net] lancement refusé : carte perso non partagée")
		return false
	match_started = true
	loaded_peers.clear()
	_cl_load_game.rpc(map_id, srv_resolve_cast(0 if Autotest.active else randi() % CharacterDB.IDS.size()))
	return true


## Serveur : distribution des personnages de la partie qui se lance (choix
## de l'hôte lu dans ses réglages, ceux des invités reçus par
## _srv_set_character).
func srv_resolve_cast(rotation: int) -> Dictionary:
	if players.has(1):
		players[1]["char"] = CharacterDB.clean_choice(Settings.character)
	return CharacterDB.resolve_cast(players, rotation)


@rpc("authority", "call_local", "reliable")
func _cl_load_game(map_id: Variant, new_cast: Variant = {}) -> void:
	# Carte inconnue, identifiant invalide, carte partagée absente ou refusée
	# ici : on ne charge jamais autre chose (la partie serait désynchronisée).
	if not can_load_map(map_id):
		var was := mode
		_reset_peer()
		if was == Mode.CLIENT:
			connection_error.emit(Lang.t("Carte absente", "Missing map"),
				Lang.t("La carte de l'hôte n'a pas pu être vérifiée sur cette machine.", "The host's map could not be verified on this computer."))
		return
	match_started = true
	current_map = map_id
	cast = CharacterDB.clean_cast(new_cast)
	GameState.set_state(GameState.State.LOADING)
	get_tree().change_scene_to_file(GAME_SCENE)


## Appelé par chaque machine quand sa scène de jeu est prête.
func report_loaded() -> void:
	_srv_loaded.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _srv_loaded() -> void:
	if not multiplayer.is_server():
		return
	# Seulement un joueur accepté (pas un pair encore muet ou refusé).
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	loaded_peers[sender] = true
	if is_everyone_loaded():
		all_loaded.emit()


func is_everyone_loaded() -> bool:
	for id in players:
		if not loaded_peers.has(id):
			return false
	return true


## Quitte proprement la session (depuis n'importe quel mode).
func leave() -> void:
	if mode == Mode.NONE:
		return
	print("[Net] fin de session (%s)" % Mode.keys()[mode])
	_reset_peer()


func is_server() -> bool:
	return multiplayer.is_server()


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.CLIENT


func local_id() -> int:
	return multiplayer.get_unique_id()


func player_name(peer_id: int) -> String:
	return players.get(peer_id, {}).get("name", Lang.t("Joueur %d", "Player %d") % peer_id)


func player_slot(peer_id: int) -> int:
	return players.get(peer_id, {}).get("slot", 0)


func sorted_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in players.keys():
		ids.append(id)
	ids.sort_custom(func(a, b): return player_slot(a) < player_slot(b))
	return ids


## Adresses IPv4 locales utilisables par les autres joueurs du réseau local.
static func local_ipv4_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if is_valid_ipv4(a) and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	# Box domestique (192.168.x) d'abord, puis 10.x, puis 172.16-31 (souvent
	# des cartes virtuelles : WSL, Hyper-V, VPN), puis le reste.
	var ranked := PackedStringArray()
	for pass_i in 4:
		for a in out:
			var rank := 3
			if a.begins_with("192.168."):
				rank = 0
			elif a.begins_with("10."):
				rank = 1
			elif _is_172_private(a):
				rank = 2
			if rank == pass_i:
				ranked.append(a)
	return ranked


static func is_valid_ipv4(address: String) -> bool:
	if address == "localhost":
		return true
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if p.is_empty() or p.length() > 3 or not p.is_valid_int():
			return false
		var v := p.to_int()
		if v < 0 or v > 255:
			return false
	return true


static func is_valid_port(p: int) -> bool:
	return p >= 1024 and p <= 65535


static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var second := a.split(".")[1].to_int()
	return second >= 16 and second <= 31


# --------------------------------------------------------------------------
# Poignée de main
# --------------------------------------------------------------------------

var _pending_name := ""


func _on_connected_to_server() -> void:
	# Connexion ENet établie : on se présente au serveur, qui peut encore refuser.
	print("[Net] connecté au transport, envoi du hello")
	_srv_hello.rpc_id(1, _pending_name, PROTOCOL_VERSION, build_version())
	# Choix de personnage dans un message à part, juste après (même canal
	# fiable : il arrive après le bonjour). Le bonjour garde sa forme pour
	# qu'un hôte d'une autre version puisse toujours répondre « version
	# différente ».
	_sent_character = CharacterDB.clean_choice(Settings.character)
	_srv_set_character.rpc_id(1, _sent_character)


## Client : renvoie son choix de personnage à l'hôte s'il a changé depuis le
## dernier envoi (OPTIONS > JEU, au salon ou en partie : pris en compte au
## prochain lancement). Appelé à chaque Settings.changed.
func send_character() -> void:
	if mode != Mode.CLIENT or not _handshake_done:
		return
	var c := CharacterDB.clean_choice(Settings.character)
	if c != _sent_character:
		_sent_character = c
		_srv_set_character.rpc_id(1, c)


## Serveur : choix de personnage d'un joueur accepté (identifiant inconnu ou
## valeur d'un autre type : « auto »). Nom choisi pour être trié APRÈS les
## RPC existants de Net : les numéros des RPC (ordre alphabétique) d'avant
## restent les mêmes, le bonjour d'une autre version est toujours compris.
@rpc("any_peer", "reliable")
func _srv_set_character(choice: Variant) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		players[sender]["char"] = CharacterDB.clean_choice(choice)


@rpc("any_peer", "reliable")
func _srv_hello(wanted_name: Variant, version: Variant, build_v: Variant) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Un seul bonjour par joueur (un second ne change ni nom ni place).
	if players.has(sender):
		return
	if not wanted_name is String:
		wanted_name = ""
	var build := String(build_v).left(32) if build_v is String else "?"
	# Motif en français puis en anglais sur deux lignes : chaque client garde
	# celle de sa langue (pick_reason) ; une ancienne version affiche les deux.
	var reason := ""
	if not version is int or version != PROTOCOL_VERSION:
		reason = "Version incompatible (hôte v%d, vous v%s).\nIncompatible version (host v%d, you v%s)." % [PROTOCOL_VERSION, str(version).left(8), PROTOCOL_VERSION, str(version).left(8)]
	elif build != build_version():
		reason = "Version du jeu différente (hôte v%s, vous v%s) : utilisez la même release.\nDifferent game version (host v%s, you v%s): use the same release." % [build_version(), build, build_version(), build]
	elif match_started:
		reason = "La partie a déjà commencé.\nThe game has already started."
	elif players.size() >= max_players:
		reason = "Le serveur est plein (%d/%d joueurs).\nThe server is full (%d/%d players)." % [players.size(), max_players, players.size(), max_players]
	if reason != "":
		print("[Net] refus du peer %d : %s" % [sender, reason])
		_cl_rejected.rpc_id(sender, reason)
		peer_rejected.emit(sender, reason)
		# Laisse le temps au message d'arriver avant de couper.
		get_tree().create_timer(0.3).timeout.connect(func():
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer and sender in multiplayer.get_peers():
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(sender))
		return
	players[sender] = {"name": _unique_name(_clean_name(wanted_name)), "slot": _free_slot(),
		"char": CharacterDB.AUTO}  # choix envoyé juste après : _srv_set_character
	print("[Net] %s a rejoint (peer %d)" % [players[sender].name, sender])
	_cl_welcome.rpc_id(sender, max_players)
	_cl_players.rpc(players)
	# Carte du salon (et carte perso à télécharger) pour le nouvel arrivant.
	map_share.srv_peer_joined(sender)
	if lobby_map != "":
		_cl_lobby_map.rpc_id(sender, lobby_map)
	player_joined.emit(sender)


@rpc("authority", "reliable")
func _cl_welcome(server_max_players: Variant) -> void:
	_connect_timer.stop()
	_handshake_done = true
	max_players = clampi(int(server_max_players), 1, MAX_SUPPORTED_PLAYERS) if server_max_players is int else DEFAULT_MAX_PLAYERS
	print("[Net] accepté par le serveur")
	joined_server.emit()


## Motif de refus « français\nanglais » envoyé par l'hôte : la ligne de la
## langue du joueur (texte d'une seule ligne : rendu tel quel).
static func pick_reason(reason: String) -> String:
	var parts := reason.split("\n")
	if parts.size() != 2:
		return reason
	return Lang.t(parts[0], parts[1])


@rpc("authority", "reliable")
func _cl_rejected(reason: String) -> void:
	_connect_timer.stop()
	_handshake_done = false
	lobby_map = ""
	var peer_was := mode
	_reset_peer()
	if peer_was == Mode.CLIENT:
		connection_error.emit(Lang.t("Connexion refusée", "Connection refused"), pick_reason(reason))


@rpc("authority", "call_local", "reliable")
func _cl_players(new_players: Variant) -> void:
	if multiplayer.is_server():
		players = new_players
	else:
		players = clean_players(new_players)
	players_changed.emit()


## Registre des joueurs reçu de l'hôte, borné : 8 entrées au plus, clés
## entières, noms nettoyés (_clean_name), places 0 à 7.
static func clean_players(v: Variant) -> Dictionary:
	var out := {}
	if not v is Dictionary:
		return out
	for pid in v:
		if out.size() >= MAX_SUPPORTED_PLAYERS:
			break
		var p: Variant = v[pid]
		if not (pid is int and pid > 0 and p is Dictionary):
			continue
		var n: Variant = p.get("name", "")
		var s: Variant = p.get("slot", 0)
		out[pid] = {"name": _clean_name(n if n is String else "", 24), "slot": clampi(int(s) if (s is int or s is float) else 0, 0, MAX_SUPPORTED_PLAYERS - 1)}
	return out


# --------------------------------------------------------------------------
# Événements du transport
# --------------------------------------------------------------------------

## Délai laissé à un pair pour se présenter (_srv_hello) avant d'être coupé
## (réglable par les tests).
var hello_timeout_sec := 5.0


func _on_peer_connected(id: int) -> void:
	print("[Net] transport : peer %d connecté" % id)
	# Serveur : un pair muet ne garde pas une place ENet.
	if multiplayer.is_server() and mode == Mode.HOST:
		get_tree().create_timer(hello_timeout_sec).timeout.connect(func():
			if mode == Mode.HOST and not players.has(id) and multiplayer.multiplayer_peer is ENetMultiplayerPeer and id in multiplayer.get_peers():
				print("[Net] peer %d coupé : pas de présentation en %d s" % [id, int(hello_timeout_sec)])
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))


func _on_peer_disconnected(id: int) -> void:
	print("[Net] transport : peer %d déconnecté" % id)
	if multiplayer.is_server() and players.has(id):
		print("[Net] %s a quitté la partie" % players[id].name)
		players.erase(id)
		loaded_peers.erase(id)
		# Un joueur qui part pendant le transfert ne bloque pas les autres.
		map_share.srv_peer_left(id)
		_cl_players.rpc(players)
		player_left.emit(id)
		# Un joueur qui part pendant le chargement ne doit pas bloquer les autres.
		if match_started and not loaded_peers.is_empty() and is_everyone_loaded():
			all_loaded.emit()


func _on_connection_failed() -> void:
	_connect_timer.stop()
	_reset_peer()
	connection_error.emit(Lang.t("Connexion impossible", "Cannot connect"),
		Lang.t("Le serveur est inaccessible.\nVérifiez l'adresse IP, le port, et que l'hôte a bien lancé la partie (pare-feu).",
			"The server cannot be reached.\nCheck the IP address, the port, and that the host has started the game (firewall)."))


func _on_connect_timeout() -> void:
	if mode != Mode.CLIENT or _handshake_done:
		return
	_reset_peer()
	connection_error.emit(Lang.t("Délai dépassé", "Timed out"),
		Lang.t("Aucune réponse du serveur après %d secondes.\nLe serveur n'existe pas ou le port est incorrect.",
			"No answer from the server after %d seconds.\nThe server does not exist or the port is wrong.") % int(CONNECT_TIMEOUT_SEC))


func _on_server_disconnected() -> void:
	var was_joined := _handshake_done
	_reset_peer()
	if was_joined:
		session_ended.emit(Lang.t("Connexion perdue avec l'hôte.", "Connection to the host lost."))


# --------------------------------------------------------------------------
# Utilitaires internes
# --------------------------------------------------------------------------

func _reset_peer() -> void:
	_connect_timer.stop()
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players = {}
	loaded_peers = {}
	match_started = false
	_handshake_done = false
	lobby_map = ""
	if map_share:
		map_share.reset()


# --------------------------------------------------------------------------
# Mesure de bande passante (statistiques ENet de l'hôte local)
# --------------------------------------------------------------------------

var _bw_t := -1.0

## Octets et paquets UDP envoyés / reçus par CETTE machine depuis l'appel
## précédent (après compression, en-têtes ENet compris, hors IP/UDP), avec la
## durée écoulée `dt`. Remet les compteurs d'ENet à zéro : un seul appelant.
## Vide hors ENet (solo).
func sample_bandwidth() -> Dictionary:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.host == null:
		return {}
	var h := peer.host
	var t := Time.get_ticks_usec() / 1000000.0
	var d := {
		"sent": h.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
		"recv": h.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA),
		"sent_packets": h.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS),
		"recv_packets": h.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS),
		"dt": t - _bw_t if _bw_t >= 0.0 else 0.0,
	}
	_bw_t = t
	return d


func _free_slot() -> int:
	var used := {}
	for p in players.values():
		used[p.slot] = true
	for s in MAX_SUPPORTED_PLAYERS:
		if not used.has(s):
			return s
	return players.size()


func _unique_name(n: String) -> String:
	var taken := {}
	for p in players.values():
		taken[p.name] = true
	if not taken.has(n):
		return n
	var i := 2
	while taken.has("%s (%d)" % [n, i]):
		i += 1
	return "%s (%d)" % [n, i]


## Nom de joueur affichable : sans caractère de contrôle (C0, DEL, marques et
## contrôles bidirectionnels), 16 caractères (`max_len`) au plus.
static func _clean_name(n: String, max_len := 16) -> String:
	var out := ""
	for i in n.length():
		var c := n.unicode_at(i)
		if c == 10 or c == 9:
			out += " "
		elif c < 0x20 or c == 0x7F or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069):
			continue
		else:
			out += n[i]
	out = out.strip_edges()
	if out.is_empty():
		out = "Survivant"
	return out.substr(0, max_len)


## Numéro de build (inscrit par tools/release.sh dans chaque .exe publié) :
## hôte et clients doivent avoir exactement la même release.
static func build_version() -> String:
	# Tests : simuler un joueur d'une autre release.
	var fake := OS.get_environment("AUTOTEST_FAKE_BUILD")
	if fake != "":
		return fake
	return str(ProjectSettings.get_setting("application/config/version", "0"))
