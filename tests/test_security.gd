extends TestCase
## Sécurité (docs/SECURITY.md) : valeurs réseau piégées (NaN, infini,
## tableaux immenses, noms-chemins), vraisemblance des déplacements et des
## explosions revendiqués, inondation de requêtes, fichiers de réglages
## piégés (objets et ressources décodés par ConfigFile = exécution de code).

const TMP_CFG := "user://security_unittest.cfg"
const TMP_SCRIPT := "user://security_unittest_pwn.gd"
const META := "security_unittest_pwned"
const SAVED := ["player_name", "fov", "mouse_sensitivity", "invert_y", "language", "last_port", "master_volume"]

var _saved := {}


func before_each() -> void:
	for k in SAVED:
		_saved[k] = Settings.get(k)
	if Engine.has_meta(META):
		Engine.remove_meta(META)


func after_each() -> void:
	for k in SAVED:
		Settings.set(k, _saved[k])
	for f in [TMP_CFG, TMP_SCRIPT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	if Engine.has_meta(META):
		Engine.remove_meta(META)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ------------------------------------------------------------------ réseau

func test_player_state_rejects_non_finite_positions() -> void:
	var ok := NetCodec.encode_player_state(Vector3(1, 2, 3), 0.5, 0.1, 9)
	assert_eq(NetCodec.decode_player_state(ok).size(), 4, "état normal lu")
	for bad in [Vector3(NAN, 0, 0), Vector3(0, INF, 0), Vector3(0, 0, -INF), Vector3(1e9, 0, 0)]:
		var buf := NetCodec.encode_player_state(Vector3.ZERO, 0.0, 0.0, 0)
		buf.encode_float(0, bad.x)
		buf.encode_float(4, bad.y)
		buf.encode_float(8, bad.z)
		assert_true(NetCodec.decode_player_state(buf).is_empty(), "position %s refusée" % bad)


func test_rpc_never_decode_objects() -> void:
	# Un objet reçu dans un RPC = exécution de code : doit rester interdit.
	var mp := host.get_tree().get_multiplayer() as SceneMultiplayer
	assert_true(mp != null and not mp.allow_object_decoding, "allow_object_decoding désactivé")


func test_fx_decoding_drops_non_finite_values() -> void:
	var buf := PackedByteArray()
	NetCodec.append_shot(buf, 2, "m1911", false, Vector3(NAN, 0, 0), PackedVector3Array([Vector3.ONE, Vector3.UP]), PackedVector3Array())
	NetCodec.append_shot(buf, 2, "m1911", false, Vector3.ZERO, PackedVector3Array([Vector3(INF, 0, 0), Vector3.UP, Vector3.ONE, Vector3.UP]), PackedVector3Array([Vector3(NAN, 1, 1)]))
	var fx := NetCodec.decode_fx(buf)
	assert_eq(fx.size(), 1, "tir à l'origine NaN ignoré")
	assert_eq(fx[0].impacts.size(), 0, "impacts coupés au premier non fini")
	assert_eq(fx[0].blood.size(), 0, "taches de sang non finies ignorées")


func test_guard_helpers() -> void:
	assert_true(NetGuard.finite_vec(Vector3(1, -2, 3)))
	assert_false(NetGuard.finite_vec(Vector3(NAN, 0, 0)))
	assert_false(NetGuard.finite_vec(Vector3(0, 0, INF)))
	assert_false(NetGuard.valid_dir(Vector3.ZERO), "direction nulle")
	assert_true(NetGuard.valid_dir(Vector3(0, 0, -1)))
	var big := PackedVector3Array()
	big.resize(10000)
	assert_eq(NetGuard.clean_vecs(big, 128, true).size(), 128, "tableau borné")
	assert_eq(NetGuard.clean_vecs(PackedVector3Array([Vector3.ONE, Vector3.UP, Vector3.ONE]), 10, true).size(), 2, "paires complètes seulement")
	for bad in ["", "../x", "a/b", "res:x", "A", "a.b", "x".repeat(100)]:
		assert_false(NetGuard.safe_token(bad), "nom refusé : %s" % bad)
	assert_true(NetGuard.safe_token("perk_juggernog_2"))


func test_limiter() -> void:
	var l := NetGuard.Limiter.new(10.0, 5.0)
	var n := 0
	for i in 50:
		if l.allow(7, 100.0):
			n += 1
	assert_eq(n, 5, "rafale bornée")
	assert_true(l.allow(7, 100.2), "jetons regagnés avec le temps")
	assert_true(l.allow(8, 100.0), "autre joueur indépendant")


## Débit propre à chaque message (cadence de tir de Combat : arme en main).
func test_limiter_take_with_own_rate() -> void:
	var l := NetGuard.Limiter.new(0.0, 4.0)
	var n := 0
	for i in 10:
		if l.take(1, 10.0, 8.0):
			n += 1
	assert_eq(n, 4, "rafale de 4 jetons")
	assert_false(l.take(1, 10.1, 8.0), "0,8 jeton regagné en 0,1 s : refusé")
	assert_true(l.take(1, 10.2, 8.0), "1,6 jeton cumulé : accepté")
	assert_false(l.take(1, 10.3, 2.0), "débit plus lent : 0,8 jeton")
	l.forget(1)
	assert_true(l.take(1, 10.3, 2.0), "oublié : seau plein")


## Tirs d'un seau de cadence de Combat : `n` tirs réguliers à `rate` coups/s
## à partir de `t0`, dont ceux d'un à-coup de `stall` s (réseau, serveur
## chargé) arrivent tous ensemble à sa fin. Retourne le nombre de refus.
func _fire_refusals(rate: float, n: int, stall: float, client_rate := -1.0) -> int:
	var l := NetGuard.Limiter.new(0.0, Combat.FIRE_BURST_TOKENS)
	var sent := rate if client_rate < 0.0 else client_rate
	var refused := 0
	for i in n:
		var t := 1.0 + i / sent
		if t > 1.5 and t < 1.5 + stall:
			t = 1.5 + stall
		if not l.take(1, t, rate * 1.25, Combat.fire_burst(rate)):
			refused += 1
	return refused


## FAUCHEUSE (20 coups/s) : un à-coup de 0,3 s regroupait 6 tirs, au-delà de
## la rafale fixe de 4 jetons (tir d'un client honnête refusé, mp_powerups).
func test_fast_weapon_tolerates_jitter_but_not_cheating() -> void:
	var dm := 1.0 / WeaponDB.fire_interval("death_machine")
	assert_near(dm, 20.0, 0.01, "FAUCHEUSE : 1200 coups/min")
	assert_eq(_fire_refusals(dm, 40, 0.3), 0, "à-coup de 0,3 s : aucun tir refusé")
	assert_true(_fire_refusals(dm, 200, 0.0, dm * 1.5) > 10, "cadence 1,5x tenue : refusée")
	var pistol := 1.0 / WeaponDB.fire_interval("m1911")
	assert_eq(Combat.fire_burst(pistol), Combat.FIRE_BURST_TOKENS, "arme lente : rafale de 4 tirs inchangée")
	assert_true(_fire_refusals(dm, 40, 0.6) > 0, "à-coup de 0,6 s : au-delà de la tolérance")


func test_splash_must_follow_the_shot() -> void:
	var o := Vector3(0, 1.6, 0)
	var d := Vector3(1, 0, 0)
	assert_true(Combat.plausible_splash(o, d, Vector3.INF), "rien touché")
	assert_true(Combat.plausible_splash(o, d, Vector3(30, 1.6, 0)), "droit devant")
	assert_true(Combat.plausible_splash(o, d, Vector3(40, 1.6, 6)), "dispersion (8,5°)")
	assert_true(Combat.plausible_splash(o, d, Vector3(0.5, 1.6, 1.5)), "à bout portant")
	assert_false(Combat.plausible_splash(o, d, Vector3(-8, 1.6, 0)), "derrière le tireur")
	assert_false(Combat.plausible_splash(o, d, Vector3(20, 1.6, 20)), "45° à côté")
	assert_false(Combat.plausible_splash(o, d, Vector3(400, 1.6, 0)), "hors de portée")
	assert_false(Combat.plausible_splash(o, d, Vector3(NAN, 0, 0)), "NaN")


func test_movement_plausibility() -> void:
	var a := Vector3(0, 0, 0)
	assert_true(Player.plausible_move(a, Vector3(Player.SPRINT_SPEED * 0.05, 0, 0), 0.05), "sprint")
	assert_true(Player.plausible_move(a, Vector3(3.2, 0, 0), 0.15), "fente au couteau")
	assert_true(Player.plausible_move(a, Vector3(7.0, 0, 0), 1.0), "gigue : paquets groupés")
	assert_true(Player.plausible_move(a, Vector3(0, -30, 0), 0.05), "chute (vertical ignoré)")
	assert_true(Player.plausible_move(a, Vector3(40, 0, 0), 3.0), "long gel du client")
	assert_false(Player.plausible_move(a, Vector3(30, 0, 0), 0.05), "téléportation")
	assert_false(Player.plausible_move(a, Vector3(12, 0, 0), 0.2), "vitesse x9")


func test_server_refuses_teleporting_client() -> void:
	var p := Player.new()  # hors de l'arbre : seule la règle du serveur est jouée
	p.peer_id = 5
	var t := Time.get_ticks_usec() / 1000000.0
	assert_true(p._srv_accept_state(Vector3.ZERO, t), "premier état : référence")
	assert_true(p._srv_accept_state(Vector3(0.3, 0, 0), t + 0.05), "pas normal accepté")
	assert_false(p._srv_accept_state(Vector3(60, 0, 0), t + 0.1), "téléportation refusée")
	assert_false(p._srv_accept_state(Vector3(60, 0, 0), t + 0.15), "toujours refusée ensuite")
	assert_true(p._srv_accept_state(Vector3(1.0, 0, 0), t + 0.2), "retour près de la position acceptée")
	p.net_allow_warp()  # téléporteur, réapparition : voulus par le serveur
	assert_true(p._srv_accept_state(Vector3(80, 0, 0), t + 0.25), "saut voulu par le serveur accepté")
	p.free()


# ------------------------------------------------------------------ fichiers

func test_safe_config_rejects_objects_and_resources() -> void:
	for bad in [
		"[p]\nname=Object(RefCounted,\"script\":null)\n",
		"[p]\nname=Resource(\"user://x.gd\")\n",
		"[p]\nname=ExtResource(\"1\")\n",
		"[p]\nname=SubResource(\"a\")\n",
		"[p]\nname=Object ; commentaire\n(RefCounted)\n",
		"[p]\nlist=[1, Object(RefCounted)]\n",
	]:
		assert_true(SafeConfig.unsafe_constructor(bad) != "", "refusé : %s" % bad.c_escape())
		assert_true(SafeConfig.parse_text(bad) == null)
	var good := "[player]\nname=\"Object(1) ; # \\\"Resource(\"\n[bindings]\nfire=PackedStringArray(\"mouse:1\")\n[v]\nc=Color(1, 0, 0, 1)\nx=Vector3(1, 2, 3)\n"
	assert_eq(SafeConfig.unsafe_constructor(good), "", "valeurs simples acceptées")
	var cfg := SafeConfig.parse_text(good)
	assert_true(cfg != null and cfg.get_value("player", "name") == "Object(1) ; # \"Resource(", "texte entre guillemets intact")


func test_settings_file_cannot_run_code() -> void:
	# Script « piège » : s'il était chargé et attaché, il marquerait Engine.
	_write(TMP_SCRIPT, "extends RefCounted\nfunc _init():\n\tEngine.set_meta(\"%s\", true)\n" % META)
	_write(TMP_CFG, "[player]\nname=Object(RefCounted,\"script\":Resource(\"%s\"))\n[video]\nfov=90.0\n" % TMP_SCRIPT)
	var before := Settings.fov
	assert_false(Settings.load_from(TMP_CFG), "fichier piégé ignoré en entier")
	assert_false(Engine.has_meta(META), "aucun code exécuté")
	assert_eq(Settings.fov, before, "réglages inchangés")


func test_settings_values_are_typed_and_bounded() -> void:
	_write(TMP_CFG, "[player]\nname=42\n[controls]\nmouse_sensitivity=\"vite\"\ninvert_y=3\n[video]\nfov=1e9\n[game]\nlanguage=\"xx\"\n[network]\nlast_port=999999\n[audio]\nmaster=-5.0\n")
	Settings.player_name = "Claude"
	Settings.mouse_sensitivity = 0.25
	Settings.invert_y = false
	assert_true(Settings.load_from(TMP_CFG), "fichier lu")
	assert_eq(Settings.player_name, "Claude", "nom : mauvais type -> inchangé")
	assert_eq(Settings.mouse_sensitivity, 0.25, "sensibilité : mauvais type -> inchangée")
	assert_eq(Settings.invert_y, false, "booléen : mauvais type -> inchangé")
	assert_near(Settings.fov, 130.0, 0.001, "champ de vision borné")
	assert_eq(Settings.language, "fr", "langue inconnue -> fr")
	assert_eq(Settings.last_port, 65535, "port borné")
	assert_near(Settings.master_volume, 0.0, 0.001, "volume borné")


func test_career_file_is_read_safely() -> void:
	_write(TMP_SCRIPT, "extends RefCounted\nfunc _init():\n\tEngine.set_meta(\"%s\", true)\n" % META)
	_write(TMP_CFG, "[career]\nkills=Object(RefCounted,\"script\":Resource(\"%s\"))\n" % TMP_SCRIPT)
	assert_true(SafeConfig.load_file(TMP_CFG) == null, "dossier de combat piégé ignoré")
	assert_false(Engine.has_meta(META), "aucun code exécuté")
