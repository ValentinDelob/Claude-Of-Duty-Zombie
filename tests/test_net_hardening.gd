extends TestCase
## Durcissement réseau et chargement des cartes : noms et registre des joueurs
## reçus nettoyés, identifiants de carte bornés (jamais un chemin), pair muet
## coupé, bonjour en double ignoré, chargement signalé par un inconnu ignoré,
## objets jamais décodés, dossiers et noms de modèles filtrés, atouts et armes
## vérifiés dans les bases du jeu.

const SHA := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


func test_clean_name() -> void:
	@warning_ignore("static_called_on_instance")
	assert_eq(Net._clean_name("\u202eAB\u0007C\nD\u200b"), "ABC D", "contrôles retirés")
	@warning_ignore("static_called_on_instance")
	assert_eq(Net._clean_name("   "), "Survivant")
	@warning_ignore("static_called_on_instance")
	assert_eq(Net._clean_name("A".repeat(40)).length(), 16, "16 caractères")
	@warning_ignore("static_called_on_instance")
	assert_eq(Net._clean_name("\u2066\u2069\u007f"), "Survivant", "que des contrôles")


func test_clean_players() -> void:
	var many := {}
	for i in 20:
		many[i + 2] = {"name": "J%d" % i, "slot": i}
	@warning_ignore("static_called_on_instance")
	var out := Net.clean_players(many)
	assert_eq(out.size(), Net.MAX_SUPPORTED_PLAYERS, "8 entrées au plus")
	for pid in out:
		assert_true(pid is int and out[pid].slot >= 0 and out[pid].slot < Net.MAX_SUPPORTED_PLAYERS, "place bornée")
	@warning_ignore("static_called_on_instance")
	var odd := Net.clean_players({"1": {"name": "x"}, 3: "pas un dict", 4: {"name": "[b]\u202eMéchant\u0001", "slot": 99}, -2: {"name": "y"}})
	assert_eq(odd.keys(), [4], "clés entières positives seulement")
	assert_eq(odd[4].slot, Net.MAX_SUPPORTED_PLAYERS - 1)
	assert_eq(odd[4].name, "[b]Méchant", "contrôles retirés du nom")
	@warning_ignore("static_called_on_instance")
	assert_true(Net.clean_players("n'importe quoi").is_empty())


func test_map_ids_bounded() -> void:
	for ok in ["bunker_k7", "kino", "perso:ma_carte", "partage:" + SHA]:
		assert_true(CustomMapGuard.game_map_id_ok(ok), "accepté : " + ok)
	for bad in ["../../etc/passwd", "perso:../x", "perso:a/b", "perso:c:\\x", "perso:", "perso:.cache", "partage:zz", "partage:" + SHA.to_upper(),
			"partage:../" + SHA, "res://scripts/boot.gd", "x".repeat(200)]:
		assert_false(CustomMapGuard.game_map_id_ok(bad), "refusé : " + bad)
	assert_false(Game.has_map("perso:../../etc"), "has_map : pas de chemin")
	assert_true(Game.make_map_def("perso:..\\x") == null, "make_map_def : pas de chemin")
	assert_false(Game.has_map("partage:" + SHA), "hash absent du cache")
	# Chargement ordonné par l'hôte.
	assert_true(Net.can_load_map("bunker_k7"))
	assert_false(Net.can_load_map(42), "pas un texte")
	assert_false(Net.can_load_map("partage:" + SHA), "carte partagée absente")
	assert_false(Net.can_load_map("../kino"))
	assert_false(Net.can_load_map("inconnue"), "carte hors registre")


func test_asset_names_and_ids() -> void:
	assert_true(CustomMapGuard.asset_name_ok("seat_broken_a"))
	for bad in ["../x", "a/b", "", "x.glb", "res://x", "a b"]:
		assert_false(CustomMapGuard.asset_name_ok(bad), "nom de modèle refusé : " + bad)
	assert_true(CustomMapGuard.perk_ok("titan") and CustomMapGuard.perk_ok("lazarus"))
	assert_false(CustomMapGuard.perk_ok("../boot") or CustomMapGuard.perk_ok(3) or CustomMapGuard.perk_ok(""))
	assert_true(CustomMapGuard.weapon_ok("m14") and CustomMapGuard.weapon_ok("bowie"))
	assert_false(CustomMapGuard.weapon_ok("raygun_9000") or CustomMapGuard.weapon_ok(null))


func test_models_dir_filtered() -> void:
	var def_dir := MeshMapBuilder.new({}, "").models_dir
	for bad in ["user://evil/", "res://assets/models/../../scripts/", "C:/Windows/", "res://scripts/", "res://assets/models/x\\..\\y/"]:
		assert_eq(MeshMapBuilder.new({"models_dir": bad}, "").models_dir, def_dir, "dossier refusé : " + bad)
	assert_eq(MeshMapBuilder.new({"models_dir": "res://assets/models/perks"}, "").models_dir, "res://assets/models/perks/", "dossier accepté")
	var b := MeshMapBuilder.new({}, "")
	assert_true(b._model("../../scripts/boot") == null, "modèle hors du dossier refusé")
	assert_true(b._collision_boxes("../x").is_empty())


func test_no_object_decoding() -> void:
	assert_false((Net.multiplayer as SceneMultiplayer).allow_object_decoding, "objets jamais décodés")


func test_hello_and_loaded_from_unknown_ignored() -> void:
	var saved := Net.players.duplicate(true)
	# Hors RPC, l'expéditeur vaut 0 : un « joueur » 0 déjà présent.
	Net.players = {0: {"name": "Premier", "slot": 0}}
	@warning_ignore("static_called_on_instance")
	Net._srv_hello("Second", Net.PROTOCOL_VERSION, Net.build_version())
	assert_eq(Net.players[0].name, "Premier", "second bonjour ignoré")
	Net.players = {}
	Net.loaded_peers.clear()
	Net._srv_loaded()
	assert_true(Net.loaded_peers.is_empty(), "chargement d'un inconnu ignoré")
	Net.players = saved


func test_silent_peer_dropped() -> void:
	var port := 17961 + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()
	var saved_timeout := Net.hello_timeout_sec
	Net.hello_timeout_sec = 0.6
	assert_eq(Net.host(port, 4, "Hote"), OK, "hébergement")
	# Un pair ENet brut qui se connecte mais ne se présente jamais.
	var c := ENetConnection.new()
	c.create_host(1)
	# Même compression que l'hôte (Net.host), sinon la poignée de main ENet échoue.
	c.compress(ENetConnection.COMPRESS_RANGE_CODER)
	# Données de connexion : l'identifiant du pair (≥ 2), comme ENetMultiplayerPeer.
	c.connect_to_host("127.0.0.1", port, 0, 424242)
	var connected := false
	var dropped := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000 and not dropped:
		var ev := c.service(0)
		if ev[0] == ENetConnection.EVENT_CONNECT:
			connected = true
		elif ev[0] == ENetConnection.EVENT_DISCONNECT:
			dropped = true
		await wait_frames(1)
	c.destroy()
	Net.leave()
	Net.hello_timeout_sec = saved_timeout
	assert_true(connected, "pair connecté au transport")
	assert_true(dropped, "pair muet coupé par l'hôte")
