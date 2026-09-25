extends TestCase

func after_each() -> void:
	Net.leave()


func test_ipv4_validation() -> void:
	assert_true(Net.is_valid_ipv4("192.168.1.25"))
	assert_true(Net.is_valid_ipv4("127.0.0.1"))
	assert_true(Net.is_valid_ipv4("localhost"))
	assert_false(Net.is_valid_ipv4("256.1.1.1"))
	assert_false(Net.is_valid_ipv4("192.168.1"))
	assert_false(Net.is_valid_ipv4("a.b.c.d"))
	assert_false(Net.is_valid_ipv4(""))
	assert_false(Net.is_valid_ipv4("1.2.3.4.5"))


func test_port_validation() -> void:
	assert_true(Net.is_valid_port(7777))
	assert_false(Net.is_valid_port(80))
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


func test_join_invalid_address_reports_error() -> void:
	var errors := []
	var cb := func(t, m): errors.append(t)
	Net.connection_error.connect(cb)
	Net.join("999.1.1.1", 7777, "X")
	Net.connection_error.disconnect(cb)
	assert_eq(errors, ["Adresse invalide"])
	assert_eq(Net.mode, Net.Mode.NONE)


func test_join_nobody_listening_reports_error() -> void:
	var errors := []
	var cb := func(t, m): errors.append(t)
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
	assert_eq(Net._clean_name(""), "Survivant")
	assert_eq(Net._clean_name("abcdefghijklmnopqrstuvwxyz").length(), 16)
