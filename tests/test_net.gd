extends TestCase

func after_each() -> void:
	Net.leave()


func test_ipv4_validation() -> void:
	@warning_ignore("static_called_on_instance")
	assert_true(Net.is_valid_ipv4("192.168.1.25"))
	@warning_ignore("static_called_on_instance")
	assert_true(Net.is_valid_ipv4("127.0.0.1"))
	@warning_ignore("static_called_on_instance")
	assert_true(Net.is_valid_ipv4("localhost"))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_ipv4("256.1.1.1"))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_ipv4("192.168.1"))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_ipv4("a.b.c.d"))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_ipv4(""))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_ipv4("1.2.3.4.5"))


func test_port_validation() -> void:
	@warning_ignore("static_called_on_instance")
	assert_true(Net.is_valid_port(7777))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_port(80))
	@warning_ignore("static_called_on_instance")
	assert_false(Net.is_valid_port(70000))


func test_solo_is_server() -> void:
	Net.start_solo("  Testeur  ")
	assert_eq(Net.mode, Net.Mode.SOLO)
	assert_true(Net.is_server())
	assert_eq(Net.local_id(), 1)
	assert_eq(Net.player_name(1), "Testeur")
	Net.leave()
	assert_eq(Net.mode, Net.Mode.NONE)
	assert_true(Net.players.is_empty())


func test_host_and_leave_frees_port() -> void:
	assert_eq(Net.host(17777, 4, "Hote"), OK)
	assert_eq(Net.mode, Net.Mode.HOST)
	assert_eq(Net.players.size(), 1)
	Net.leave()
	# Le port doit être réutilisable immédiatement.
	assert_eq(Net.host(17777, 4, "Hote"), OK)


## L'hôte qui part AVEC des invités garde son pair ouvert HOST_CLOSING_DELAY
## (avis de départ) : QUITTER puis HÉBERGER aussitôt sur le même port doit
## réussir (l'ancien pair est fermé avant la nouvelle session).
func test_host_with_guest_leave_then_host_again() -> void:
	var port := 17971 + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()
	assert_eq(Net.host(port, 4, "Hote"), OK, "hébergement")
	# Un pair ENet brut connecté au transport (vu par Net comme un invité).
	var c := ENetConnection.new()
	c.create_host(1)
	c.compress(ENetConnection.COMPRESS_RANGE_CODER)
	c.connect_to_host("127.0.0.1", port, 0, 424243)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000 and Net.multiplayer.get_peers().is_empty():
		c.service(0)
		await wait_frames(1)
	assert_false(Net.multiplayer.get_peers().is_empty(), "invité connecté")
	Net.leave()
	assert_true(Net._closing_peer != null, "départ avec invité : ancien pair encore ouvert (avis de départ)")
	assert_eq(Net.host(port, 4, "Hote"), OK, "HÉBERGER aussitôt sur le même port")
	assert_true(Net._closing_peer == null, "ancien pair fermé avant la nouvelle session")
	assert_eq(Net.mode, Net.Mode.HOST)
	c.destroy()
	# L'échéance prévue pour l'ancien pair ne ferme pas le nouveau.
	await wait_seconds(Net.HOST_CLOSING_DELAY + 0.15)
	var now := Net.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	assert_true(now != null and now.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "nouveau serveur toujours ouvert")
	assert_eq(Net.mode, Net.Mode.HOST)


func test_join_invalid_address_reports_error() -> void:
	var errors := []
	var cb := func(t, _m): errors.append(t)
	Net.connection_error.connect(cb)
	Net.join("999.1.1.1", 7777, "X")
	Net.connection_error.disconnect(cb)
	assert_eq(errors, ["Adresse invalide"])
	assert_eq(Net.mode, Net.Mode.NONE)


func test_join_nobody_listening_reports_error() -> void:
	var errors := []
	var cb := func(t, _m): errors.append(t)
	Net.connection_error.connect(cb)
	Net.join("127.0.0.1", 17999, "X")
	var t := 0.0
	while errors.is_empty() and t < Net.CONNECT_TIMEOUT_SEC + 4.0:
		await wait_seconds(0.25)
		t += 0.25
	Net.connection_error.disconnect(cb)
	assert_eq(errors.size(), 1, "une erreur de connexion attendue")
	assert_eq(Net.mode, Net.Mode.NONE)


func test_name_cleaning() -> void:
	@warning_ignore("static_called_on_instance")
	assert_eq(Net._clean_name(""), "Survivant")
	@warning_ignore("static_called_on_instance")
	assert_eq(Net._clean_name("abcdefghijklmnopqrstuvwxyz").length(), 16)
