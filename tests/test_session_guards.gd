extends TestCase
## Garde-fous de Session : points ajoutés ou dépensés pour un joueur inconnu,
## montant nul ou négatif, réceptions client (_cl_points, _cl_stats,
## _cl_inventory) pour un joueur inconnu, et API serveur appelée par un client.

var s: Session


func before_each() -> void:
	s = Session.new()
	host.add_child(s)


func after_each() -> void:
	if is_instance_valid(s):
		s.free()


func test_add_points_guards() -> void:
	var pd := s.create(1)
	var start := pd.points
	var events := []
	s.points_event.connect(func(pid, delta): events.append([pid, delta]))
	s.add_points(99, 500)
	assert_false(s.data.has(99), "joueur inconnu jamais créé")
	s.add_points(1, 0)
	assert_eq(pd.points, start, "montant nul ignoré")
	assert_true(events.is_empty(), "aucun événement pour un appel ignoré")
	s.add_points(1, -(start + 10000))
	assert_eq(pd.points, 0, "jamais sous zéro")
	s.add_points(1, 50)
	assert_eq(pd.points, 50)
	assert_eq(events.size(), 2, "deux changements réels")


func test_try_spend_guards() -> void:
	var pd := s.create(1)
	pd.points = 100
	assert_false(s.try_spend(42, 10), "joueur inconnu")
	assert_false(s.try_spend(1, 101), "pas assez de points")
	assert_eq(pd.points, 100)
	assert_true(s.try_spend(1, 0), "dépense nulle permise")
	assert_true(s.try_spend(1, 100), "tout dépenser")
	assert_eq(pd.points, 0)
	# Montant négatif : refusé (il créditerait des points).
	assert_false(s.try_spend(1, -30), "montant négatif refusé par try_spend")
	assert_eq(pd.points, 0, "montant négatif : aucun point crédité")


func test_client_handlers_unknown_player() -> void:
	var fired := []
	s.stats_changed.connect(func(pid): fired.append(["stats", pid]))
	s.inventory_changed.connect(func(pid): fired.append(["inv", pid]))
	s.points_event.connect(func(pid, _d): fired.append(["pts", pid]))
	s._cl_points(77, 999, 999)
	s._cl_stats(77, {"points": 5, "max_health": -1})
	s._cl_inventory(77, {"weapons": "n'importe quoi"})
	assert_true(fired.is_empty(), "rien émis pour un joueur inconnu : %s" % str(fired))
	assert_false(s.data.has(77), "joueur inconnu jamais créé")


func test_client_handlers_known_player_on_server() -> void:
	# Sur le serveur (pair hors-ligne), les copies reçues ne remplacent pas
	# les données de référence : seuls les signaux partent.
	var pd := s.create(3)
	pd.points = 10
	var fired := []
	s.stats_changed.connect(func(_pid): fired.append("stats"))
	s.inventory_changed.connect(func(_pid): fired.append("inv"))
	s._cl_stats(3, {"points": 12345})
	s._cl_inventory(3, {})
	assert_eq(pd.points, 10, "stats reçues ignorées par le serveur")
	assert_eq(fired, ["stats", "inv"])
	s._cl_points(3, 70, 60)
	assert_eq(pd.points, 70, "total reçu appliqué")


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


func test_server_api_refused_on_client() -> void:
	var box := Node.new()
	box.name = "ClientBox"
	host.add_child(box)
	var mp := SceneMultiplayer.new()
	mp.multiplayer_peer = FakeClientPeer.new()
	host.get_tree().set_multiplayer(mp, box.get_path())
	var cs := Session.new()
	box.add_child(cs)
	assert_false(cs.multiplayer.is_server(), "session côté client")
	var pd := cs.create(2)
	pd.points = 500
	cs.add_points(2, 100)
	assert_eq(pd.points, 500, "client : add_points ignoré")
	assert_false(cs.try_spend(2, 10), "client : try_spend refusé")
	assert_eq(pd.points, 500)
	# Réception client : les copies du serveur sont appliquées.
	cs._cl_points(2, 40, -460)
	assert_eq(pd.points, 40, "total reçu du serveur appliqué")
	host.get_tree().set_multiplayer(null, box.get_path())
	box.free()
