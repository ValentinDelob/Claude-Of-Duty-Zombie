extends TestCase
## Utilitaires et garde-fous de Net sans vrai réseau : adresses locales et
## plages privées 172.16-31, refus du bonjour (_srv_hello : version, build,
## partie lancée, serveur plein, appel reçu par un client), noms en double,
## places pleines, choix du personnage (bonjour, _srv_set_character), échec et
## délai de connexion. Les appels passent par une
## instance neuve de net.gd sous `host`, avec son propre SceneMultiplayer :
## l'autoload Net et le pair du jeu ne sont jamais touchés, aucun port ouvert.
## Net est chargé comme simple Node (pas l'autoload) : ses fonctions statiques
## sont appelées sur l'instance, volontairement.
@warning_ignore_start("static_called_on_instance", "incompatible_ternary")

const NET_SCRIPT := "res://scripts/autoload/net.gd"

var _box: Node
var _net: Node


## Pair client factice : identifiant 2, connecté, n'envoie ni ne reçoit rien.
class FakeClientPeer extends MultiplayerPeerExtension:
	func _get_unique_id() -> int:
		return 2
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED
	func _poll() -> void:
		pass
	func _get_available_packet_count() -> int:
		return 0
	func _get_max_packet_size() -> int:
		return 1 << 20
	func _put_packet_script(_p: PackedByteArray) -> Error:
		return OK
	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()
	func _get_packet_peer() -> int:
		return 1
	func _get_packet_channel() -> int:
		return 0
	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _set_transfer_channel(_c: int) -> void:
		pass
	func _get_transfer_channel() -> int:
		return 0
	func _set_transfer_mode(_m: MultiplayerPeer.TransferMode) -> void:
		pass
	func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _set_target_peer(_p: int) -> void:
		pass
	func _is_server() -> bool:
		return false
	func _is_server_relay_supported() -> bool:
		return false
	func _close() -> void:
		pass
	func _disconnect_peer(_p: int, _now: bool) -> void:
		pass
	func _set_refuse_new_connections(_e: bool) -> void:
		pass
	func _is_refusing_new_connections() -> bool:
		return false


## Instance neuve de net.gd dans une branche à part (pair hors-ligne = serveur,
## ou pair client factice).
func _make_net(client := false) -> Node:
	_box = Node.new()
	_box.name = "NetBox"
	host.add_child(_box)
	var mp := SceneMultiplayer.new()
	mp.multiplayer_peer = FakeClientPeer.new() if client else OfflineMultiplayerPeer.new()
	host.get_tree().set_multiplayer(mp, _box.get_path())
	_net = (load(NET_SCRIPT) as GDScript).new()
	_net.name = "NetUnderTest"
	_box.add_child(_net)
	return _net


func after_each() -> void:
	if is_instance_valid(_box):
		host.get_tree().set_multiplayer(null, _box.get_path())
		_box.free()
	_box = null
	_net = null


# ------------------------------------------------------------------ fonctions statiques

func test_is_172_private() -> void:
	for a in ["172.16.0.1", "172.20.5.5", "172.31.255.255"]:
		assert_true(Net._is_172_private(a), a)
	for a in ["172.15.0.1", "172.32.0.1", "10.0.0.1", "192.168.1.1", "172.", "1172.16.0.1", "172.abc.0.1"]:
		assert_false(Net._is_172_private(a), a)


func test_local_ipv4_addresses_ranked() -> void:
	var addrs := Net.local_ipv4_addresses()
	var last_rank := -1
	for a in addrs:
		assert_true(Net.is_valid_ipv4(a), "adresse IPv4 : %s" % a)
		assert_false(a.begins_with("127.") or a.begins_with("169.254."), "ni boucle locale ni lien local : %s" % a)
		var rank := 3
		if a.begins_with("192.168."):
			rank = 0
		elif a.begins_with("10."):
			rank = 1
		elif Net._is_172_private(a):
			rank = 2
		assert_true(rank >= last_rank, "ordre 192.168 / 10 / 172.16-31 / autres : %s" % str(addrs))
		last_rank = rank


# ------------------------------------------------------------------ places et noms

func test_free_slot_when_full() -> void:
	var n := _make_net()
	n.players = {}
	assert_eq(n._free_slot(), 0, "première place libre")
	for i in Net.MAX_SUPPORTED_PLAYERS:
		n.players[i + 1] = {"name": "J%d" % i, "slot": i}
	assert_eq(n._free_slot(), Net.MAX_SUPPORTED_PLAYERS, "toutes les places prises : taille du registre")
	n.players.erase(4)
	assert_eq(n._free_slot(), 3, "place libérée réutilisée")


func test_unique_name_duplicates() -> void:
	var n := _make_net()
	n.players = {1: {"name": "Bob", "slot": 0}}
	assert_eq(n._unique_name("Alice"), "Alice", "nom libre gardé")
	assert_eq(n._unique_name("Bob"), "Bob (2)", "premier doublon")
	n.players[2] = {"name": "Bob (2)", "slot": 1}
	n.players[3] = {"name": "Bob (3)", "slot": 2}
	assert_eq(n._unique_name("Bob"), "Bob (4)", "doublons successifs")


# ------------------------------------------------------------------ bonjour

func _hello_reason(n: Node, wanted: Variant, version: Variant, build: Variant) -> String:
	var got := []
	var cb := func(_pid, reason): got.append(reason)
	n.peer_rejected.connect(cb)
	n._srv_hello(wanted, version, build)
	n.peer_rejected.disconnect(cb)
	return String(got[0]) if not got.is_empty() else ""


func test_hello_rejections() -> void:
	var n := _make_net()
	var bv: String = Net.build_version()
	n.players = {1: {"name": "Hote", "slot": 0}}
	n.max_players = 4
	for bad_v in [Net.PROTOCOL_VERSION + 1, str(Net.PROTOCOL_VERSION), null, 4.5, [4]]:
		assert_true(_hello_reason(n, "X", bad_v, bv).begins_with("Version incompatible"), "version %s refusée" % str(bad_v))
	for bad_b in ["0.0.0-autre", 12, null, "A".repeat(500)]:
		assert_true(_hello_reason(n, "X", Net.PROTOCOL_VERSION, bad_b).begins_with("Version du jeu différente"), "build %s refusé" % str(bad_b).left(12))
	n.match_started = true
	assert_eq(_hello_reason(n, "X", Net.PROTOCOL_VERSION, bv), "La partie a déjà commencé.\nThe game has already started.")
	assert_eq(Net.pick_reason("La partie a déjà commencé.\nThe game has already started."), Lang.t("La partie a déjà commencé.", "The game has already started."))
	assert_eq(Net.pick_reason("Texte seul"), "Texte seul", "motif d'une ligne rendu tel quel")
	n.match_started = false
	n.max_players = 1
	assert_true(_hello_reason(n, "X", Net.PROTOCOL_VERSION, bv).begins_with("Le serveur est plein"), "serveur plein")
	assert_eq(n.players.size(), 1, "aucun joueur ajouté par un refus")


func test_hello_accepted_with_odd_name() -> void:
	var n := _make_net()
	n.players = {1: {"name": "Survivant", "slot": 0}}
	n.max_players = 4
	var joined := []
	n.player_joined.connect(func(pid): joined.append(pid))
	# Nom qui n'est pas un texte : remplacé par le nom par défaut, dédoublonné.
	assert_eq(_hello_reason(n, {"evil": true}, Net.PROTOCOL_VERSION, Net.build_version()), "", "accepté")
	assert_eq(joined.size(), 1, "arrivée signalée")
	var pid: int = joined[0]
	assert_eq(n.players[pid].name, "Survivant (2)", "nom par défaut dédoublonné")
	assert_eq(n.players[pid].slot, 1, "première place libre")
	# Second bonjour du même pair : ignoré.
	n._srv_hello("Autre", Net.PROTOCOL_VERSION, Net.build_version())
	assert_eq(n.players[pid].name, "Survivant (2)", "second bonjour ignoré")


func test_hello_ignored_on_client() -> void:
	var n := _make_net(true)
	assert_false(n.multiplayer.is_server(), "instance côté client")
	n.players = {}
	assert_eq(_hello_reason(n, "X", 0, "x"), "", "aucun refus émis par un client")
	assert_true(n.players.is_empty(), "client : aucun joueur ajouté")


func test_hello_and_character_choice() -> void:
	var n := _make_net()
	n.players = {1: {"name": "Hote", "slot": 0}}
	n.max_players = 4
	# Hors RPC, l'expéditeur vaut 0.
	n._srv_hello("Invite", Net.PROTOCOL_VERSION, Net.build_version())
	assert_eq(n.players[0].char, CharacterDB.AUTO, "avant le choix : automatique")
	n._srv_set_character("mercer")
	assert_eq(n.players[0].char, "mercer", "choix envoyé juste après le bonjour")
	n._srv_set_character("orlov")
	assert_eq(n.players[0].char, "orlov", "choix changé au salon")
	for bad in ["zorg", 7, null, {"x": 1}, "../callahan"]:
		n._srv_set_character(bad)
		assert_eq(n.players[0].char, CharacterDB.AUTO, "valeur invalide -> auto : %s" % str(bad))
	n.players.erase(0)
	n._srv_set_character("orlov")
	assert_false(n.players.has(0), "joueur inconnu (refusé ou pas encore présenté) : ignoré")
	# Le bonjour garde sa forme d'avant (trois valeurs) et _srv_set_character
	# est trié après les RPC existants : leurs numéros ne bougent pas, un hôte
	# d'une autre version répond toujours « version différente ».
	var names: Array = []
	for m in n.get_script().get_rpc_config():
		names.append(String(m))
	names.sort()
	assert_eq(names[-1], "_srv_set_character", "nouveau RPC en dernier : %s" % [names])
	var hello_args := -1
	for m in n.get_method_list():
		if m.name == "_srv_hello":
			hello_args = (m.args as Array).size()
	assert_eq(hello_args, 3, "bonjour à trois valeurs")


# ------------------------------------------------------------------ échecs de connexion

func _errors_of(n: Node, f: Callable) -> Array:
	var got := []
	var cb := func(title, _msg): got.append(title)
	n.connection_error.connect(cb)
	f.call()
	n.connection_error.disconnect(cb)
	return got


func test_connection_failed_resets() -> void:
	var n := _make_net()
	n.mode = Net.Mode.CLIENT
	n.players = {1: {"name": "Hote", "slot": 0}}
	var got := _errors_of(n, n._on_connection_failed)
	assert_eq(got, ["Connexion impossible"])
	assert_eq(n.mode, Net.Mode.NONE, "session remise à zéro")
	assert_true(n.players.is_empty())
	assert_true(n.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "pair hors-ligne remis")


func test_connect_timeout() -> void:
	var n := _make_net()
	n.mode = Net.Mode.NONE
	assert_eq(_errors_of(n, n._on_connect_timeout), [], "hors connexion : rien")
	n.mode = Net.Mode.CLIENT
	n._handshake_done = true
	assert_eq(_errors_of(n, n._on_connect_timeout), [], "déjà accepté : rien")
	assert_eq(n.mode, Net.Mode.CLIENT)
	n._handshake_done = false
	assert_eq(_errors_of(n, n._on_connect_timeout), ["Délai dépassé"], "délai dépassé signalé")
	assert_eq(n.mode, Net.Mode.NONE, "session remise à zéro")
